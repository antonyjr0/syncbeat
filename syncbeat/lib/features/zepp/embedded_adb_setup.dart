import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'embedded_adb.dart';

Future<void> showEmbeddedAdbSetup(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const EmbeddedAdbSetup(),
);

class EmbeddedAdbSetup extends StatefulWidget {
  const EmbeddedAdbSetup({super.key});
  @override
  State<EmbeddedAdbSetup> createState() => _EmbeddedAdbSetupState();
}

class _EmbeddedAdbSetupState extends State<EmbeddedAdbSetup> {
  final _connectPort = TextEditingController(
    text: EmbeddedAdb.instance.connectionPort?.toString(),
  );
  bool _busy = false;
  String? _message;

  Future<void> _run(bool pairing) async {
    setState(() {
      _busy = true;
      _message = pairing
          ? 'Apri il codice in Debug wireless e rispondi alla notifica di SyncBeat.'
          : 'Connessione in corso…';
    });
    try {
      if (pairing) {
        await EmbeddedAdb.instance.pairFromNotification();
      } else {
        await EmbeddedAdb.instance.connect(
          EmbeddedAdb.validatePort(_connectPort.text),
        );
      }
      if (mounted) {
        setState(
          () => _message = pairing
              ? 'Abbinamento riuscito. Inserisci ora la porta principale di Debug wireless e premi Collega.'
              : 'ADB collegato in SyncBeat. Puoi chiudere e attivare Gestisci automaticamente Zepp.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _message = error.message ?? 'Operazione non riuscita.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = pairing
              ? 'Abbinamento non riuscito. Riprova con un nuovo codice.'
              : 'Connessione non riuscita. Usa la porta della pagina principale Debug wireless, non quella di abbinamento.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _connectPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Debug wireless in SyncBeat'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nessuna app aggiuntiva. Android 11+ richiede il debug wireless attivo su una rete Wi-Fi. Il collegamento è limitato a questo telefono.',
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await EmbeddedAdb.channel.invokeMethod<void>('settings');
                      } on PlatformException catch (error) {
                        if (mounted) setState(() => _message = error.message);
                      }
                    },
              child: const Text('Apri Debug wireless'),
            ),
            const Text(
              'Scegli «Accoppia dispositivo con codice di accoppiamento» in Debug wireless. Lascia aperto il codice e inseriscilo dalla notifica «Abbina SyncBeat».',
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(true),
              child: const Text('Abbina dalla notifica'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dopo l’abbinamento, torna alla pagina principale Debug wireless. La porta di connessione è diversa e può cambiare dopo un riavvio.',
            ),
            TextField(
              controller: _connectPort,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Porta di connessione',
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _run(false),
              child: const Text('Collega'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(_message!),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Chiudi'),
      ),
    ],
  );
}
