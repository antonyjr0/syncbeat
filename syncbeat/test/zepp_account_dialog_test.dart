import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/audio_sources/public_audio_storage.dart';
import 'package:syncbeat/features/zepp/zepp_account.dart';
import 'package:syncbeat/features/zepp/zepp_account_dialog.dart';
import 'package:syncbeat/features/zepp/zepp_client.dart';
import 'package:syncbeat/features/zepp/zepp_transfer_dialog.dart';

const watch = ZeppDevice('Test watch', 'AA:BB:CC:DD:EE:FF');
const key = '00112233445566778899aabbccddeeff';

void main() {
  testWidgets(
    'opening and cancelling sends no credentials; blank submit validates locally',
    (tester) async {
      final account = _Account();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showZeppAccountRecovery(
                  context,
                  device: watch,
                  account: account,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(account.calls, 0);
      await tester.tap(find.text('Recupera chiave'));
      await tester.pumpAndSettle();
      expect(account.calls, 0);
      expect(
        find.text('Inserisci email e password del tuo account Zepp.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(account.calls, 0);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'download setup imports only after explicit request; failure=$fail preserves existing storage',
      (tester) async {
        tester.view.physicalSize = const Size(900, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final account = _Account();
        final client = _Client();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ZeppTransferDialog(
                file: const PublishedAudio('content://media/42', 'Test.mp3'),
                configureOnly: true,
                client: client,
                account: account,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<ZeppDevice>));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Test watch').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('zepp-account-connect')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(account.calls, 0);
        await tester.enterText(
          find.byKey(const Key('zepp-account-email')),
          'test@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('zepp-account-password')),
          'synthetic',
        );
        await tester.tap(find.text('Recupera chiave'));
        await tester.pump();
        expect(account.calls, 1);
        expect(client.saved, 'old-key');
        expect(find.byType(ZeppAccountDialog), findsOneWidget);
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        )) {
          expect(field.controller!.text, isEmpty);
        }
        if (fail) {
          account.result.completeError(
            const ZeppException('Accesso rifiutato'),
          );
        } else {
          account.result.complete(key);
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(client.saved, fail ? 'old-key' : key);
        expect(client.sends, 0);
        expect(client.authorizations, 0);
        if (fail) {
          expect(find.text('Accesso rifiutato'), findsOneWidget);
        } else {
          expect(find.byType(ZeppAccountDialog), findsNothing);
          expect(
            find.text(
              'Chiave recuperata e salvata per questo orologio. Nessun brano inviato.',
            ),
            findsOneWidget,
          );
          expect(find.text(key), findsNothing);
        }
      },
    );
  }
}

class _Account extends ZeppAccount {
  int calls = 0;
  final result = Completer<String>();
  @override
  Future<String> recoverKey({
    required String email,
    required String password,
    required ZeppDevice device,
  }) {
    calls++;
    expect(email, 'test@example.com');
    expect(password, 'synthetic');
    expect(device.address, watch.address);
    return result.future;
  }
}

class _Client extends ZeppClient {
  String saved = 'old-key';
  int sends = 0, authorizations = 0;
  @override
  Future<List<ZeppDevice>> devices() async => [watch];
  @override
  Future<String?> savedKey(ZeppDevice device) async => saved;
  @override
  Future<void> rememberKey(ZeppDevice device, String key) async {
    saved = key;
  }

  @override
  Future<void> secureScreen(bool enabled) async {}
  @override
  Future<Map<String, dynamic>> coordinationStatus() async => {
    'state': 'ready',
    'enabled': false,
  };
  @override
  Stream<ZeppEvent> get events => const Stream.empty();
  @override
  Future<bool> authorizeCoordination() async {
    authorizations++;
    return true;
  }

  @override
  Future<void> send({
    required ZeppDevice device,
    required String key,
    required String path,
    required String title,
    required String artist,
    bool coordinateZepp = false,
  }) async {
    sends++;
  }
}
