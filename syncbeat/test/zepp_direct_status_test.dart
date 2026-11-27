import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/zepp/zepp_adb_stream.dart';
import 'package:syncbeat/features/zepp/zepp_direct_status.dart';

Matcher failureCode(String code) =>
    isA<ZeppBootstrapException>().having((error) => error.code, 'code', code);

void main() {
  test(
    'credential is written only after the input marker; READY may be split',
    () async {
      final output = StreamController<List<int>>();
      var writes = 0;
      final credential = base64Encode(List.filled(32, 17));
      final preparing = exchangeDirectStatusBootstrap(output.stream, (
        line,
      ) async {
        writes++;
        expect(line == '$credential\n', isTrue);
        output.add(utf8.encode('SYNCBEAT_DIRECT_RE'));
        output.add(utf8.encode('ADY_V1:43210\n'));
        return true;
      }, credential);
      await Future<void>.delayed(Duration.zero);
      expect(writes, 0);
      output.add(utf8.encode('SYNCBEAT_DIRECT_INPUT_V1\n'));
      expect(await preparing, 43210);
      expect(writes, 1);
      await output.close();
    },
  );

  test(
    'unexpected bootstrap output is sanitized and receives no credential',
    () async {
      var writes = 0;
      final preparing = exchangeDirectStatusBootstrap(
        Stream.value(utf8.encode('Unexpected output\n')),
        (_) async {
          writes++;
          return true;
        },
        base64Encode(List.filled(32, 17)),
      );
      await expectLater(
        preparing,
        throwsA(failureCode('DIRECT_INPUT_UNAVAILABLE')),
      );
      expect(writes, 0);
    },
  );

  test(
    'lease and status use one loopback connection and report helper death',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final credential = base64Encode(List.filled(32, 17));
      Socket? peer;
      var connections = 0;
      final requests = <String>[];
      final accepted = server.listen((socket) {
        connections++;
        peer = socket;
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final id = line.split('|').first;
              final command = line.substring(line.indexOf('|') + 1);
              requests.add(command);
              final response = command == 'AUTH $credential'
                  ? 'OK'
                  : switch (command) {
                      'STATUS' => 'STATUS:1:2000:1234',
                      'BEGIN 20000' || 'PING' || 'RESTORE' => 'OK',
                      _ => 'ERR',
                    };
              socket.write('$id|$response\n');
            }, onError: (_) {});
      });
      try {
        final session = await ZeppDirectStatusSession.connect(
          server.port,
          credential,
        );
        final first = await session.readStatus();
        expect(first.uid, 2000);
        expect(first.pid, 1234);
        await session.beginLease(20000);
        await session.ping();
        await session.restore();
        expect(connections, 1);
        expect(requests, [
          'AUTH $credential',
          'STATUS',
          'BEGIN 20000',
          'PING',
          'RESTORE',
        ]);
        peer!.destroy();
        await expectLater(
          session.restore(),
          throwsA(failureCode('DIRECT_LEASE_FAILED')),
        );
        await session.close();
        expect(session.connected, isFalse);
        expect(connections, 1);
      } finally {
        peer?.destroy();
        await accepted.cancel();
        await server.close();
      }
    },
  );

  test('authentication failure ends the connection without retry', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    Socket? peer;
    var connections = 0;
    final accepted = server.listen((socket) {
      connections++;
      peer = socket;
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            socket.write('${line.split('|').first}|ERR\n');
          }, onError: (_) {});
    });
    try {
      await expectLater(
        ZeppDirectStatusSession.connect(
          server.port,
          base64Encode(List.filled(32, 17)),
        ),
        throwsA(failureCode('DIRECT_AUTH_FAILED')),
      );
      expect(connections, 1);
    } finally {
      peer?.destroy();
      await accepted.cancel();
      await server.close();
    }
  });
}
