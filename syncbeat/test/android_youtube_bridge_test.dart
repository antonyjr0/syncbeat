import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/android_youtube_bridge.dart';
import 'package:syncbeat/features/audio_sources/audio_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('syncbeat/youtube');
  const events = MethodChannel('syncbeat/youtube/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(events, null);
    messenger.setMockMethodCallHandler(methods, null);
  });
  Future<void> emit(Map<String, Object?> event) async {
    await messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  test(
    'bridge passes arguments/timeout, decodes metadata and ignores events for other operations',
    () async {
      final response = Completer<Map<String, dynamic>>();
      final started = Completer<MethodCall>();
      messenger.setMockMethodCallHandler(methods, (call) async {
        started.complete(call);
        return response.future;
      });
      final lines = <String>[];
      final task = AndroidYoutubeBridge().run(
        ['--dump-json', '--flat-playlist', '--', 'ytsearch10:artist title'],
        cancellation: DownloadCancellationToken(),
        onLine: lines.add,
        timeout: const Duration(seconds: 30),
      );
      final call = await started.future;
      expect(call.method, 'run');
      expect(call.arguments['timeoutMs'], 30000);
      expect(call.arguments['arguments'], contains('--flat-playlist'));
      expect(call.arguments['arguments'], contains('ytsearch10:artist title'));
      await emit({'id': 'other', 'line': 'ignore'});
      await emit({
        'id': call.arguments['id'],
        'line': 'SYNCBEAT:{"downloaded_bytes":10}',
      });
      response.complete({'output': '{"id":"PzYnwqUGI7Q"}\n'});
      await task;
      expect(lines, [
        'SYNCBEAT:{"downloaded_bytes":10}',
        '{"id":"PzYnwqUGI7Q"}',
      ]);
    },
  );
  test('cancellation reaches native job ID and reports cancellation', () async {
    final response = Completer<Map<String, dynamic>>();
    final started = Completer<String>();
    String? cancelledId;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'run') {
        started.complete(call.arguments['id']);
        return response.future;
      }
      if (call.method == 'cancel') {
        cancelledId = call.arguments['id'];
        response.completeError(PlatformException(code: 'CANCELLED'));
      }
      return null;
    });
    final cancellation = DownloadCancellationToken();
    final task = AndroidYoutubeBridge().run(
      ['--dump-json', '--', 'ytsearch5:test'],
      cancellation: cancellation,
      onLine: (_) {},
      timeout: const Duration(seconds: 30),
    );
    final expected = expectLater(
      task,
      throwsA(isA<DownloadCancelledException>()),
    );
    final id = await started.future;
    cancellation.cancel();
    await expected;
    expect(cancelledId, id);
  });
  test(
    'native timeout and network failures become actionable source errors',
    () async {
      messenger.setMockMethodCallHandler(
        methods,
        (_) async => throw PlatformException(
          code: 'TIMEOUT',
          message: 'Tempo massimo superato',
        ),
      );
      await expectLater(
        AndroidYoutubeBridge().run(
          ['--dump-json', '--', 'ytsearch5:test'],
          cancellation: DownloadCancellationToken(),
          onLine: (_) {},
          timeout: const Duration(seconds: 30),
        ),
        throwsA(isA<AudioSourceException>()),
      );
    },
  );
  test('already cancelled request never starts native work', () async {
    var called = false;
    messenger.setMockMethodCallHandler(methods, (_) async {
      called = true;
      return null;
    });
    final token = DownloadCancellationToken()..cancel();
    await expectLater(
      AndroidYoutubeBridge().run(
        [],
        cancellation: token,
        onLine: (_) {},
        timeout: const Duration(seconds: 30),
      ),
      throwsA(isA<DownloadCancelledException>()),
    );
    expect(called, isFalse);
  });
}
