import 'package:flutter/services.dart';

import 'zepp_client.dart';

/// Client del flusso di riferimento Zepp OS (confronto con [ZeppClient]).
/// Stessa interfaccia, canali separati: il dialog del trasferimento lo sceglie
/// con l'interruttore "Flusso di riferimento".
class ZeppRefClient implements ZeppClient {
  const ZeppRefClient();
  static const _channel = MethodChannel('syncbeat/zepp_ref');
  static const _events = EventChannel('syncbeat/zepp_ref/events');

  @override
  Stream<ZeppEvent> get events => _events.receiveBroadcastStream().map((raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    return map['type'] == 'progress'
        ? ZeppEvent.progress(map['done'] as int, map['total'] as int)
        : ZeppEvent.status(map['text'] as String);
  });

  @override
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

  /// Collega, autentica e legge le capacita' col flusso di riferimento.
  @override
  Future<void> verify({required ZeppDevice device, required String key}) =>
      _run({'address': device.address, 'key': key.trim(), 'send': false});

  /// Come [verify], poi invia un solo MP3 col flusso di riferimento.
  @override
  Future<void> send({
    required ZeppDevice device,
    required String key,
    required String path,
    required String title,
    required String artist,
  }) => _run({
    'address': device.address,
    'key': key.trim(),
    'send': true,
    'path': path,
    'title': title,
    'artist': artist,
  });

  Future<void> _run(Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod<Object?>('run', arguments);
    } on PlatformException catch (error) {
      throw ZeppException(error.message ?? 'Operazione non riuscita');
    }
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  /// Indipendente dal flusso: stessa finestra, stessa regola.
  @override
  Future<void> secureScreen(bool enabled) =>
      const ZeppClient().secureScreen(enabled);

  /// Le licenze sono quelle del codice Zepp gia' presente, identiche.
  @override
  Future<String> licenses() => const ZeppClient().licenses();
}
