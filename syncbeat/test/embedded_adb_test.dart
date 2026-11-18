import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/zepp/embedded_adb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rejects malformed pairing information before accessing keys or sockets',
    () async {
      final adb = EmbeddedAdb.instance;
      for (final port in [0, -1, 65536]) {
        await expectLater(adb.pair(port, '123456'), throwsFormatException);
        await expectLater(adb.connect(port), throwsFormatException);
      }
      for (final code in ['', '12345', '1234567', 'abc123']) {
        await expectLater(adb.pair(42000, code), throwsFormatException);
      }
      expect(adb.ready, isFalse);
    },
  );
}
