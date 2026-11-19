import 'dart:async';

import 'zepp_diagnostics.dart';

/// Serial request/reply channel used by the embedded ADB helper.
class ZeppAdbRequests {
  ZeppAdbRequests(this.write);

  final Future<bool> Function(String) write;
  Future<void> _queue = Future.value();
  Completer<String>? _reply;
  String? _replyId;
  int _sequence = 0;

  void receive(String line) {
    final reply = _reply;
    if (reply != null && !reply.isCompleted && line.startsWith('$_replyId|')) {
      reply.complete(line.substring(line.indexOf('|') + 1));
    }
  }

  void disconnected() {
    final reply = _reply;
    if (reply != null && !reply.isCompleted) {
      reply.completeError(StateError('Collegamento al recupero interrotto.'));
    }
  }

  Future<String> request(String command) {
    final result = Completer<String>();
    _queue = _queue.catchError((_) {}).then((_) async {
      final reply = Completer<String>();
      _reply = reply;
      reply.future.ignore();
      final id = '${++_sequence}';
      _replyId = id;
      final code = command.split(' ').first;
      zeppDiagnostic('${code}_WRITE', request: _sequence);
      try {
        if (!await write(
          '$id|$command\n',
        ).timeout(const Duration(seconds: 5))) {
          throw StateError('Servizio permessi non disponibile.');
        }
        final response = await reply.future.timeout(
          const Duration(seconds: 25),
        );
        if (response != 'OK' &&
            !(command == 'STATUS' && response.startsWith('STATUS:'))) {
          throw StateError(
            'Sospensione o ripristino dei permessi non confermato.',
          );
        }
        zeppDiagnostic('${code}_OK', request: int.parse(id));
        result.complete(response);
      } catch (error, stack) {
        zeppDiagnostic('${code}_ERROR', request: int.parse(id));
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        _reply = null;
      }
    });
    return result.future;
  }
}
