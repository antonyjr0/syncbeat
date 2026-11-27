import 'dart:io';

import 'zepp_adb_stream.dart';
import 'zepp_diagnostics.dart';

const adbConnectServiceType = '_adb-tls-connect._tcp';

String normalizeAdbServiceType(String type) {
  final normalized = type.toLowerCase().replaceAll(RegExp(r'^\.+|\.+$'), '');
  return normalized.endsWith('.local')
      ? normalized.substring(0, normalized.length - 6)
      : normalized;
}

/// Discovery metadata is untrusted. Never connect to an advertised remote host.
/// Return only the port of one service resolved to an address owned by this phone.
int selectSelfAdbConnectPort(Map<Object?, Object?> snapshot) {
  String? addressKey(Object? value) {
    if (value is! String) return null;
    final address = InternetAddress.tryParse(value);
    if (address == null ||
        address.isLoopback ||
        address.isMulticast ||
        address.rawAddress.every((byte) => byte == 0)) {
      return null;
    }
    return address.rawAddress
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  final local = snapshot['localAddresses'];
  final services = snapshot['services'];
  if (local is! List || services is! List) {
    throw const ZeppBootstrapException(
      'ADB_DISCOVERY_INVALID',
      'Risposta della ricerca Debug wireless non valida.',
    );
  }
  final localAddresses = local.map(addressKey).whereType<String>().toSet();
  final candidates = <String, int>{};
  for (final item in services) {
    if (item is! Map) continue;
    final name = item['name'];
    final type = item['type'];
    final port = item['port'];
    final hosts = item['addresses'];
    if (type is! String ||
        normalizeAdbServiceType(type) != adbConnectServiceType ||
        name is! String ||
        // Android may append a DNS-SD collision suffix. Excluding it can
        // falsely leave one stale, unsuffixed advertisement as the sole match.
        !RegExp(
          r'^adb-[A-Za-z0-9_.-]+(?: \((?:[2-9]|[1-9][0-9]+)\))?$',
        ).hasMatch(name) ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        hosts is! List) {
      continue;
    }
    if (!hosts
        .map(addressKey)
        .whereType<String>()
        .any(localAddresses.contains)) {
      continue;
    }
    candidates['$name:$port'] = port;
  }
  zeppDiagnostic('ADB_DISCOVERY_CANDIDATES', request: candidates.length);
  if (candidates.length != 1) {
    throw ZeppBootstrapException(
      candidates.isEmpty
          ? 'ADB_DISCOVERY_NOT_FOUND'
          : 'ADB_DISCOVERY_AMBIGUOUS',
      candidates.isEmpty
          ? 'Debug wireless di questo telefono non trovato. Attiva Wi-Fi e Debug wireless e autorizza SyncBeat la prima volta.'
          : 'Android annuncia più porte Debug wireless per questo telefono. '
                'La porta attuale non è identificabile con certezza; collegamento interrotto.',
    );
  }
  return candidates.values.single;
}
