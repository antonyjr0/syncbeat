import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'zepp_adb_requests.dart';
import 'zepp_adb_stream.dart';
import 'zepp_diagnostics.dart';

/// Read fixed markers only. Never include bootstrap output in exceptions.
Future<int> exchangeDirectStatusBootstrap(
  Stream<List<int>> payload,
  Future<bool> Function(String) write,
  String credential,
) async {
  final lines = StreamIterator(
    payload
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter()),
  );
  try {
    if (!await lines.moveNext().timeout(const Duration(seconds: 5)) ||
        lines.current != 'SYNCBEAT_DIRECT_INPUT_V1') {
      throw const ZeppBootstrapException(
        'DIRECT_INPUT_UNAVAILABLE',
        'Il servizio locale non ha confermato il canale di autenticazione.',
      );
    }
    zeppDiagnostic('DIRECT_INPUT_READY');
    if (!await write('$credential\n').timeout(const Duration(seconds: 5))) {
      throw const ZeppBootstrapException(
        'DIRECT_INPUT_FAILED',
        'Autenticazione del bootstrap locale non riuscita.',
      );
    }
    if (!await lines.moveNext().timeout(const Duration(seconds: 5))) {
      throw const ZeppBootstrapException(
        'DIRECT_BOOTSTRAP_EXITED',
        'Il servizio locale è terminato durante la preparazione.',
      );
    }
    const prefix = 'SYNCBEAT_DIRECT_READY_V1:';
    final line = lines.current;
    final port = line.startsWith(prefix)
        ? int.tryParse(line.substring(prefix.length))
        : null;
    if (port == null || port < 1 || port > 65535) {
      throw const ZeppBootstrapException(
        'DIRECT_READY_INVALID',
        'Segnale di prontezza del servizio locale non valido.',
      );
    }
    zeppDiagnostic('DIRECT_BOOTSTRAP_READY');
    return port;
  } on TimeoutException {
    throw const ZeppBootstrapException(
      'DIRECT_BOOTSTRAP_TIMEOUT',
      'Il bootstrap del servizio locale non risponde entro il limite previsto.',
    );
  } on FormatException {
    throw const ZeppBootstrapException(
      'DIRECT_READY_INVALID',
      'Segnale di prontezza del servizio locale non valido.',
    );
  } finally {
    await lines.cancel();
  }
}

class ZeppDirectStatus {
  const ZeppDirectStatus({required this.uid, required this.pid});
  final int uid;
  final int pid;
}

/// B1 session. The only public operation is a read-only status request.
/// Neither this connection nor a status request invokes the ADB transport.
class ZeppDirectStatusSession {
  ZeppDirectStatusSession._(this._socket) {
    _subscription = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _requests.receive,
          onDone: () => unawaited(close()),
          onError: (_) => unawaited(close()),
        );
  }

  final Socket _socket;
  late final StreamSubscription<String> _subscription;
  bool _closed = false;
  late final _requests = ZeppAdbRequests((line) async {
    if (_closed) return false;
    _socket.add(utf8.encode(line));
    await _socket.flush();
    return !_closed;
  }, replyTimeout: const Duration(seconds: 5));

  bool get connected => !_closed;

  static Future<ZeppDirectStatusSession> connect(
    int port,
    String credential,
  ) async {
    if (port < 1 || port > 65535) {
      throw const ZeppBootstrapException(
        'DIRECT_INVALID_ENDPOINT',
        'Indirizzo del canale locale non valido.',
      );
    }
    final Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {
      throw const ZeppBootstrapException(
        'DIRECT_CONNECT_FAILED',
        'Collegamento al canale locale non riuscito. Prepara nuovamente il canale con Wi-Fi.',
      );
    }
    final session = ZeppDirectStatusSession._(socket);
    try {
      // AUTH's payload stays on the bootstrap/local connection. The request
      // logger records only the fixed AUTH phase code and numeric request ID.
      await session._requests.request('AUTH $credential');
      return session;
    } catch (_) {
      await session.close();
      throw const ZeppBootstrapException(
        'DIRECT_AUTH_FAILED',
        'Autenticazione del canale locale non confermata. Prepara nuovamente il canale con Wi-Fi.',
      );
    }
  }

  Future<ZeppDirectStatus> readStatus() async {
    try {
      if (_closed) throw StateError('Session ended');
      final fields = (await _requests.request('STATUS')).split(':');
      final uid = fields.length == 4 ? int.tryParse(fields[2]) : null;
      final pid = fields.length == 4 ? int.tryParse(fields[3]) : null;
      if (fields.length != 4 ||
          fields[0] != 'STATUS' ||
          fields[1] != '1' ||
          (uid != 2000 && uid != 0) ||
          pid == null ||
          pid < 1) {
        throw const FormatException('Invalid status');
      }
      zeppDiagnostic('DIRECT_STATUS_OK', pid: pid);
      return ZeppDirectStatus(uid: uid!, pid: pid);
    } catch (_) {
      await close();
      throw const ZeppBootstrapException(
        'DIRECT_UNAVAILABLE',
        'Canale locale non disponibile. Riattiva il Wi-Fi e prepara nuovamente il canale.',
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _requests.disconnected();
    _socket.destroy();
    await _subscription.cancel();
  }
}
