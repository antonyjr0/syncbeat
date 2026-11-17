import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../audio_sources/public_audio_storage.dart';
import 'zepp_client.dart';
import 'zepp_ref_client.dart';

/// Finestra di dialogo, aperta dall'elenco "MP3 locali" gia' esistente, per
/// inviare un MP3 gia' scaricato al lettore Musica dell'orologio.
/// Non e' stato provato su un orologio reale: vedi docs/zepp-musica.it.md.
Future<void> showZeppTransferDialog(
  BuildContext context,
  PublishedAudio file, {
  ZeppClient client = const ZeppClient(),
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ZeppTransferDialog(file: file, client: client),
);

class ZeppTransferDialog extends StatefulWidget {
  const ZeppTransferDialog({
    super.key,
    required this.file,
    this.client = const ZeppClient(),
    this.events,
  });
  final PublishedAudio file;
  final ZeppClient client;

  /// Sostituibile nei test; di norma arriva dal canale Android.
  final Stream<ZeppEvent>? events;

  @override
  State<ZeppTransferDialog> createState() => _ZeppTransferDialogState();
}

class _ZeppTransferDialogState extends State<ZeppTransferDialog> {
  final _key = TextEditingController();
  late final _title = TextEditingController(
    text: p.basenameWithoutExtension(widget.file.name),
  );
  final _artist = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<ZeppDevice> _devices = const [];
  ZeppDevice? _device;
  StreamSubscription<ZeppEvent>? _sub;
  bool _busy = false;
  double? _progress;
  String? _status;
  bool _failed = false;
  bool _useRef = false;

  /// Il client attivo: quello abituale, oppure il flusso di riferimento
  /// (implementazione separata da Gadgetbridge/OronBox) se l'interruttore e' acceso.
  ZeppClient get _client => _useRef ? const ZeppRefClient() : widget.client;

  void _listen() {
    _sub = (widget.events ?? _client.events).listen((event) {
      if (!mounted || !_busy) return;
      setState(() {
        if (event.isProgress) {
          _progress = event.total == 0 ? null : event.done / event.total;
        } else {
          _status = event.text;
        }
      });
    }, onError: (_) {});
  }

  Future<void> _setRef(bool value) async {
    if (_busy) return;
    await _sub?.cancel();
    setState(() {
      _useRef = value;
      _devices = const [];
      _device = null;
      _status = null;
      _failed = false;
    });
    _listen();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_client.secureScreen(true));
    _listen();
  }

  @override
  void dispose() {
    unawaited(_client.secureScreen(false));
    _sub?.cancel();
    _key.clear();
    _key.dispose();
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _busy = true;
      _failed = false;
      _status = null;
    });
    try {
      final devices = await _client.devices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _device = null;
        _status = devices.isEmpty
            ? 'Nessun dispositivo abbinato. Non fare reset o nuovi abbinamenti per questa prova.'
            : 'Scegli il tuo orologio dall\'elenco. L\'elenco da solo non prova la compatibilita\'.';
      });
    } on ZeppException catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _start({required bool send}) async {
    if (_device == null) {
      setState(() {
        _failed = true;
        _status = 'Prima scegli l\'orologio dall\'elenco.';
      });
      return;
    }
    if (!_form.currentState!.validate()) return;
    final device = _device!;
    final ok = send
        ? await _confirm(
            'Inviare questo MP3?',
            'File: ${widget.file.name}\n'
                'Titolo: ${_title.text}\nArtista: ${_artist.text}\n'
                'Orologio: ${device.label}\n\n'
                'Scrive un brano nel lettore Musica originale. Non cancella altri file. '
                'Questa prova non ha un comando per togliere il brano: usa i controlli '
                'dell\'orologio o di Zepp. Se si interrompe puo\' restare un file parziale. '
                'Tieni l\'app aperta fino alla fine.',
            'Invia',
          )
        : await _confirm(
            'Verificare il collegamento?',
            'Orologio: ${device.label}\n\n'
                'Contatta solo questo dispositivo, si autentica e legge le capacita\'. '
                'Non invia musica. Assicurati che Zepp abbia finito la sincronizzazione.',
            'Verifica',
          );
    if (!ok || !mounted) return;
    final key = _key.text;
    _key.clear(); // la chiave non resta nel campo
    setState(() {
      _busy = true;
      _failed = false;
      _progress = null;
      _status = 'Avvio...';
    });
    try {
      if (send) {
        await _client.send(
          device: device,
          key: key,
          path: widget.file.path,
          title: _title.text,
          artist: _artist.text,
        );
      } else {
        await _client.verify(device: device, key: key);
      }
      if (!mounted) return;
      setState(() {
        _status = send
            ? 'Ultimo blocco confermato dall\'orologio. Controlla titolo e riproduzione '
                  'nel lettore Musica: da qui non si puo\' verificare. Poi controlla che Zepp funzioni ancora.'
            : 'Autenticazione riuscita e servizio music presente. Nessun brano inviato.';
      });
    } on ZeppException catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status =
              '${error.message}\nNessun reset e nessun nuovo tentativo automatico.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _licenses() async {
    final text = await _client.licenses();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Licenze del codice Zepp'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Invia all\'orologio'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(child: _body(context)),
    ),
    actions: [
      TextButton(onPressed: _licenses, child: const Text('Licenze')),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Chiudi'),
      ),
    ],
  );

  Widget _body(BuildContext context) => Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Funzione sperimentale, non ancora provata su un orologio reale. '
                  'Invia un MP3 al lettore Musica originale via Bluetooth Classic. '
                  'Serve la chiave di abbinamento Zepp (32 cifre esadecimali): '
                  'non viene salvata ne\' inviata online e il campo si svuota quando parte l\'operazione.',
                ),
              ),
            ),
            SwitchListTile(
              key: const Key('zepp-ref-flow'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Flusso di riferimento (confronto)'),
              subtitle: const Text(
                'Implementazione separata, scritta dalle fonti pubbliche '
                '(Gadgetbridge e OronBox), per confronto con quella abituale. '
                'Di norma spento: vedi docs/zepp-flusso-riferimento.it.md.',
              ),
              value: _useRef,
              onChanged: _busy ? null : _setRef,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.audio_file),
              title: Text(widget.file.name),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _loadDevices,
              icon: const Icon(Icons.bluetooth),
              label: const Text('1. Mostra dispositivi abbinati'),
            ),
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<ZeppDevice>(
                key: const Key('zepp-device'),
                initialValue: _device,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Orologio'),
                items: [
                  for (final d in _devices)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: _busy ? null : (d) => setState(() => _device = d),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('zepp-key'),
              controller: _key,
              enabled: !_busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '2. Chiave (32 cifre esadecimali)',
              ),
              validator: (v) => isValidZeppKey(v ?? '')
                  ? null
                  : 'Servono 32 cifre esadecimali (0-9, a-f)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('zepp-title'),
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Titolo'),
              validator: (v) => validateZeppMetadata(v ?? '', required: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('zepp-artist'),
              controller: _artist,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Artista'),
              validator: (v) => validateZeppMetadata(v ?? ''),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('zepp-verify'),
                  onPressed: _busy ? null : () => _start(send: false),
                  child: const Text('3. Verifica collegamento (non invia)'),
                ),
                FilledButton(
                  key: const Key('zepp-send'),
                  onPressed: _busy ? null : () => _start(send: true),
                  child: const Text('4. Invia MP3'),
                ),
                if (_busy)
                  TextButton(
                    onPressed: () => _client.cancel(),
                    child: const Text('Interrompi'),
                  ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                key: const Key('zepp-status'),
                style: TextStyle(
                  color: _failed ? Theme.of(context).colorScheme.error : null,
                ),
              ),
            ],
          ],
        ),
      );
}
