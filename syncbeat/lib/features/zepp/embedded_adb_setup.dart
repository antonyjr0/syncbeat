import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'embedded_adb.dart';
import 'zepp_adb_stream.dart';

Future<void> showEmbeddedAdbSetup(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const EmbeddedAdbSetup(),
);

class EmbeddedAdbSetup extends StatefulWidget {
  const EmbeddedAdbSetup({super.key, this.adb});
  final EmbeddedAdb? adb;
  @override
  State<EmbeddedAdbSetup> createState() => _EmbeddedAdbSetupState();
}

class _EmbeddedAdbSetupState extends State<EmbeddedAdbSetup> {
  late final _adb = widget.adb ?? EmbeddedAdb.instance;
  late final _connectPort = TextEditingController(
    text: _adb.connectionPort?.toString(),
  );
  bool _busy = false;
  String? _message;
  bool _connectionError = false;
  bool? _automaticAuthorized;

  @override
  void initState() {
    super.initState();
    _refreshAuthorization();
  }

  Future<void> _refreshAuthorization() async {
    try {
      final granted = await _adb.automaticActivationAuthorized();
      if (mounted) setState(() => _automaticAuthorized = granted);
    } catch (_) {
      /* Keep the explicit action available; it verifies again. */
    }
  }

  Future<void> _authorizeAutomatic() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Abilitazione del collegamento automatico…';
    });
    try {
      await _adb.authorizeAutomaticActivation(userApproved: true);
      if (mounted) {
        setState(() {
          _automaticAuthorized = true;
          _message = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is ZeppBootstrapException
              ? error.message
              : 'Abilitazione non riuscita. Nessun nuovo tentativo automatico.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(bool pairing, {bool manual = false}) async {
    var connecting = !pairing;
    setState(() {
      _busy = true;
      _message = pairing
          ? 'Apri il codice in Debug wireless e rispondi alla notifica di SyncBeat.'
          : 'Connessione in corso…';
    });
    try {
      if (pairing) {
        await _adb.pairFromNotification();
        connecting = true;
      }
      if (manual) {
        await _adb.connect(EmbeddedAdb.validatePort(_connectPort.text));
      } else {
        await _adb.connectAutomatically();
      }
      await _adb.prepareForUse(alreadyConnected: true);
      await _refreshAuthorization();
      if (mounted) {
        setState(() {
          _connectionError = false;
          _message =
              'Collegamento autorizzato e pronto in SyncBeat. Puoi chiudere questa finestra.';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _connectionError = connecting;
          _message = error.message ?? 'Operazione non riuscita.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionError = connecting;
          _message = !connecting
              ? 'Abbinamento non riuscito. Riprova con un nuovo codice.'
              : 'Connessione automatica non riuscita. Controlla Wi-Fi e Debug wireless. Puoi usare la porta manuale come recupero.';
        });
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
                        await EmbeddedAdb.channel.invokeMethod<void>(
                          'settings',
                        );
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
              'La porta di connessione viene individuata automaticamente. '
              'Dopo il primo abbinamento l’app prepara il collegamento a ogni apertura. '
              'Android può richiedere di riattivare Debug wireless dopo un riavvio.',
            ),
            if (_connectionError)
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
              child: const Text('Collega automaticamente'),
            ),
            if (_connectionError)
              TextButton(
                onPressed: _busy ? null : () => _run(false, manual: true),
                child: const Text('Collega con porta manuale'),
              ),
            const SizedBox(height: 12),
            if (_automaticAuthorized != true) ...[
              const Text(
                'Consente a SyncBeat di attivare il Debug wireless tramite un’autorizzazione alle impostazioni protette di Android.',
              ),
              FilledButton(
                onPressed: _busy ? null : _authorizeAutomatic,
                child: const Text('Abilita collegamento automatico'),
              ),
            ] else
              const Text('Collegamento automatico abilitato.'),
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
