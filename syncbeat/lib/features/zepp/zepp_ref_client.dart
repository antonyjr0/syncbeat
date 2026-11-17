import 'package:flutter/services.dart';

import 'zepp_client.dart';

/// Client del flusso di riferimento Zepp OS (confronto con [ZeppClient]).
/// Stessa interfaccia, canali separati: per confrontare i due flussi basta
/// usare questo client al posto di ZeppClient nel punto di chiamata esistente.
class ZeppRefClient {
  const ZeppRefClient();
  static const _channel = MethodChannel('syncbeat/zepp_ref');
  static const _events = EventChannel('syncbeat/zepp_ref/events');

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

  /// Collega, autentica e legge le capacita' col flusso di riferimento.
  Future<void> verify({required ZeppDevice device, required String key}) =>
      _run({'address': device.address, 'key': key.trim(), 'send': false});

  /// Come [verify], poi invia un solo MP3 col flusso di riferimento.
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

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
