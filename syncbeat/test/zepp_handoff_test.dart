import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';
import 'package:syncbeat/features/zepp/zepp_handoff_dialog.dart';

void main() {
  for (final missing in [false, true]) {
    testWidgets('Zepp handoff opens only the official app; missing=$missing', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('syncbeat/zepp');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (missing) {
          throw PlatformException(
            code: 'ZEPP_MISSING',
            message: 'Zepp non disponibile',
          );
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.binding.setSurfaceSize(const Size(320, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const ZeppHandoffDialog(
                    file: PublishedAudio(
                      'content://media/external/downloads/42',
                      'Own tone.mp3',
                    ),
                  ),
                ),
                child: const Text('Apri'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Apri'));
      await tester.pumpAndSettle();
      expect(find.text('Own tone.mp3'), findsOneWidget);
      expect(find.textContaining('Download/SyncBeat'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.text('Apri Zepp per trasferire'));
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), ['openZepp']);
      expect(
        find.textContaining(
          missing ? 'Zepp non disponibile' : 'In Zepp apri Dispositivo',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Trasferimento completato'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
