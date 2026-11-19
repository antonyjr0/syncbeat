import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/zepp/zepp_adb_requests.dart';

void main() {
  testWidgets('RESTORE waits behind BEGIN and ignores its late reply', (
    tester,
  ) async {
    final writes = <String>[];
    late ZeppAdbRequests requests;
    requests = ZeppAdbRequests((line) async {
      writes.add(line);
      return true;
    });
    Object? beginError;
    requests.request('BEGIN 780000').catchError((Object error) {
      beginError = error;
      return 'ERR';
    });
    var restored = false;
    final restore = requests.request('RESTORE').then((_) => restored = true);
    await tester.pump();
    expect(writes, ['1|BEGIN 780000\n']);
    await tester.pump(const Duration(seconds: 26));
    expect(beginError, isA<TimeoutException>());
    expect(writes, ['1|BEGIN 780000\n', '2|RESTORE\n']);
    // Server finishes the slow BEGIN before handling its queued RESTORE.
    requests.receive('1|OK');
    await tester.pump();
    expect(restored, isFalse);
    requests.receive('2|OK');
    await tester.pump();
    await restore;
    expect(restored, isTrue);
  });

  testWidgets('read-only STATUS and disconnect preserve request correlation', (
    tester,
  ) async {
    final requests = ZeppAdbRequests((_) async => true);
    final status = requests.request('STATUS');
    await tester.pump();
    requests.receive('1|STATUS:1:1:4');
    expect(await status, 'STATUS:1:1:4');
    final restore = requests.request('RESTORE');
    final failure = expectLater(restore, throwsStateError);
    await tester.pump();
    requests.disconnected();
    await failure;
  });
}
