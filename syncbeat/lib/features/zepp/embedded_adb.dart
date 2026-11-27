import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'zepp_adb_requests.dart';
import 'zepp_adb_stream.dart';
import 'zepp_diagnostics.dart';
import 'zepp_direct_status.dart';
import 'adb_connect_discovery.dart';
import 'adb_connection_attempt.dart';

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
  ZeppDirectStatusSession? _leaseSession;
  Future<ZeppDirectStatusSession>? _directPreparation;
  StreamSubscription<String>? _subscription;
  late final _requests = ZeppAdbRequests((line) async {
    final stream = _helper;
    return stream != null && await stream.writeString(line);
  });
  Timer? _heartbeat;
  bool _active = false;
  int? _port;
  Future<void>? _automaticConnection;
  Future<void>? _startup;
  Future<void>? _openingPreparation;
  Future<void>? _grantOperation;
  AppLifecycleListener? _appLifecycle;
  bool _wasInBackground = false;
  final startupStatus = ValueNotifier<String?>(null);
  final startupFailed = ValueNotifier<bool>(false);

  bool get ready =>
      _connection?.connected == true && _connection?.tlsEnabled == true;
  int? get connectionPort => _port;

  Future<bool> automaticActivationAuthorized() async {
    final state = await channel.invokeMapMethod<String, Object?>(
      'wirelessDebugAuthorization',
    );
    if (state?['primaryUser'] != true) {
      throw const ZeppBootstrapException(
        'ADB_GRANT_PROFILE',
        'Il collegamento automatico richiede il profilo principale di Android.',
      );
    }
    return state?['authorized'] == true;
  }

  /// Invoked only by the explicit setup button, never by startup/background code.
  Future<void> authorizeAutomaticActivation({
    required bool userApproved,
  }) async {
    if (!userApproved) {
      throw const ZeppBootstrapException(
        'ADB_GRANT_CONSENT_REQUIRED',
        'Premi Abilita collegamento automatico per autorizzare questa funzione.',
      );
    }
    final pending = _grantOperation;
    if (pending != null) return pending;
    final operation = _grantAutomaticActivation();
    _grantOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_grantOperation, operation)) _grantOperation = null;
    }
  }

  Future<void> _grantAutomaticActivation() async {
    if (_active) {
      throw const ZeppBootstrapException(
        'ADB_GRANT_BUSY',
        'Attendi la fine del trasferimento e del ripristino di Zepp.',
      );
    }
    if (await automaticActivationAuthorized()) return;
    await connectAutomatically();
    zeppDiagnostic('ADB_GRANT_REQUEST');
    // Fixed package, user and permission. No caller-supplied shell arguments.
    final stream = await ZeppAdbStream.open(
      _connection!,
      ++_nextStreamId,
      'shell:pm grant --user 0 com.example.syncbeat android.permission.WRITE_SECURE_SETTINGS && echo SYNCBEAT_DEBUG_AUTH_GRANTED_V1',
    );
    try {
      await stream.onPayload
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line == 'SYNCBEAT_DEBUG_AUTH_GRANTED_V1')
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      zeppDiagnostic('ADB_GRANT_ERROR');
      throw const ZeppBootstrapException(
        'ADB_GRANT_FAILED',
        'Autorizzazione non confermata. Controlla il Debug wireless; nessun nuovo tentativo automatico.',
      );
    } finally {
      await stream.close();
    }
    if (!await automaticActivationAuthorized()) {
      zeppDiagnostic('ADB_GRANT_ERROR');
      throw const ZeppBootstrapException(
        'ADB_GRANT_NOT_CONFIRMED',
        'Android non ha concesso l’autorizzazione. Il Debug wireless resta gestibile dalle impostazioni.',
      );
    }
    zeppDiagnostic('ADB_GRANT_VERIFIED');
  }

  void register() {
    channel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'ready':
            return ready || _directStatus?.connected == true;
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
            final local = _directStatus;
            if (local != null && local.connected) {
              await local.ping();
              return null;
            }
            await _ensureHelper();
            await _request('PING');
            zeppDiagnostic('HELPER_PREPARED');
            return null;
          case 'begin':
            final local = _directStatus;
            _leaseSession = local != null && local.connected ? local : null;
            final timeout = call.arguments as int;
            if (_leaseSession != null) {
              await _leaseSession!.beginLease(timeout);
            } else {
              await _ensureHelper();
              await _request('BEGIN $timeout');
            }
            _active = true;
            _heartbeat?.cancel();
            _heartbeat = Timer.periodic(const Duration(seconds: 5), (
              timer,
            ) async {
              if (!_active || !identical(_heartbeat, timer)) return;
              try {
                final local = _leaseSession;
                if (local != null) {
                  await local.ping();
                } else {
                  await _request('PING');
                }
              } catch (_) {
                if (!_active || !identical(_heartbeat, timer)) return;
                _active = false;
                timer.cancel();
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
            final allowBootstrap = call.arguments == true;
            final local =
                _leaseSession ?? (allowBootstrap ? _directStatus : null);
            if (local != null && (local.connected || !allowBootstrap)) {
              await local.restore();
              _leaseSession = null;
              return null;
            }
            await _ensureHelper(allowBootstrap: allowBootstrap);
            await _request('RESTORE');
            _leaseSession = null;
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
      await attemptAdbConnection(
        connect: connection.connect,
        tlsEnabled: () => connection.tlsEnabled,
      );
      _port = port;
      await _storage.write(key: 'embedded_adb_port_v1', value: '$port');
    } catch (_) {
      await connection.disconnect();
      rethrow;
    }
  }

  Future<bool> reconnect() async {
    if (ready) return true;
    try {
      await connectAutomatically();
      return ready;
    } catch (_) {
      return false;
    }
  }

  /// One discovery and one TLS connection. No saved-port retry on failure.
  Future<void> connectAutomatically() async {
    if (ready) return;
    final pending = _automaticConnection;
    if (pending != null) return pending;
    final operation = _discoverAndConnect();
    _automaticConnection = operation;
    try {
      await operation;
    } finally {
      if (identical(_automaticConnection, operation)) {
        _automaticConnection = null;
      }
    }
  }

  Future<void> _discoverAndConnect() async {
    try {
      final activation = await channel
          .invokeMethod<String>('ensureWirelessDebug')
          .timeout(const Duration(seconds: 5));
      switch (activation) {
        case 'no_wifi':
          throw const ZeppBootstrapException(
            'ADB_WIFI_REQUIRED',
            'Collega il telefono a una rete Wi-Fi per preparare il servizio.',
          );
        case 'authorization_required':
          zeppDiagnostic('ADB_WIFI_MANUAL_ACTIVATION');
        case 'already_enabled':
          zeppDiagnostic('ADB_WIFI_ALREADY_ENABLED');
        case 'enable_requested':
          zeppDiagnostic('ADB_WIFI_ENABLE_REQUESTED');
        default:
          throw const ZeppBootstrapException(
            'ADB_WIFI_STATE_INVALID',
            'Stato Debug wireless non disponibile.',
          );
      }
      zeppDiagnostic('ADB_DISCOVERY_START');
      final snapshot = await channel
          .invokeMapMethod<Object?, Object?>('discoverConnect')
          .timeout(const Duration(seconds: 12));
      final port = selectSelfAdbConnectPort(snapshot ?? {});
      zeppDiagnostic('ADB_DISCOVERY_SELECTED');
      await connect(port);
      zeppDiagnostic('ADB_AUTO_CONNECTED');
    } catch (error) {
      zeppDiagnostic('ADB_AUTO_CONNECT_ERROR');
      final code = error is ZeppBootstrapException
          ? error.code
          : error is PlatformException
          ? error.code
          : null;
      if (code != null &&
          RegExp(
            r'^ADB_(DISCOVERY|WIFI|CONNECT|HANDSHAKE|TLS)_[A-Z_]+$',
          ).hasMatch(code)) {
        zeppDiagnostic(code);
      }
      rethrow;
    }
  }

  /// Called once when this app process opens. Observations and foreground
  /// resumes never create a retry loop. No BEGIN, restore or music command.
  Future<void> prepareOnOpen() => _startup ??= prepareOnForeground();

  void startAutomaticPreparation() {
    if (_appLifecycle != null) return;
    _appLifecycle = AppLifecycleListener(
      onPause: () => _wasInBackground = true,
      onResume: () {
        if (_wasInBackground) {
          _wasInBackground = false;
          unawaited(prepareOnForeground());
        }
      },
    );
    unawaited(prepareOnOpen());
  }

  /// A genuine app reopening is a new user action, not a timer retry.
  Future<void> prepareOnForeground() async {
    if (_directStatus?.connected == true) return;
    final pending = _openingPreparation;
    if (pending != null) return pending;
    final operation = _prepareOnOpen();
    _openingPreparation = operation;
    try {
      await operation;
    } finally {
      if (identical(_openingPreparation, operation)) _openingPreparation = null;
    }
  }

  Future<void> _prepareOnOpen() async {
    try {
      await prepareForUse();
    } catch (_) {
      /* Visible status, no automatic retry. */
    }
  }

  /// Explicit setup completion may prepare the already-connected channel.
  Future<void> prepareForUse({bool alreadyConnected = false}) async {
    startupStatus.value = 'Preparazione del collegamento all’orologio…';
    startupFailed.value = false;
    try {
      if (!alreadyConnected) await connectAutomatically();
      await prepareOfflineStatus(allowReconnect: false);
      startupStatus.value =
          'Collegamento preparato. Per inviare un brano premi Invia all’orologio.';
      zeppDiagnostic('APP_PREPARATION_READY');
    } catch (error) {
      startupFailed.value = true;
      startupStatus.value = error is ZeppBootstrapException
          ? error.message
          : 'Preparazione non riuscita. Controlla Wi-Fi e Debug wireless. '
                'La prima volta autorizza SyncBeat dalla configurazione.';
      zeppDiagnostic('APP_PREPARATION_ERROR');
      rethrow;
    }
  }

  Future<ZeppDirectStatus> prepareOfflineStatus({
    bool allowReconnect = true,
  }) async {
    if (_active) {
      throw const ZeppBootstrapException(
        'DIRECT_BUSY',
        'Attendi il ripristino di Zepp prima di preparare il canale locale.',
      );
    }
    final existing = _directStatus;
    if (existing != null && existing.connected) return existing.readStatus();
    final preparation = _directPreparation ??= _startDirectStatus(
      allowReconnect: allowReconnect,
    );
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

  Future<ZeppDirectStatusSession> _startDirectStatus({
    bool allowReconnect = true,
  }) async {
    if (!ready && (!allowReconnect || !await reconnect())) {
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
    if (_active && _leaseSession == null) {
      _active = false;
      _heartbeat?.cancel();
      channel.invokeMethod<void>('leaseLost').ignore();
    }
    _requests.disconnected();
  }

  Future<String> _request(String command) => _requests.request(command);
}
