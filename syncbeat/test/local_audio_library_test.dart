import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/local_audio_library.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';

class _Storage extends PublicAudioStorage {
  bool exists = true;
  @override
  Future<List<PublishedAudio>> list() async => exists
      ? [
          const PublishedAudio(
            'content://media/external/downloads/42',
            'Own tone.mp3',
          ),
        ]
      : [];
}

void main() {
  testWidgets(
    'published content URI is shown, played via native player, stopped and removed after external deletion',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('syncbeat-library-test-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final storage = _Storage();
      final calls = <MethodCall>[];
      const channel = MethodChannel('syncbeat/youtube');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'playbackState') {
              return {'playing': true, 'positionMs': 100, 'durationMs': 1000};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: LocalAudioLibrary(
              storage: storage,
              legacyDirectory: directory,
              android: true,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Own tone.mp3'), findsOneWidget);
      await tester.tap(find.byTooltip('Riproduci'));
      await tester.pump();
      expect(calls.first.method, 'play');
      expect((calls.first.arguments as Map)['path'], startsWith('content://'));
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      expect(calls.last.method, 'stop');
      storage.exists = false;
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.refresh));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Own tone.mp3'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
