import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/zepp/embedded_adb.dart';
import 'package:syncbeat/features/zepp/embedded_adb_setup.dart';
import 'package:syncbeat/features/zepp/zepp_adb_stream.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'one explicit button, no extra dialog or automatic grant; failure=$fail',
      (tester) async {
        final adb = _Adb()..fail = fail;
        await tester.binding.setSurfaceSize(const Size(393, 852));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: EmbeddedAdbSetup(adb: adb)),
          ),
        );
        await tester.pumpAndSettle();
        expect(adb.grants, 0);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Dettagli'), findsNothing);
        expect(
          find.text(
            'Consente a SyncBeat di attivare il Debug wireless tramite un’autorizzazione alle impostazioni protette di Android.',
          ),
          findsOneWidget,
        );
        final button = find.text('Abilita collegamento automatico');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(adb.grants, 1);
        expect(adb.approved, isTrue);
        expect(find.byType(AlertDialog), findsOneWidget);
        if (fail) {
          expect(find.text('Autorizzazione non confermata.'), findsOneWidget);
          await tester.pumpAndSettle();
          expect(adb.grants, 1);
          expect(button, findsOneWidget);
        } else {
          expect(find.text('Collegamento automatico abilitato.'), findsWidgets);
          expect(button, findsNothing);
        }
      },
    );
  }
  testWidgets('pairing and connecting do not grant the privilege', (
    tester,
  ) async {
    final adb = _Adb();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmbeddedAdbSetup(adb: adb)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbina dalla notifica'));
    await tester.pumpAndSettle();
    expect(adb.pairings, 1);
    expect(adb.connections, 1);
    expect(adb.grants, 0);
    expect(find.text('Abilita collegamento automatico'), findsOneWidget);
  });
}

class _Adb implements EmbeddedAdb {
  int grants = 0, pairings = 0, connections = 0;
  bool granted = false, fail = false, approved = false;
  @override
  int? get connectionPort => null;
  @override
  Future<bool> automaticActivationAuthorized() async => granted;
  @override
  Future<void> authorizeAutomaticActivation({
    required bool userApproved,
  }) async {
    grants++;
    approved = userApproved;
    if (fail) {
      throw const ZeppBootstrapException(
        'ADB_GRANT_FAILED',
        'Autorizzazione non confermata.',
      );
    }
    granted = true;
  }

  @override
  Future<void> pairFromNotification() async {
    pairings++;
  }

  @override
  Future<void> connectAutomatically() async {
    connections++;
  }

  @override
  Future<void> prepareForUse({bool alreadyConnected = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
