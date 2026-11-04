import 'dart:async';
import 'package:flutter/services.dart';
import 'audio_source.dart';

/// The same argument list and progress protocol as the Windows process adapter.
class AndroidYoutubeBridge {
  AndroidYoutubeBridge({
    this.methods = const MethodChannel('syncbeat/youtube'),
    this.events = const EventChannel('syncbeat/youtube/events'),
  });
  final MethodChannel methods;
  final EventChannel events;
  static int _sequence = 0;

  Future<void> run(
    List<String> arguments, {
    required DownloadCancellationToken cancellation,
    required void Function(String) onLine,
    required Duration timeout,
  }) async {
    cancellation.throwIfCancelled();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    var completed = false;
    Object? callbackError;
    final subscription = events.receiveBroadcastStream().listen(
      (event) {
        final data = Map<Object?, Object?>.from(event as Map);
        if (data['id'] == id && data['line'] is String) {
          try {
            onLine(data['line'] as String);
          } catch (error) {
            callbackError = error;
          }
        }
      },
      onError: (Object error) {
        callbackError = error;
      },
    );
    Future<void> cancel() async {
      if (completed) return;
      try {
        await methods.invokeMethod<void>('cancel', {'id': id});
      } on Exception {
        /* completion reports the error */
      }
    }

    unawaited(cancellation.whenCancelled.then((_) => cancel()));
    try {
      final response = await methods
          .invokeMapMethod<String, dynamic>('run', {
            'id': id,
            'arguments': arguments,
            'timeoutMs': timeout.inMilliseconds,
          })
          .timeout(
            timeout + const Duration(seconds: 10),
            onTimeout: () async {
              await cancel();
              throw const AudioSourceException(
                'Tempo massimo del bridge Android superato.',
              );
            },
          );
      cancellation.throwIfCancelled();
      // Search metadata is returned once, not on both streams, avoiding races
      // between MethodChannel completion and EventChannel stdout delivery.
      for (final line in (response?['output'] as String? ?? '').split('\n')) {
        if (line.startsWith('{')) onLine(line);
      }
      if (callbackError != null) {
        throw AudioSourceException(
          'Metadati/progresso Android non validi: $callbackError',
        );
      }
    } on PlatformException catch (error) {
      if (cancellation.isCancelled || error.code == 'CANCELLED') {
        throw const DownloadCancelledException();
      }
      throw AudioSourceException(
        'YouTube Android: ${error.message ?? error.code}',
      );
    } on MissingPluginException {
      throw const AudioSourceException(
        'Bridge Android non disponibile. Ricompila e reinstalla l’APK.',
      );
    } finally {
      completed = true;
      await subscription.cancel();
    }
  }
}
