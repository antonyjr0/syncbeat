import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/zepp/adb_connection_attempt.dart';
import 'package:syncbeat/features/zepp/zepp_adb_stream.dart';

Matcher outcome(String code) =>
    isA<ZeppBootstrapException>().having((e) => e.code, 'code', code);

void main() {
  test('one connection, TLS required, no probing or retries', () async {
    var calls = 0;
    await attemptAdbConnection(
      connect: () async {
        calls++;
        return true;
      },
      tlsEnabled: () => true,
    );
    expect(calls, 1);
    await expectLater(
      attemptAdbConnection(
        connect: () async {
          calls++;
          return true;
        },
        tlsEnabled: () => false,
      ),
      throwsA(outcome('ADB_TLS_REQUIRED')),
    );
    expect(calls, 2);
  });

  test(
    'captures dependency refusal and suppresses raw endpoint diagnostic',
    () async {
      final printed = <String>[];
      var calls = 0;
      await runZoned(
        () async {
          await expectLater(
            attemptAdbConnection(
              connect: () async {
                calls++;
                // Synthetic metadata must never reach the outer logger.
                Zone.current.print(
                  'Failed to connect to ADB: SocketException: Connection refused, address = PRIVATE-ENDPOINT, errno = 111',
                );
                return false;
              },
              tlsEnabled: () => false,
            ),
            throwsA(outcome('ADB_CONNECT_REFUSED')),
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(calls, 1);
      expect(printed, isEmpty);
    },
  );

  test(
    'deadline differs from refusal and does not cause a second connection',
    () async {
      var calls = 0;
      final pending = Completer<bool>();
      await expectLater(
        attemptAdbConnection(
          connect: () {
            calls++;
            return pending.future;
          },
          tlsEnabled: () => false,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(outcome('ADB_CONNECT_TIMEOUT')),
      );
      expect(calls, 1);
      pending.complete(false);
    },
  );

  test(
    'unconfirmed handshake is not called a missing Android privilege',
    () async {
      await expectLater(
        attemptAdbConnection(
          connect: () async => false,
          tlsEnabled: () => false,
        ),
        throwsA(outcome('ADB_HANDSHAKE_REJECTED')),
      );
      await expectLater(
        attemptAdbConnection(
          connect: () async => throw const SocketException(
            'synthetic',
            osError: OSError('refused', 111),
          ),
          tlsEnabled: () => false,
        ),
        throwsA(outcome('ADB_CONNECT_REFUSED')),
      );
    },
  );
}
