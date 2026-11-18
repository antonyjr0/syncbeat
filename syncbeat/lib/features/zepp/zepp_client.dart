import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'embedded_adb.dart';

/// Un orologio Bluetooth gia' abbinato al telefono.
class ZeppDevice {
  const ZeppDevice(this.name, this.address);
  final String name;
  final String address;

  /// Mostra solo la coda dell'indirizzo, abbastanza per distinguere due dispositivi.
  String get label {
    final tail = address.length > 5
        ? address.substring(address.length - 5)
        : address;
    return '$name · ...$tail';
  }
}

/// Aggiornamento mostrato durante l'operazione (stato testuale o avanzamento).
class ZeppEvent {
  const ZeppEvent.status(this.text) : done = 0, total = 0;
  const ZeppEvent.progress(this.done, this.total) : text = null;
  final String? text;
  final int done;
  final int total;
  bool get isProgress => text == null;
}

class ZeppException implements Exception {
  const ZeppException(this.message);
  final String message;
  @override
  String toString() => message;
}

const zeppMaxBytes = 32 * 1024 * 1024;
const zeppMusicMetadataMaxBytes = 31;

/// Match the installed Zepp music flow without splitting UTF-8 characters.
String prepareZeppMusicMetadata(String value) {
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in value.trim().runes) {
    final text = String.fromCharCode(rune);
    final size = _utf8Length(text);
    if (bytes + size > zeppMusicMetadataMaxBytes) break;
    result.write(text);
    bytes += size;
  }
  return result.toString();
}

/// Stessa regola del codice nativo: niente separatori del protocollo.
String? validateZeppMetadata(String value, {bool required = false}) {
  if (required && value.trim().isEmpty) return 'Obbligatorio';
  if (_utf8Length(value) > zeppMusicMetadataMaxBytes) {
    return 'Massimo 31 byte';
  }
  for (final unit in value.runes) {
    if (unit < 32 ||
        unit == 127 ||
        '&?#%='.contains(String.fromCharCode(unit))) {
      return 'Evita caratteri di controllo e & ? # % =';
    }
  }
  return null;
}

int _utf8Length(String value) => value.runes.fold(
  0,
  (sum, r) =>
      sum +
      (r < 0x80
          ? 1
          : r < 0x800
          ? 2
          : r < 0x10000
          ? 3
          : 4),
);

/// La chiave Zepp: 32 cifre esadecimali, con o senza prefisso 0x.
bool isValidZeppKey(String value) =>
    RegExp(r'^(0[xX])?[0-9a-fA-F]{32}$').hasMatch(value.trim());

/// Ponte verso il codice Android. Funziona solo su Android.
class ZeppClient {
  const ZeppClient();
  static const _channel = MethodChannel('syncbeat/zepp');
  static const _events = EventChannel('syncbeat/zepp/events');
  static const _storage = FlutterSecureStorage();
  String _storageKey(ZeppDevice device) =>
      'zepp_pairing_v1_${device.address.toUpperCase()}';

  Future<String?> savedKey(ZeppDevice device) =>
      _storage.read(key: _storageKey(device));
  Future<void> rememberKey(ZeppDevice device, String key) =>
      _storage.write(key: _storageKey(device), value: key.trim());
  Future<void> forgetKey(ZeppDevice device) =>
      _storage.delete(key: _storageKey(device));

  Future<List<String>> probeParallelBle(ZeppDevice device) async {
    try {
      return await _channel.invokeListMethod<String>('probeBle', {
            'address': device.address,
          }) ??
          const [];
    } on PlatformException catch (error) {
      throw ZeppException(error.message ?? 'Verifica BLE non disponibile.');
    }
  }

  Future<void> openOfficialApp() async {
    try {
      await _channel.invokeMethod<void>('openZepp');
    } on PlatformException catch (error) {
      throw ZeppException(error.message ?? 'Impossibile aprire Zepp.');
    }
  }

  Future<Map<String, dynamic>> coordinationStatus() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('adbStatus') ??
          {'state': 'not_running'};
    } on PlatformException catch (error) {
      throw ZeppException(
        error.message ?? 'Stato debug wireless non disponibile.',
      );
    }
  }

  Future<bool> authorizeCoordination() async {
    if (!await EmbeddedAdb.instance.reconnect()) return false;
    return await _channel.invokeMethod<bool>('authorizeAdb') ?? false;
  }

  Future<void> setCoordinationEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setZeppCoordination', {'enabled': enabled});

  Future<void> restoreZeppPermissions() =>
      _coordinationAction('restoreZeppPermissions');
  Future<void> testZeppPermissions() =>
      _coordinationAction('testZeppPermissions');

  Future<void> _coordinationAction(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      throw ZeppException(
        error.message ?? 'Gestione permessi Zepp non riuscita.',
      );
    }
  }

  Stream<ZeppEvent> get events => _events.receiveBroadcastStream().map((raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    return map['type'] == 'progress'
        ? ZeppEvent.progress(map['done'] as int, map['total'] as int)
        : ZeppEvent.status(map['text'] as String);
  });

  Future<List<ZeppDevice>> devices() async {
    try {
      final raw = await _channel.invokeListMethod<Map>('devices') ?? const [];
      return [
        for (final item in raw)
          ZeppDevice(item['name'] as String, item['address'] as String),
      ];
    } on PlatformException catch (error) {
      throw ZeppException(error.message ?? 'Bluetooth non disponibile');
    }
  }

  /// Collega, autentica e legge le capacita'. Non invia musica.
  Future<void> verify({
    required ZeppDevice device,
    required String key,
    bool coordinateZepp = false,
  }) => _run({
    'address': device.address,
    'key': key.trim(),
    'send': false,
    if (coordinateZepp) 'coordinateZepp': true,
  });

  /// Come [verify], poi invia un solo MP3 al lettore Musica dell'orologio.
  Future<void> send({
    required ZeppDevice device,
    required String key,
    required String path,
    required String title,
    required String artist,
    bool coordinateZepp = false,
  }) => _run({
    'address': device.address,
    'key': key.trim(),
    'send': true,
    'path': path,
    'title': title,
    'artist': artist,
    if (coordinateZepp) 'coordinateZepp': true,
  });

  Future<void> _run(Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<Object?>('run', arguments);
    } on PlatformException catch (error) {
      throw ZeppException(error.message ?? 'Operazione non riuscita');
    }
  }

  /// Blocca screenshot e registrazione dello schermo finche' la finestra e' aperta.
  Future<void> secureScreen(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('secure', {'enabled': enabled});
    } on MissingPluginException {
      // Piattaforme senza il ponte nativo (test, desktop).
    }
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
  Future<String> licenses() async =>
      await _channel.invokeMethod<String>('licenses') ?? '';
}
