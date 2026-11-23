import 'dart:async';

import 'package:path/path.dart' as p;

import '../audio_sources/public_audio_storage.dart';
import 'zepp_client.dart';

class ZeppDownloadSetupRequired extends ZeppException {
  const ZeppDownloadSetupRequired(super.message);
}

/// One saved file, one attempt. Uses the existing send/finally/restore flow.
class ZeppDownloadTransfer {
  ZeppDownloadTransfer({this.client = const ZeppClient()});

  final ZeppClient client;
  static bool _busy = false;
  bool _cancelled = false;
  bool _nativeStarted = false;

  Future<void> send(
    PublishedAudio file, {
    required String title,
    required String artist,
    required void Function(ZeppEvent) onEvent,
  }) async {
    if (_busy) {
      throw const ZeppException(
        'Un invio è già in corso. Il file è salvato; attendi la fine prima di riprovare.',
      );
    }
    _busy = true;
    _cancelled = false;
    StreamSubscription<ZeppEvent>? events;
    try {
      onEvent(const ZeppEvent.status('Preparazione invio all’orologio…'));
      final configured = <(ZeppDevice, String)>[];
      final preferred = await client.preferredDownloadDevice();
      _checkCancellation();
      final devices = await client.devices();
      _checkCancellation();
      for (final device in devices) {
        if (preferred != null && device.address != preferred) continue;
        final key = await client.savedKey(device);
        _checkCancellation();
        if (key != null && isValidZeppKey(key)) configured.add((device, key));
      }
      if (configured.length != 1) {
        throw const ZeppDownloadSetupRequired(
          'Configura un solo orologio per l’invio automatico.',
        );
      }
      final state = await client.coordinationStatus();
      _checkCancellation();
      if (state['pendingRestore'] == true) {
        throw const ZeppException(
          'Il file è salvato, ma il ripristino di Zepp va completato prima di un nuovo invio. '
          'Apri Impostazioni → App → Zepp → Autorizzazioni → Dispositivi nelle vicinanze '
          'e ripristina l’autorizzazione, oppure usa Ripristina permessi Zepp con Wi-Fi e ADB collegato.',
        );
      }
      if (state['enabled'] != true) {
        throw const ZeppDownloadSetupRequired(
          'Completa la configurazione iniziale dell’invio automatico.',
        );
      }
      final (device, key) = configured.single;
      events = client.events.listen(onEvent, onError: (_) {});
      _checkCancellation();
      _nativeStarted = true;
      await client.send(
        device: device,
        key: key,
        path: file.path,
        title: _metadata(
          title.trim().isEmpty ? p.basenameWithoutExtension(file.name) : title,
        ),
        artist: _metadata(artist),
        coordinateZepp: true,
      );
      onEvent(
        const ZeppEvent.status(
          'Invio completato: ultimo blocco confermato dall’orologio e permessi Zepp ripristinati.',
        ),
      );
    } finally {
      try {
        await events?.cancel();
      } finally {
        _nativeStarted = false;
        _busy = false;
      }
    }
  }

  static String _metadata(String value) => prepareZeppMusicMetadata(
    value.replaceAll(RegExp(r'[\x00-\x1f\x7f&?#%=]'), ' '),
  );

  void _checkCancellation() {
    if (_cancelled) {
      throw const ZeppException('Invio annullato. Il file resta salvato.');
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    if (_nativeStarted) await client.cancel();
  }
}
