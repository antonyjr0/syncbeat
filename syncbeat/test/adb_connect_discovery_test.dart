import 'package:flutter_test/flutter_test.dart';
import 'package:syncbeat/features/zepp/adb_connect_discovery.dart';
import 'package:syncbeat/features/zepp/zepp_adb_stream.dart';

Map<String, Object> service({
  String name = 'adb-self-connect',
  String host = '192.0.2.1',
  String type = adbConnectServiceType,
  int port = 43210,
}) => {
  'name': name,
  'type': type,
  'port': port,
  'addresses': [host],
};
Map<String, Object> snapshot(List<Map<String, Object>> services) => {
  'localAddresses': ['192.0.2.1', '2001:db8::1'],
  'services': services,
};
Matcher code(String value) =>
    isA<ZeppBootstrapException>().having((e) => e.code, 'code', value);

void main() {
  test('normalizes Android NSD dotted types, local suffix and DNS case', () {
    for (final type in [
      '._adb-tls-connect._tcp',
      '._adb-tls-connect._tcp.',
      '_ADB-TLS-CONNECT._TCP.local.',
    ]) {
      expect(selectSelfAdbConnectPort(snapshot([service(type: type)])), 43210);
    }
  });
  test(
    'selects this phone; ignores remote hosts and pairing advertisements',
    () {
      expect(
        selectSelfAdbConnectPort(
          snapshot([
            service(host: '192.0.2.2'),
            service(type: '_adb-tls-pairing._tcp', port: 12345),
            service(type: '$adbConnectServiceType.'),
          ]),
        ),
        43210,
      );
    },
  );
  test(
    'duplicate IPv4 and IPv6 resolutions of one instance are one candidate',
    () {
      expect(
        selectSelfAdbConnectPort(
          snapshot([
            service(),
            service(host: '2001:0db8:0:0:0:0:0:1'),
            service(),
          ]),
        ),
        43210,
      );
    },
  );
  test('multiple local instances or ports are ambiguous', () {
    for (final extra in [
      service(name: 'adb-second-connect'),
      service(port: 43211),
    ]) {
      expect(
        () => selectSelfAdbConnectPort(snapshot([service(), extra])),
        throwsA(code('ADB_DISCOVERY_AMBIGUOUS')),
      );
    }
  });
  test(
    'loopback, remote, malformed and out-of-range services are not candidates',
    () {
      for (final invalid in [
        service(host: '127.0.0.1'),
        service(host: '::1'),
        service(host: '0.0.0.0'),
        service(host: '192.0.2.2'),
        service(name: 'unrelated'),
        service(type: '_adb._tcp'),
        service(port: 0),
        service(port: 65536),
      ]) {
        expect(
          () => selectSelfAdbConnectPort(snapshot([invalid])),
          throwsA(code('ADB_DISCOVERY_NOT_FOUND')),
        );
      }
    },
  );
  test('invalid snapshot fails explicitly', () {
    expect(
      () => selectSelfAdbConnectPort({}),
      throwsA(code('ADB_DISCOVERY_INVALID')),
    );
  });
}
