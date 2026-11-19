import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio_sources/public_audio_storage.dart';
import 'zepp_client.dart';
import 'zepp_transfer_dialog.dart';

Future<void> showWatchTransferOptions(
  BuildContext context,
  PublishedAudio file,
) async {
  try {
    final state = await const ZeppClient().coordinationStatus();
    if (!context.mounted) return;
    if (state['enabled'] == true) {
      await showZeppTransferDialog(context, file);
      return;
    }
  } catch (_) {
    // Keep the ordinary Zepp handoff available when coordination is unavailable.
  }
  final direct = await showDialog<bool>(
    context: context,
    builder: (_) => ZeppHandoffDialog(file: file),
  );
  if (direct == true && context.mounted) {
    await showZeppTransferDialog(context, file);
  }
}

class ZeppHandoffDialog extends StatefulWidget {
  const ZeppHandoffDialog({
    super.key,
    required this.file,
    this.client = const ZeppClient(),
  });
  final PublishedAudio file;
  final ZeppClient client;

  @override
  State<ZeppHandoffDialog> createState() => _ZeppHandoffDialogState();
}

class _ZeppHandoffDialogState extends State<ZeppHandoffDialog> {
  bool _opening = false;
  String? _message;

  Future<void> _openZepp() async {
    setState(() {
      _opening = true;
      _message = null;
    });
    try {
      await widget.client.openOfficialApp();
      if (mounted) {
        setState(
          () => _message =
              'In Zepp apri Dispositivo → Musica → Carica musica e scegli il file indicato.',
        );
      }
    } on ZeppException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Porta il brano sull’orologio'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(widget.file.name),
            const SizedBox(height: 12),
            Text(
              widget.file.path.startsWith('content://')
                  ? 'Il file è pronto in Download/SyncBeat.'
                  : 'Questo file è nella memoria privata di SyncBeat: esportalo in Download prima di selezionarlo in Zepp.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Per mantenere Zepp collegata, completa l’invio dalla sua pagina Musica. SyncBeat apre Zepp; dovrai scegliere il file. Non viene avviato un trasferimento automatico.',
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.file.name));
                if (mounted) {
                  setState(
                    () => _message =
                        'Nome copiato. Puoi incollarlo nella ricerca del selettore file.',
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copia nome del file'),
            ),
            if (_message != null) Text(_message!),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _opening ? null : () => Navigator.pop(context, true),
              child: const Text('Invio diretto da SyncBeat (sperimentale)'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _opening ? null : () => Navigator.pop(context),
        child: const Text('Chiudi'),
      ),
      FilledButton.icon(
        onPressed: _opening || !widget.file.path.startsWith('content://')
            ? null
            : _openZepp,
        icon: const Icon(Icons.open_in_new),
        label: const Text('Apri Zepp per trasferire'),
      ),
    ],
  );
}
