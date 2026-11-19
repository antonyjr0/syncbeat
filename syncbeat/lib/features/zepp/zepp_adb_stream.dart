import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_adb/adb_protocol.dart';
import 'package:flutter_adb/flutter_adb.dart';

class ZeppBootstrapException implements Exception {
  const ZeppBootstrapException(this.code, this.message);
  final String code;
  final String message;
}

/// Installs listeners before OPEN and buffers data until the caller subscribes.
/// IDs must be unique for the lifetime of the supplied connection.
class ZeppAdbStream {
  ZeppAdbStream._(this.connection, this.stream) {
    _opened.future.ignore();
    _payloadSubscription = stream.onPayload.listen(
      (data) {
        if (!_payload.isClosed && !_closed) _payload.add(data);
      },
      onError: (Object error) => _fail(
        const ZeppBootstrapException(
          'ADB_TRANSPORT_LOST',
          'Il canale ADB si è interrotto.',
        ),
      ),
      onDone: () {
        if (!_opened.isCompleted) {
          _opened.completeError(
            connection.connected
                ? const ZeppBootstrapException(
                    'ADB_OPEN_REFUSED',
                    'Collegamento al servizio ADB rifiutato.',
                  )
                : const ZeppBootstrapException(
                    'ADB_TRANSPORT_LOST',
                    'Il canale ADB si è interrotto.',
                  ),
          );
        }
        _finishPayload();
        unawaited(close());
      },
    );
    _readySubscription = stream.onWriteReady.listen((ready) {
      if (ready && !_opened.isCompleted) _opened.complete();
    });
    _connectionSubscription = connection.onConnectionChanged.listen((ready) {
      if (!ready) {
        _fail(
          const ZeppBootstrapException(
            'ADB_TRANSPORT_LOST',
            'Il canale ADB si è interrotto.',
          ),
        );
      }
    });
  }

  final AdbConnection connection;
  final AdbStream stream;
  final _opened = Completer<void>();
  final _payload = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _payloadSubscription;
  late final StreamSubscription<bool> _readySubscription;
  late final StreamSubscription<bool> _connectionSubscription;
  bool _closed = false;
  Future<void>? _closing;

  Stream<Uint8List> get onPayload => _payload.stream;
  bool get isClosed => _closed || stream.isClosed || !connection.connected;
  Future<bool> writeString(String text) => stream.writeString(text);

  static Future<ZeppAdbStream> open(
    AdbConnection connection,
    int id,
    String destination,
  ) async {
    final native = AdbStream(id, connection);
    final managed = ZeppAdbStream._(connection, native);
    connection.openStreams[id] = native;
    try {
      if (!connection.connected) {
        throw const ZeppBootstrapException(
          'ADB_TRANSPORT_LOST',
          'Il canale ADB si è interrotto.',
        );
      }
      // Waiting on OPEN starts immediately, even if writing to TLS stalls.
      unawaited(
        connection
            .sendMessage(AdbProtocol.generateOpen(id, destination))
            .catchError(
              (Object error) => managed._fail(
                const ZeppBootstrapException(
                  'ADB_TRANSPORT_LOST',
                  'Il canale ADB si è interrotto.',
                ),
              ),
            ),
      );
      await managed._opened.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const ZeppBootstrapException(
          'ADB_OPEN_TIMEOUT',
          'Il collegamento al servizio ADB non risponde entro 10 secondi.',
        ),
      );
      return managed;
    } catch (_) {
      await managed.close();
      rethrow;
    }
  }

  void _fail(ZeppBootstrapException error) {
    if (!_opened.isCompleted) {
      _opened.completeError(error);
    } else if (!_payload.isClosed && !_closed) {
      _payload.addError(error);
    }
    _finishPayload();
    unawaited(close());
  }

  void _finishPayload() {
    if (!_payload.isClosed) unawaited(_payload.close());
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // Retire the ID before a late OKAY/WRTE can reach the failed attempt.
    if (identical(connection.openStreams[stream.localId], stream)) {
      connection.openStreams.remove(stream.localId);
    }
    await _readySubscription.cancel();
    await _connectionSubscription.cancel();
    await _payloadSubscription.cancel();
    _finishPayload();
    stream.close();
    if (connection.connected) {
      // Cleanup never blocks completion of a failed OPEN.
      unawaited(
        connection
            .sendMessage(
              AdbProtocol.generateClose(stream.localId, stream.remoteId ?? 0),
            )
            .catchError((Object _) {}),
      );
    }
  }
}

Future<void> waitForZeppReady(Stream<List<int>> payload) async {
  try {
    final line = await payload
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 5));
    if (line == 'SYNCBEAT_RECOVERY_PENDING_V1') {
      throw const ZeppBootstrapException(
        'ADB_RECOVERY_PENDING',
        'Il servizio ADB ha un ripristino Zepp ancora pendente.',
      );
    }
    if (line != 'SYNCBEAT_READY_V1') {
      throw const ZeppBootstrapException(
        'ADB_READY_INVALID',
        'Segnale di prontezza del servizio ADB non valido.',
      );
    }
  } on TimeoutException {
    throw const ZeppBootstrapException(
      'ADB_READY_TIMEOUT',
      'Il servizio ADB non ha segnalato READY entro 5 secondi.',
    );
  } on StateError {
    throw const ZeppBootstrapException(
      'ADB_BOOTSTRAP_EXITED',
      'Il lancio ADB è terminato prima del segnale READY.',
    );
  } on FormatException {
    throw const ZeppBootstrapException(
      'ADB_READY_INVALID',
      'Segnale di prontezza del servizio ADB non valido.',
    );
  }
}
