import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'zepp_adb_requests.dart';
import 'zepp_adb_stream.dart';
import 'zepp_diagnostics.dart';
import 'zepp_direct_status.dart';

Map<String, String> _generateAdbIdentity() =>
    AdbCrypto(adbKeyName: 'SyncBeat@self').exportKeyPairForStorage();

/// Self-device only. Credentials never leave secure storage or appear in logs.
class EmbeddedAdb {
  EmbeddedAdb._();

  @visibleForTesting
  EmbeddedAdb.forTesting(AdbConnection connection) : _connection = connection;
  static final instance = EmbeddedAdb._();
  static const channel = MethodChannel('syncbeat/embedded_adb');
  static const _storage = FlutterSecureStorage();
  AdbCrypto? _identity;
  Future<AdbCrypto>? _identityLoading;
  AdbConnection? _connection;
  ZeppAdbStream? _helper;
  Future<void>? _preparation;
  int _nextStreamId = 0;
  int _connectionGeneration = 0;
  int _bootstrapAttempt = 0;
  ZeppDirectStatusSession? _directStatus;
  Future<ZeppDirectStatusSession>? _directPreparation;
  StreamSubscription<String>? _subscription;
  late final _requests = ZeppAdbRequests((line) async {
    final stream = _helper;
    return stream != null && await stream.writeString(line);
  });
  Timer? _heartbeat;
  bool _active = false;
  int? _port;

  bool get ready =>
      _connection?.connected == true && _connection?.tlsEnabled == true;
  int? get connectionPort => _port;

  void register() {
    channel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'ready':
            return ready;
          case 'diagnostics':
            // Never reconnect or bootstrap during observation.
            if (!ready || _helper == null || _helper!.isClosed) {
              return <String, Object>{'leaseState': 'unavailable'};
            }
            try {
              final reply = await _request('STATUS');
              final fields = reply.split(':');
              if (fields.length != 4 || fields[0] != 'STATUS') {
                throw StateError('Stato diagnostico non valido.');
              }
              return <String, Object>{
                'leaseState': fields[1] == '1' ? 'active' : 'idle',
                'journalPending': fields[2] == '1',
                'generation': int.parse(fields[3]),
              };
            } catch (_) {
              return <String, Object>{'leaseState': 'unknown'};
            }
          case 'prepare':
            await _ensureHelper();
            await _request('PING');
            zeppDiagnostic('HELPER_PREPARED');
            return null;
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
            await _ensureHelper(allowBootstrap: call.arguments == true);
            await _request('RESTORE');
            return null;
          default:
            throw MissingPluginException();
        }
      } on ZeppBootstrapException catch (error) {
        zeppDiagnostic(error.code);
        throw PlatformException(code: error.code, message: error.message);
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

  Future<void> pairFromNotification() async {
    // Prepare the keys before opening Settings, while the code is still fresh.
    await _crypto();
    final reply = await channel.invokeMapMethod<String, Object?>(
      'pairFromNotification',
    );
    await pair(reply!['port'] as int, reply['code'] as String);
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
    ++_connectionGeneration;
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
    _nextStreamId = 0;
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

  Future<ZeppDirectStatus> prepareOfflineStatus() async {
    if (_active) {
      throw const ZeppBootstrapException(
        'DIRECT_BUSY',
        'Attendi il ripristino di Zepp prima di preparare il canale locale.',
      );
    }
    final existing = _directStatus;
    if (existing != null && existing.connected) return existing.readStatus();
    final preparation = _directPreparation ??= _startDirectStatus();
    try {
      final session = await preparation;
      _directStatus = session;
      return await session.readStatus();
    } finally {
      if (identical(_directPreparation, preparation)) _directPreparation = null;
    }
  }

  Future<ZeppDirectStatus> offlineStatus() async {
    final session = _directStatus;
    if (session == null) {
      throw const ZeppBootstrapException(
        'DIRECT_UNAVAILABLE',
        'Prepara prima il canale locale con Wi-Fi e Debug wireless autorizzato.',
      );
    }
    return session.readStatus();
  }

  Future<ZeppDirectStatusSession> _startDirectStatus() async {
    if (!ready && !await reconnect()) {
      throw const ZeppBootstrapException(
        'DIRECT_ADB_UNAVAILABLE',
        'Per preparare il canale locale serve il Debug wireless collegato. Configuralo in SyncBeat.',
      );
    }
    final connection = _connection!;
    final generation = _connectionGeneration;
    final apk = await _bootstrapApk();
    // Independent from the public endpoint nonce of the permission helper.
    // RAM only. It is sent once on stdin after the non-echo input marker.
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final credential = base64Encode(bytes);
    bytes.fillRange(0, bytes.length, 0);
    zeppDiagnostic('DIRECT_BOOTSTRAP_START');
    final launch = await ZeppAdbStream.open(
      connection,
      ++_nextStreamId,
      'shell:stty -echo && trap "" HUP && CLASSPATH=$apk exec /system/bin/app_process /system/bin com.example.syncbeat.ZeppAdbLeaseServer --direct-status-v1 2>/dev/null',
    );
    final int port;
    try {
      port = await exchangeDirectStatusBootstrap(
        launch.onPayload,
        launch.writeString,
        credential,
      );
    } finally {
      await launch.close();
      zeppDiagnostic('DIRECT_BOOTSTRAP_CLOSED');
    }
    if (generation != _connectionGeneration) {
      throw const ZeppBootstrapException(
        'DIRECT_BOOTSTRAP_CANCELLED',
        'La connessione ADB è cambiata durante la preparazione del canale locale.',
      );
    }
    // From here the new session has no ADB dependency, including Wi-Fi loss.
    return ZeppDirectStatusSession.connect(port, credential);
  }

  Future<String> _bootstrapApk() async {
    final info = await channel.invokeMapMethod<String, dynamic>('bootstrap');
    final apk = info?['apkPath'] as String? ?? '';
    if (info?['user'] != 0 ||
        !RegExp(r'^/data/app/[A-Za-z0-9_./~+=-]+/base\.apk$').hasMatch(apk)) {
      throw StateError(
        'Il coordinamento ADB richiede il profilo principale di Android.',
      );
    }
    return apk;
  }

  Future<void> _ensureHelper({bool allowBootstrap = true}) async {
    if (_helper != null && !_helper!.isClosed) return;
    if (!allowBootstrap) {
      throw const ZeppBootstrapException(
        'ADB_RECOVERY_UNAVAILABLE',
        'Il canale del servizio non è disponibile per il ripristino. Usa Ripristina permessi Zepp.',
      );
    }
    final pending = _preparation;
    if (pending != null) return pending;
    final preparation = _startHelper();
    _preparation = preparation;
    try {
      await preparation;
    } finally {
      if (identical(_preparation, preparation)) _preparation = null;
    }
  }

  Future<void> _startHelper() async {
    final attempt = ++_bootstrapAttempt;
    zeppDiagnostic('HELPER_ENSURE', request: attempt);
    if (!ready && !await reconnect()) {
      throw const ZeppBootstrapException(
        'ADB_TRANSPORT_LOST',
        'Ricollega il debug wireless in SyncBeat.',
      );
    }
    final connection = _connection!;
    final generation = _connectionGeneration;
    final apk = await _bootstrapApk();
    final random = Random.secure();
    final nonce = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final name = 'syncbeat_zepp_$nonce';
    void checkCurrent() {
      if (generation != _connectionGeneration || !connection.connected) {
        throw const ZeppBootstrapException(
          'ADB_TRANSPORT_LOST',
          'Il canale ADB si è interrotto durante la preparazione.',
        );
      }
    }

    checkCurrent();
    zeppDiagnostic('HELPER_LAUNCH', request: attempt);
    // The legacy ADB shell has a PTY. Ignore HUP in the child directly so
    // nohup cannot redirect READY away from that channel. Keep the parent
    // waiting until the client receives READY and closes the startup stream.
    final launch = await ZeppAdbStream.open(
      connection,
      ++_nextStreamId,
      'shell:(trap "" HUP; CLASSPATH=$apk exec /system/bin/app_process /system/bin com.example.syncbeat.ZeppAdbLeaseServer $name </dev/null 2>/dev/null) & wait',
    );
    try {
      await waitForZeppReady(launch.onPayload);
      checkCurrent();
      zeppDiagnostic('HELPER_READY', request: attempt);
    } finally {
      await launch.close();
      zeppDiagnostic('HELPER_LAUNCH_CLOSED', request: attempt);
    }
    checkCurrent();
    zeppDiagnostic('HELPER_SOCKET_OPEN', request: attempt);
    final stream = await ZeppAdbStream.open(
      connection,
      ++_nextStreamId,
      'localabstract:$name',
    );
    try {
      checkCurrent();
      await _subscription?.cancel();
      _helper = stream;
      _subscription = stream.onPayload
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _requests.receive,
            onDone: () {
              if (identical(_helper, stream)) _lostHelper();
            },
            onError: (_) {
              if (identical(_helper, stream)) _lostHelper();
            },
          );
      zeppDiagnostic('HELPER_SOCKET_OK', request: attempt);
    } catch (_) {
      await stream.close();
      rethrow;
    }
  }

  void _lostHelper() {
    zeppDiagnostic('HELPER_LOST');
    _helper = null;
    if (_active) {
      _active = false;
      _heartbeat?.cancel();
      channel.invokeMethod<void>('leaseLost').ignore();
    }
    _requests.disconnected();
  }

  Future<String> _request(String command) => _requests.request(command);
}
