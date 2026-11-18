import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Map<String, String> _generateAdbIdentity() =>
    AdbCrypto(adbKeyName: 'SyncBeat@self').exportKeyPairForStorage();

/// Self-device only. Credentials never leave secure storage or appear in logs.
class EmbeddedAdb {
  EmbeddedAdb._();
  static final instance = EmbeddedAdb._();
  static const channel = MethodChannel('syncbeat/embedded_adb');
  static const _storage = FlutterSecureStorage();
  AdbCrypto? _identity;
  Future<AdbCrypto>? _identityLoading;
  AdbConnection? _connection;
  AdbStream? _helper;
  StreamSubscription<String>? _subscription;
  Completer<String>? _reply;
  int _sequence = 0;
  String? _replyId;
  Future<void> _queue = Future.value();
  Timer? _heartbeat;
  bool _active = false;
  int? _port;

  bool get ready =>
      _connection?.connected == true && _connection?.tlsEnabled == true;
  int? get connectionPort => _port;

  void register() {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ready':
          return ready;
        case 'begin':
          await _ensureHelper();
          await _request('BEGIN ${call.arguments as int}');
          _active = true;
          _heartbeat?.cancel();
          _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) async {
            if (!_active) return;
            try {
              await _request('PING');
            } catch (_) {
              _active = false;
              _heartbeat?.cancel();
              try {
                await channel.invokeMethod<void>('leaseLost');
              } catch (_) {
                /* Native worker may already be gone. */
              }
            }
          });
          return null;
        case 'restore':
          _active = false;
          _heartbeat?.cancel();
          await _ensureHelper();
          await _request('RESTORE');
          return null;
        default:
          throw MissingPluginException();
      }
    });
  }

  Future<AdbCrypto> _crypto() => _identityLoading ??= _loadCrypto();

  Future<AdbCrypto> _loadCrypto() async {
    if (_identity != null) return _identity!;
    final stored = await _storage.read(key: 'embedded_adb_identity_v1');
    final map = stored == null
        ? await Isolate.run(_generateAdbIdentity)
        : Map<String, String>.from(jsonDecode(stored) as Map);
    _identity = AdbCrypto(
      keyPair: AdbCrypto.keyPairFromStorageMap(map),
      adbKeyName: 'SyncBeat@self',
    );
    if (stored == null) {
      await _storage.write(
        key: 'embedded_adb_identity_v1',
        value: jsonEncode(map),
      );
    }
    return _identity!;
  }

  static int validatePort(String value) {
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) {
      throw const FormatException('Porta non valida.');
    }
    return port;
  }

  Future<void> pair(int port, String code) async {
    if (port < 1 || port > 65535 || !RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const FormatException(
        'Servono la porta di abbinamento e il codice di sei cifre.',
      );
    }
    final identity = await _crypto();
    final paired = await AdbPairing.pair(
      '127.0.0.1',
      port,
      code,
      identity,
      verbose: false,
    ).timeout(const Duration(seconds: 35));
    if (!paired) {
      throw StateError(
        'Abbinamento rifiutato. Apri un nuovo codice in Debug wireless e riprova.',
      );
    }
  }

  Future<void> connect(int port) async {
    if (_active) {
      throw StateError(
        'Attendi il ripristino di Zepp prima di riconnettere ADB.',
      );
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Porta non valida.');
    }
    await _subscription?.cancel();
    _subscription = null;
    _helper = null;
    await _connection?.disconnect();
    final connection = AdbConnection(
      '127.0.0.1',
      port,
      await _crypto(),
      verbose: false,
    );
    _connection = connection;
    try {
      if (!await connection.connect().timeout(const Duration(seconds: 12)) ||
          !connection.tlsEnabled) {
        throw StateError(
          'Connessione al debug wireless non riuscita. Controlla la porta di connessione.',
        );
      }
      _port = port;
      await _storage.write(key: 'embedded_adb_port_v1', value: '$port');
    } catch (_) {
      await connection.disconnect();
      rethrow;
    }
  }

  Future<bool> reconnect() async {
    if (ready) return true;
    final saved = await _storage.read(key: 'embedded_adb_port_v1');
    if (saved == null) return false;
    try {
      await connect(validatePort(saved));
      return ready;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureHelper() async {
    if (!ready && !await reconnect()) {
      throw StateError('Ricollega il debug wireless in SyncBeat.');
    }
    if (_helper != null && !_helper!.isClosed) return;
    final info = await channel.invokeMapMethod<String, dynamic>('bootstrap');
    final apk = info?['apkPath'] as String? ?? '';
    if (info?['user'] != 0 ||
        !RegExp(r'^/data/app/[A-Za-z0-9_./~+=-]+/base\.apk$').hasMatch(apk)) {
      throw StateError(
        'Il coordinamento ADB richiede il profilo principale di Android.',
      );
    }
    var nonce = await _storage.read(key: 'embedded_adb_endpoint_v1');
    if (nonce == null) {
      final random = Random.secure();
      nonce = List.generate(
        32,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      await _storage.write(key: 'embedded_adb_endpoint_v1', value: nonce);
    }
    final name =
        'syncbeat_zepp_${sha256.convert(utf8.encode('$nonce:$apk')).toString().substring(0, 32)}';
    Future<AdbStream> open() => _connection!.open('localabstract:$name');
    AdbStream stream;
    try {
      stream = await open();
    } catch (_) {
      final launch = await _connection!.open(
        'shell:CLASSPATH=$apk nohup /system/bin/app_process /system/bin com.example.syncbeat.ZeppAdbLeaseServer $name </dev/null >/dev/null 2>&1 &',
      );
      await launch.onPayload.drain<void>().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      stream = await open();
    }
    _helper = stream;
    await _subscription?.cancel();
    _subscription = stream.onPayload
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final reply = _reply;
            if (reply != null &&
                !reply.isCompleted &&
                line.startsWith('$_replyId|')) {
              reply.complete(line.substring(line.indexOf('|') + 1));
            }
          },
          onDone: _lostHelper,
          onError: (_) => _lostHelper(),
        );
  }

  void _lostHelper() {
    _helper = null;
    if (_active) {
      _active = false;
      _heartbeat?.cancel();
      channel.invokeMethod<void>('leaseLost').ignore();
    }
    final reply = _reply;
    if (reply != null && !reply.isCompleted) {
      reply.completeError(StateError('Collegamento al recupero interrotto.'));
    }
  }

  Future<void> _request(String command) {
    final result = Completer<void>();
    _queue = _queue.catchError((_) {}).then((_) async {
      final reply = Completer<String>();
      _reply = reply;
      reply.future.ignore();
      final id = '${++_sequence}';
      _replyId = id;
      try {
        final stream = _helper;
        if (stream == null ||
            !await stream
                .writeString('$id|$command\n')
                .timeout(const Duration(seconds: 5))) {
          throw StateError('Servizio permessi non disponibile.');
        }
        if (await reply.future.timeout(const Duration(seconds: 25)) != 'OK') {
          throw StateError(
            'Sospensione o ripristino dei permessi non confermato.',
          );
        }
        result.complete();
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        _reply = null;
      }
    });
    return result.future;
  }
}
