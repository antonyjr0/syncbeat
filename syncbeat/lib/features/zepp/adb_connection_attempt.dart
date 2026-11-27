import 'dart:async';
import 'dart:io';

import 'zepp_adb_stream.dart';

/// Exactly one transport attempt. flutter_adb 1.0.0 catches TCP exceptions and
/// prints them even with verbose=false; intercept only that known diagnostic,
/// replacing endpoint/error details with a fixed outcome. No socket probe,
/// second connection, identity reset or fallback is performed here.
Future<void> attemptAdbConnection({
  required Future<bool> Function() connect,
  required bool Function() tlsEnabled,
  Duration timeout = const Duration(seconds: 12),
}) async {
  String? failure;
  try {
    final accepted = await runZoned(
      () => connect().timeout(timeout),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          if (line.startsWith('Failed to connect to ADB: ')) {
            failure = _printedFailure(line);
          } else {
            parent.print(zone, line);
          }
        },
      ),
    );
    if (!accepted) {
      throw adbConnectionFailure(failure ?? 'ADB_HANDSHAKE_REJECTED');
    }
    if (!tlsEnabled()) throw adbConnectionFailure('ADB_TLS_REQUIRED');
  } on ZeppBootstrapException {
    rethrow;
  } on TimeoutException {
    throw adbConnectionFailure('ADB_CONNECT_TIMEOUT');
  } on SocketException catch (error) {
    final code = error.osError?.errorCode;
    throw adbConnectionFailure(
      [61, 111, 10061].contains(code)
          ? 'ADB_CONNECT_REFUSED'
          : 'ADB_CONNECT_NETWORK_ERROR',
    );
  } on HandshakeException {
    throw adbConnectionFailure('ADB_HANDSHAKE_REJECTED');
  } catch (_) {
    throw adbConnectionFailure('ADB_CONNECT_FAILED');
  }
}

String _printedFailure(String line) {
  // Dependency-specific strings, never emitted to the application's log/UI.
  if (line.contains('Connection refused') ||
      RegExp(r'errno = (61|111|10061)\b').hasMatch(line)) {
    return 'ADB_CONNECT_REFUSED';
  }
  if (line.contains('timed out') || line.contains('TimeoutException')) {
    return 'ADB_CONNECT_TIMEOUT';
  }
  if (line.contains('SocketException')) return 'ADB_CONNECT_NETWORK_ERROR';
  if (line.contains('HandshakeException')) return 'ADB_HANDSHAKE_REJECTED';
  return 'ADB_CONNECT_FAILED';
}

ZeppBootstrapException adbConnectionFailure(
  String code,
) => ZeppBootstrapException(code, switch (code) {
  'ADB_CONNECT_REFUSED' =>
    'Debug wireless individuato, ma la connessione è rifiutata. '
        'Il servizio non accetta collegamenti su quella porta.',
  'ADB_CONNECT_TIMEOUT' =>
    'Tempo di collegamento al Debug wireless scaduto. '
        'Nessun secondo tentativo automatico.',
  'ADB_CONNECT_NETWORK_ERROR' =>
    'Collegamento locale al Debug wireless non disponibile.',
  'ADB_HANDSHAKE_REJECTED' =>
    'Autenticazione ADB/TLS non confermata. '
        'Apri Configura collegamento e usa Abbina dalla notifica per ripristinare l’abbinamento di SyncBeat.',
  'ADB_TLS_REQUIRED' =>
    'Il collegamento trovato non usa il Debug wireless TLS richiesto.',
  _ =>
    'Collegamento al Debug wireless non riuscito. Controlla la configurazione.',
});
