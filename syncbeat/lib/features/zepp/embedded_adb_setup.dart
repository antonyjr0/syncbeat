import 'package:flutter/material.dart';
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
  final _pairPort = TextEditingController();
  final _connectPort = TextEditingController(
    text: EmbeddedAdb.instance.connectionPort?.toString(),
  );
  final _code = TextEditingController();
  bool _busy = false;
  String? _message;

  Future<void> _run(bool pairing) async {
    setState(() {
      _busy = true;
      _message = pairing ? 'Abbinamento in corso…' : 'Connessione in corso…';
    });
    try {
      if (pairing) {
        await EmbeddedAdb.instance.pair(
          EmbeddedAdb.validatePort(_pairPort.text),
          _code.text.trim(),
        );
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
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = pairing
              ? 'Abbinamento non riuscito. Apri un nuovo codice con la relativa porta e riprova.'
              : 'Connessione non riuscita. Usa la porta della pagina principale Debug wireless, non quella di abbinamento.',
        );
      }
    } finally {
      if (mounted) {
        _code.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _pairPort.dispose();
    _connectPort.dispose();
    _code.clear();
    _code.dispose();
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
                  : () => EmbeddedAdb.channel.invokeMethod<void>('settings'),
              child: const Text('Apri Opzioni sviluppatore'),
            ),
            const Text(
              'Apri Debug wireless → Associa dispositivo con codice. Usa lo schermo diviso: chiudendo quella finestra il codice può scadere.',
            ),
            TextField(
              controller: _pairPort,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Porta di abbinamento',
              ),
            ),
            TextField(
              controller: _code,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              decoration: const InputDecoration(
                labelText: 'Codice temporaneo di 6 cifre',
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(true),
              child: const Text('Abbina'),
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
