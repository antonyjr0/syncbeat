import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:syncbeat/features/zepp/embedded_adb.dart';
import 'package:syncbeat/features/zepp/zepp_adb_stream.dart';

Matcher failureCode(String code) =>
    isA<ZeppBootstrapException>().having((error) => error.code, 'code', code);

class FakeConnection extends AdbConnection {
  FakeConnection(AdbCrypto identity) : super('127.0.0.1', 1234, identity);
  final changes = StreamController<bool>.broadcast();
  void Function(AdbStream)? onOpen;
  int opens = 0;
  final destinations = <String>[];
  void Function(AdbStream, String)? onWrite;
  bool alive = true;

  @override
  bool get connected => alive;
  @override
  bool get tlsEnabled => true;
  @override
  Stream<bool> get onConnectionChanged => changes.stream;

  @override
  Future<void> sendMessage(Uint8List data, {bool flush = false}) async {
    final header = ByteData.sublistView(data);
    if (header.getUint32(0, Endian.little) == AdbProtocol.CMD_OPEN) {
      opens++;
      destinations.add(utf8.decode(data.sublist(24)));
      onOpen?.call(openStreams[header.getUint32(4, Endian.little)]!);
    } else if (header.getUint32(0, Endian.little) == AdbProtocol.CMD_WRTE) {
      onWrite?.call(
        openStreams[header.getUint32(4, Endian.little)]!,
        utf8.decode(data.sublist(24)),
      );
    }
  }
}

Future<Object?> invokeEmbedded(String method, [Object? arguments]) async {
  const codec = StandardMethodCodec();
  final reply = Completer<ByteData?>();
  ServicesBinding.instance.channelBuffers.push(
    EmbeddedAdb.channel.name,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    reply.complete,
  );
  return codec.decodeEnvelope((await reply.future)!);
}

class RecordingEmbedded extends EmbeddedAdb {
  RecordingEmbedded(this.fake) : super.forTesting(fake);
  final FakeConnection fake;
  final connectedPorts = <int>[];
  bool refuse = false;
  @override
  Future<void> connect(int port) async {
    connectedPorts.add(port);
    if (refuse) throw StateError('Connection refused');
    fake.alive = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ServicesBinding.instance.channelBuffers.resize(EmbeddedAdb.channel.name, 10);
  late AdbCrypto identity;
  setUpAll(() {
    identity = AdbCrypto();
  });

  for (final scenario in [
    'success',
    'success_eof',
    'unconfirmed',
    'denied',
    'profile',
    'already',
    'no_consent',
  ]) {
    test('guided authorization: $scenario', () async {
      final connection = FakeConnection(identity);
      final adb = EmbeddedAdb.forTesting(connection);
      var granted = scenario == 'already';
      var queries = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EmbeddedAdb.channel, (call) async {
            expect(call.method, 'wirelessDebugAuthorization');
            queries++;
            return {
              'primaryUser': scenario != 'profile',
              'authorized': granted,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(EmbeddedAdb.channel, null),
      );
      connection.onOpen = (stream) {
        stream.remoteId = 10;
        stream.readyForWrite();
        if (scenario.startsWith('success')) granted = true;
        stream.addPayload(
          Uint8List.fromList(
            utf8.encode(
              scenario == 'denied'
                  ? 'Permission refused\n'
                  : 'SYNCBEAT_DEBUG_AUTH_GRANTED_V1\r\n',
            ),
          ),
        );
        if (scenario == 'denied' || scenario == 'success_eof') {
          scheduleMicrotask(stream.close);
        }
      };
      if (scenario.startsWith('success')) {
        await Future.wait([
          adb.authorizeAutomaticActivation(userApproved: true),
          adb.authorizeAutomaticActivation(userApproved: true),
        ]);
        expect(queries, 2);
      } else if (scenario == 'already') {
        await adb.authorizeAutomaticActivation(userApproved: true);
      } else {
        final expected = switch (scenario) {
          'unconfirmed' => 'ADB_GRANT_NOT_CONFIRMED',
          'profile' => 'ADB_GRANT_PROFILE',
          'no_consent' => 'ADB_GRANT_CONSENT_REQUIRED',
          _ => 'ADB_GRANT_FAILED',
        };
        await expectLater(
          adb.authorizeAutomaticActivation(
            userApproved: scenario != 'no_consent',
          ),
          throwsA(failureCode(expected)),
        );
      }
      final shouldOpen = [
        'success',
        'success_eof',
        'unconfirmed',
        'denied',
      ].contains(scenario);
      expect(connection.opens, shouldOpen ? 1 : 0);
      if (shouldOpen) {
        expect(
          connection.destinations.single,
          'shell:pm grant --user 0 com.example.syncbeat android.permission.WRITE_SECURE_SETTINGS && echo SYNCBEAT_DEBUG_AUTH_GRANTED_V1',
        );
      }
      if (scenario == 'no_consent') expect(queries, 0);
      await connection.changes.close();
    });
  }

  for (final activation in [
    'authorization_required',
    'already_enabled',
    'enable_requested',
    'no_wifi',
  ]) {
    test(
      'activation state $activation still permits at most one discovery/connection',
      () async {
        final connection = FakeConnection(identity)..alive = false;
        final adb = RecordingEmbedded(connection);
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(EmbeddedAdb.channel, (call) async {
              calls.add(call.method);
              if (call.method == 'ensureWirelessDebug') return activation;
              return {
                'localAddresses': ['192.0.2.1'],
                'services': [
                  {
                    'name': 'adb-self-connect',
                    'type': '_adb-tls-connect._tcp',
                    'addresses': ['192.0.2.1'],
                    'port': 43210,
                  },
                ],
              };
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(EmbeddedAdb.channel, null),
        );
        if (activation == 'no_wifi') {
          await expectLater(
            adb.connectAutomatically(),
            throwsA(failureCode('ADB_WIFI_REQUIRED')),
          );
          expect(calls, ['ensureWirelessDebug']);
          expect(adb.connectedPorts, isEmpty);
        } else {
          await adb.connectAutomatically();
          expect(calls, ['ensureWirelessDebug', 'discoverConnect']);
          expect(adb.connectedPorts, [43210]);
        }
        await connection.changes.close();
      },
    );
  }

  for (final refuse in [false, true]) {
    test(
      'automatic discovery connects once, without a saved-port fallback; refusal=$refuse',
      () async {
        final connection = FakeConnection(identity)..alive = false;
        final adb = RecordingEmbedded(connection)..refuse = refuse;
        var discoveries = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(EmbeddedAdb.channel, (call) async {
              if (call.method == 'ensureWirelessDebug') {
                return 'authorization_required';
              }
              expect(call.method, 'discoverConnect');
              discoveries++;
              return {
                'localAddresses': ['192.0.2.1'],
                'services': [
                  {
                    'name': 'adb-self-connect',
                    'type': '_adb-tls-connect._tcp',
                    'addresses': ['192.0.2.1'],
                    'port': 43210,
                  },
                ],
              };
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(EmbeddedAdb.channel, null),
        );
        final preparing = Future.wait([
          adb.connectAutomatically(),
          adb.connectAutomatically(),
        ]);
        if (refuse) {
          await expectLater(preparing, throwsStateError);
        } else {
          await preparing;
        }
        expect(discoveries, 1);
        expect(adb.connectedPorts, [43210]);
        expect(connection.opens, 0);
        await connection.changes.close();
      },
    );
  }

  test(
    'B1 status survives ADB loss and bootstrap sends credential only on stdin',
    () async {
      final connection = FakeConnection(identity);
      final adb = EmbeddedAdb.forTesting(connection);
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      Socket? peer;
      String? credential;
      var bootstrapCalls = 0;
      var directConnections = 0;
      final accepted = server.listen((socket) {
        directConnections++;
        peer = socket;
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final id = line.split('|').first;
              final command = line.substring(line.indexOf('|') + 1);
              if (command.startsWith('AUTH ')) {
                final valid = command.substring(5) == credential;
                socket.write('$id|${valid ? 'OK' : 'ERR'}\n');
              } else {
                socket.write('$id|STATUS:1:2000:5678\n');
              }
            }, onError: (_) {});
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EmbeddedAdb.channel, (call) async {
            expect(call.method, 'bootstrap');
            bootstrapCalls++;
            return {'apkPath': '/data/app/test/base.apk', 'user': 0};
          });
      connection.onOpen = (stream) {
        stream.remoteId = 10;
        stream.readyForWrite();
        stream.addPayload(
          Uint8List.fromList(utf8.encode('SYNCBEAT_DIRECT_INPUT_V1\n')),
        );
      };
      connection.onWrite = (stream, line) {
        credential = line.trim();
        stream.readyForWrite();
        stream.addPayload(
          Uint8List.fromList(
            utf8.encode('SYNCBEAT_DIRECT_READY_V1:${server.port}\n'),
          ),
        );
      };
      try {
        await Future.wait([adb.prepareOnOpen(), adb.prepareOnOpen()]);
        expect(adb.startupFailed.value, isFalse);
        final status = await adb.offlineStatus();
        expect(status.pid, 5678);
        expect(connection.opens, 1);
        expect(bootstrapCalls, 1);
        expect(directConnections, 1);
        expect(connection.destinations.single.contains(credential!), isFalse);
        expect(
          connection.destinations.single.contains('--direct-status-v1'),
          isTrue,
        );
        connection.alive = false;
        connection.changes.add(false);
        await adb
            .prepareOnOpen(); // Foreground observation cannot retry startup.
        expect(adb.ready, isFalse);
        expect((await adb.offlineStatus()).pid, 5678);
        expect((await adb.offlineStatus()).uid, 2000);
        expect(connection.opens, 1);
        expect(bootstrapCalls, 1);
        expect(directConnections, 1);
      } finally {
        peer?.destroy();
        await accepted.cancel();
        await server.close();
        await connection.changes.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(EmbeddedAdb.channel, null);
      }
    },
  );

  test(
    'failed startup discovers once and does not bootstrap or retry',
    () async {
      final connection = FakeConnection(identity)..alive = false;
      final adb = EmbeddedAdb.forTesting(connection);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EmbeddedAdb.channel, (call) async {
            calls.add(call.method);
            if (call.method == 'ensureWirelessDebug') {
              return 'authorization_required';
            }
            return {
              'localAddresses': ['192.0.2.1'],
              'services': [],
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(EmbeddedAdb.channel, null),
      );
      await Future.wait([adb.prepareOnOpen(), adb.prepareOnOpen()]);
      await adb.prepareOnOpen();
      expect(calls, ['ensureWirelessDebug', 'discoverConnect']);
      expect(adb.startupFailed.value, isTrue);
      expect(connection.opens, 0);
      await adb.prepareOnForeground();
      expect(calls, [
        'ensureWirelessDebug',
        'discoverConnect',
        'ensureWirelessDebug',
        'discoverConnect',
      ], reason: 'Only a new opening may attempt preparation again');
      await connection.changes.close();
    },
  );

  test(
    'concurrent preparation launches once and recovery reuses that socket',
    () async {
      final connection = FakeConnection(identity);
      final adb = EmbeddedAdb.forTesting(connection);
      adb.register();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            EmbeddedAdb.channel,
            (call) async => call.method == 'bootstrap'
                ? {'apkPath': '/data/app/test/base.apk', 'user': 0}
                : null,
          );
      connection.onOpen = (stream) {
        stream.remoteId = 10 + stream.localId;
        stream.readyForWrite();
        if (connection.opens == 1) {
          stream.addPayload(
            Uint8List.fromList(utf8.encode('SYNCBEAT_READY_V1\n')),
          );
          stream.close();
        }
      };
      connection.onWrite = (stream, text) {
        stream.readyForWrite();
        stream.addPayload(
          Uint8List.fromList(utf8.encode('${text.split('|').first}|OK\n')),
        );
      };
      try {
        await Future.wait([
          invokeEmbedded('prepare'),
          invokeEmbedded('prepare'),
        ]);
        expect(connection.opens, 2);
        await invokeEmbedded('restore', false);
        expect(connection.opens, 2);
      } finally {
        connection.alive = false;
        connection.changes.add(false);
        await Future<void>.delayed(Duration.zero);
        await connection.changes.close();
        EmbeddedAdb.channel.setMethodCallHandler(null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(EmbeddedAdb.channel, null);
      }
    },
  );

  test('failed bootstrap followed by recovery never launches again', () async {
    final connection = FakeConnection(identity);
    final adb = EmbeddedAdb.forTesting(connection);
    adb.register();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          EmbeddedAdb.channel,
          (call) async => {'apkPath': '/data/app/test/base.apk', 'user': 0},
        );
    connection.onOpen = (stream) => stream.close();
    try {
      await expectLater(
        invokeEmbedded('begin', 20000),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'ADB_OPEN_REFUSED',
          ),
        ),
      );
      await expectLater(
        invokeEmbedded('restore', false),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'ADB_RECOVERY_UNAVAILABLE',
          ),
        ),
      );
      expect(connection.opens, 1);
      await expectLater(
        invokeEmbedded('prepare'),
        throwsA(isA<PlatformException>()),
      );
      expect(connection.opens, 2);
    } finally {
      await connection.changes.close();
      EmbeddedAdb.channel.setMethodCallHandler(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EmbeddedAdb.channel, null);
    }
  });

  test('immediate READY is buffered before the caller subscribes', () async {
    final connection = FakeConnection(identity);
    connection.onOpen = (stream) {
      stream.remoteId = 10;
      stream.readyForWrite();
      stream.addPayload(Uint8List.fromList(utf8.encode('SYNCBEAT_READY_V1\n')));
      stream.close();
    };
    final launch = await ZeppAdbStream.open(connection, 1, 'shell:test');
    await waitForZeppReady(launch.onPayload);
    await launch.close();
    expect(connection.opens, 1);
    expect(connection.openStreams, isEmpty);
    await connection.changes.close();
  });

  test(
    'refusal is immediate and distinct from a silent peer timeout',
    () async {
      final connection = FakeConnection(identity);
      connection.onOpen = (stream) => stream.close();
      await expectLater(
        ZeppAdbStream.open(connection, 1, 'localabstract:test'),
        throwsA(failureCode('ADB_OPEN_REFUSED')),
      );
      connection.onOpen = null;
      final timeout = expectLater(
        ZeppAdbStream.open(connection, 2, 'localabstract:test'),
        throwsA(failureCode('ADB_OPEN_TIMEOUT')),
      );
      await timeout;
      expect(connection.opens, 2);
      expect(connection.openStreams, isEmpty);
      await connection.changes.close();
    },
  );

  test('transport loss during OPEN is distinct from refusal', () async {
    final connection = FakeConnection(identity);
    connection.onOpen = (_) {
      connection.alive = false;
      connection.changes.add(false);
    };
    await expectLater(
      ZeppAdbStream.open(connection, 1, 'localabstract:test'),
      throwsA(failureCode('ADB_TRANSPORT_LOST')),
    );
    expect(connection.openStreams, isEmpty);
    await connection.changes.close();
  });

  test('slow and split READY waits for the complete signal', () async {
    final payload = StreamController<List<int>>();
    var ready = false;
    final waiting = waitForZeppReady(payload.stream).then((_) => ready = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(ready, isFalse);
    payload.add(utf8.encode('SYNCBEAT_RE'));
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    payload.add(utf8.encode('ADY_V1\n'));
    await Future<void>.delayed(Duration.zero);
    await waiting;
    expect(ready, isTrue);
    await payload.close();
  });

  test(
    'EOF and timeout before READY are distinct and late READY has no effect',
    () async {
      await expectLater(
        waitForZeppReady(const Stream<List<int>>.empty()),
        throwsA(failureCode('ADB_BOOTSTRAP_EXITED')),
      );
      final payload = StreamController<List<int>>();
      var completed = false;
      final timeout = expectLater(
        waitForZeppReady(payload.stream).then((_) => completed = true),
        throwsA(failureCode('ADB_READY_TIMEOUT')),
      );
      await Future<void>.delayed(const Duration(seconds: 5));
      await timeout;
      payload.add(utf8.encode('SYNCBEAT_READY_V1\n'));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      await payload.close();
    },
  );
}
