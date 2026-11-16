import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';
import 'package:syncbeat/features/zepp/zepp_client.dart';
import 'package:syncbeat/features/zepp/zepp_transfer_dialog.dart';

const _goodKey = '00112233445566778899aabbccddeeff';

void main() {
  test('validazione chiave e metadati', () {
    expect(isValidZeppKey(_goodKey), isTrue);
    expect(isValidZeppKey('0x$_goodKey'), isTrue);
    expect(isValidZeppKey('zz112233445566778899aabbccddeeff'), isFalse);
    expect(isValidZeppKey('0011'), isFalse);
    expect(validateZeppMetadata('Titolo ok'), isNull);
    expect(validateZeppMetadata('a&b'), isNotNull);
    expect(validateZeppMetadata('', required: true), isNotNull);
    expect(validateZeppMetadata('è' * 101), isNotNull);
    expect(validateZeppMetadata('è' * 100), isNull);
  });

  group('canale nativo', () {
    final calls = <MethodCall>[];
    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('syncbeat/zepp'), (
            call,
          ) async {
            calls.add(call);
            if (call.method == 'devices') {
              return [
                {'name': 'Amazfit Active 3', 'address': 'AA:BB:CC:DD:EE:FF'},
              ];
            }
            if (call.method == 'run' && call.arguments['key'] == 'fail') {
              throw PlatformException(code: 'ZEPP', message: 'Rifiutata');
            }
            return null;
          });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('syncbeat/zepp'), null),
    );

    test('devices e send passano i parametri attesi', () async {
      const client = ZeppClient();
      final devices = await client.devices();
      expect(devices.single.label, 'Amazfit Active 3 · ...EE:FF');
      await client.send(
        device: devices.single,
        key: ' $_goodKey ',
        path: 'content://media/42',
        title: 'T',
        artist: 'A',
      );
      final run = calls.last;
      expect(run.method, 'run');
      expect(run.arguments, {
        'address': 'AA:BB:CC:DD:EE:FF',
        'key': _goodKey,
        'send': true,
        'path': 'content://media/42',
        'title': 'T',
        'artist': 'A',
      });
      await client.verify(device: devices.single, key: _goodKey);
      expect(calls.last.arguments['send'], false);
      expect(calls.last.arguments.containsKey('path'), isFalse);
    });

    test('errori nativi diventano ZeppException', () async {
      const client = ZeppClient();
      expect(
        () => client.verify(
          device: const ZeppDevice('x', 'AA'),
          key: 'fail',
        ),
        throwsA(isA<ZeppException>()),
      );
    });
  });

  group('finestra', () {
    const file = PublishedAudio('content://media/42', 'Brano.mp3');

    testWidgets('chiave non valida: nessuna chiamata nativa di invio', (
      tester,
    ) async {
      final client = _FakeClient();
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showZeppTransferDialog(context, file, client: client),
              child: const Text('apri'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Mostra dispositivi abbinati'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zepp-device')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orologio test · ...EE:FF').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('zepp-key')), '1234');
      await tester.ensureVisible(find.byKey(const Key('zepp-send')));
      await tester.tap(find.byKey(const Key('zepp-send')));
      await tester.pumpAndSettle();
      expect(find.text('Servono 32 cifre esadecimali (0-9, a-f)'), findsOneWidget);
      expect(client.sent, isEmpty);
    });

    testWidgets('invio: conferma, svuota la chiave, mostra esito', (
      tester,
    ) async {
      final client = _FakeClient();
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showZeppTransferDialog(context, file, client: client),
              child: const Text('apri'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Mostra dispositivi abbinati'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zepp-device')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orologio test · ...EE:FF').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('zepp-key')), _goodKey);
      await tester.ensureVisible(find.byKey(const Key('zepp-send')));
      await tester.tap(find.byKey(const Key('zepp-send')));
      await tester.pumpAndSettle();
      expect(find.text('Inviare questo MP3?'), findsOneWidget);
      expect(client.sent, isEmpty, reason: 'niente invio prima della conferma');
      await tester.tap(find.text('Invia'));
      await tester.pumpAndSettle();
      expect(client.sent.single['path'], 'content://media/42');
      expect(client.sent.single['title'], 'Brano');
      expect(client.sent.single['key'], _goodKey);
      final field = tester.widget<TextFormField>(
        find.byKey(const Key('zepp-key')),
      );
      expect(field.controller!.text, isEmpty);
      expect(find.textContaining('Ultimo blocco confermato'), findsOneWidget);
    });

    testWidgets('errore nativo mostrato senza ritentare', (tester) async {
      final client = _FakeClient()..error = 'Autenticazione rifiutata';
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showZeppTransferDialog(context, file, client: client),
              child: const Text('apri'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Mostra dispositivi abbinati'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zepp-device')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orologio test · ...EE:FF').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('zepp-key')), _goodKey);
      await tester.ensureVisible(find.byKey(const Key('zepp-verify')));
      await tester.tap(find.byKey(const Key('zepp-verify')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verifica'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Autenticazione rifiutata'), findsOneWidget);
      expect(find.textContaining('nessun nuovo tentativo'), findsOneWidget);
      expect(client.verified, 1);
      expect(client.secure, [true]);
    });
  });
}

class _FakeClient extends ZeppClient {
  final sent = <Map<String, String>>[];
  int verified = 0;
  String? error;

  final secure = <bool>[];

  @override
  Future<void> secureScreen(bool enabled) async => secure.add(enabled);

  @override
  Stream<ZeppEvent> get events => const Stream.empty();

  @override
  Future<List<ZeppDevice>> devices() async => const [
    ZeppDevice('Orologio test', 'AA:BB:CC:DD:EE:FF'),
  ];

  @override
  Future<void> verify({required ZeppDevice device, required String key}) async {
    verified++;
    if (error != null) throw ZeppException(error!);
  }

  @override
  Future<void> send({
    required ZeppDevice device,
    required String key,
    required String path,
    required String title,
    required String artist,
  }) async {
    sent.add({'key': key, 'path': path, 'title': title, 'artist': artist});
    if (error != null) throw ZeppException(error!);
  }
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
