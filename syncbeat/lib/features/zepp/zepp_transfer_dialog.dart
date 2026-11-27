import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'embedded_adb_setup.dart';

import '../audio_sources/public_audio_storage.dart';
import 'zepp_client.dart';
import 'zepp_account.dart';
import 'zepp_account_dialog.dart';
import 'zepp_diagnostics.dart';

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

Future<bool> showWatchDownloadSetup(
  BuildContext context,
  PublishedAudio file,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ZeppTransferDialog(file: file, configureOnly: true),
    ) ??
    false;

class ZeppTransferDialog extends StatefulWidget {
  const ZeppTransferDialog({
    super.key,
    required this.file,
    this.client = const ZeppClient(),
    this.events,
    this.configureOnly = false,
    this.account,
  });
  final PublishedAudio file;
  final ZeppClient client;
  final bool configureOnly;
  final ZeppAccount? account;

  /// Sostituibile nei test; di norma arriva dal canale Android.
  final Stream<ZeppEvent>? events;

  @override
  State<ZeppTransferDialog> createState() => _ZeppTransferDialogState();
}

class _ZeppTransferDialogState extends State<ZeppTransferDialog>
    with WidgetsBindingObserver {
  final _key = TextEditingController();
  late final _title = TextEditingController(
    text: prepareZeppMusicMetadata(
      p.basenameWithoutExtension(widget.file.name),
    ),
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
  bool _hasSavedKey = false;
  bool _coordinateZepp = false;
  String _coordinationState = 'loading';
  bool _restorePending = false;
  String _leaseState = 'unavailable';

  Future<void> _refreshCoordination() async {
    try {
      final state = await widget.client.coordinationStatus();
      if (!mounted) return;
      setState(() {
        _coordinationState = state['state'] as String? ?? 'not_running';
        _coordinateZepp = state['enabled'] == true;
        _restorePending = state['pendingRestore'] == true;
        final diagnostics = state['diagnostics'] as Map?;
        _leaseState = diagnostics?['leaseState'] as String? ?? 'unavailable';
        zeppDiagnostic('UI_STATUS_READ');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _coordinationState = 'unavailable';
          _leaseState = 'unknown';
          _restorePending = true;
        });
      }
    }
  }

  Future<void> _setCoordination(bool enabled) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (enabled && !await widget.client.authorizeCoordination()) {
        throw const ZeppException(
          'Configura il debug wireless dentro SyncBeat. La modalità rimane disattivata.',
        );
      }
      await widget.client.setCoordinationEnabled(enabled);
      if (mounted) setState(() => _coordinateZepp = enabled);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = error is ZeppException
              ? error.message
              : 'Impossibile attivare la gestione di Zepp.';
        });
      }
    } finally {
      await _refreshCoordination();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareZeppHelper() async {
    setState(() {
      _busy = true;
      _failed = false;
      _status = 'Preparazione del servizio ADB…';
    });
    try {
      await widget.client.prepareZeppHelper();
      if (mounted) {
        setState(
          () => _status =
              'Servizio ADB pronto e collegato. Nessuna sospensione dei permessi richiesta.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = error is ZeppException
              ? error.message
              : 'Preparazione del servizio ADB non riuscita.';
        });
      }
    } finally {
      await _refreshCoordination();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOfflineHelper({required bool prepare}) async {
    setState(() {
      _busy = true;
      _failed = false;
      _status = prepare
          ? 'Preparazione del canale locale di prova…'
          : 'Lettura dello stato dal canale locale…';
    });
    try {
      await widget.client.offlineHelperStatus(prepare: prepare);
      if (mounted) {
        setState(
          () => _status = prepare
              ? 'Canale locale preparato. Puoi inviare i brani anche con il Wi-Fi spento finché il canale resta attivo.'
              : 'Stato ricevuto direttamente dal servizio locale.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = error is ZeppException
              ? error.message
              : 'Verifica del canale locale non riuscita.';
        });
      }
    } finally {
      // Reading the direct channel must not invoke status/recovery over ADB.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageZeppPermissions({required bool test}) async {
    setState(() {
      _busy = true;
      _failed = false;
      _status = test
          ? 'Prova sospensione e ripristino, senza inviare file…'
          : 'Ripristino permessi Zepp…';
    });
    try {
      if (test) {
        await widget.client.testZeppPermissions();
      } else {
        await widget.client.restoreZeppPermissions();
      }
      if (mounted) {
        setState(
          () => _status = test
              ? 'Prova riuscita: Dispositivi nelle vicinanze di Zepp sospeso e ripristinato. Nessun file inviato.'
              : 'Permessi Zepp ripristinati allo stato iniziale.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = error is ZeppException
              ? error.message
              : 'Ripristino Zepp non confermato. Riconnetti il debug wireless e riprova.';
        });
      }
    } finally {
      await _refreshCoordination();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _probeParallelBle() async {
    final device = _device;
    if (device == null) {
      setState(() => _status = 'Prima scegli l’orologio dall’elenco.');
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
      _status =
          'Verifica BLE con Zepp collegata: lettura dei servizi, nessun invio…';
    });
    try {
      final characteristics = await widget.client.probeParallelBle(device);
      final available = ['16', '17', '23'].every(
        (part) =>
            characteristics.contains('000000$part-0000-3512-2118-0009af100700'),
      );
      if (mounted) {
        setState(() {
          _status = available
              ? 'Collegamento BLE disponibile e canali necessari presenti. Nessuna autenticazione o musica inviata. Controlla che Zepp sia rimasta collegata: l’invio parallelo non è ancora verificato.'
              : 'Collegamento BLE aperto, ma i canali necessari non sono tutti disponibili. Nessuna autenticazione o musica inviata.';
        });
      }
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

  Future<void> _selectDevice(ZeppDevice? device) async {
    setState(() {
      _device = device;
      _key.clear();
      _hasSavedKey = false;
      _busy = true;
      _status = null;
      _failed = false;
    });
    try {
      final saved = device == null
          ? null
          : await widget.client.savedKey(device);
      if (mounted) {
        setState(() => _hasSavedKey = saved != null && isValidZeppKey(saved));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Impossibile leggere la chiave salvata. Puoi reinserirla.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgetKey() async {
    final device = _device;
    if (device == null) return;
    setState(() => _busy = true);
    try {
      await widget.client.forgetKey(device);
      if (mounted) {
        setState(() {
          _hasSavedKey = false;
          _key.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Impossibile cancellare la chiave salvata. Riprova.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recoverAccountKey() async {
    final device = _device;
    if (_busy || device == null) return;
    setState(() {
      _busy = true;
      _status = null;
      _failed = false;
    });
    try {
      final key = await showZeppAccountRecovery(
        context,
        device: device,
        account: widget.account ?? ZeppAccount(),
      );
      if (!mounted || key == null) return;
      if (!isValidZeppKey(key)) {
        throw const ZeppException('Chiave Zepp non compatibile.');
      }
      final previousKey = await widget.client.savedKey(device);
      if (!mounted) return;
      if (previousKey != null && isValidZeppKey(previousKey)) {
        final normalizedPrevious = previousKey
            .trim()
            .replaceFirst(RegExp(r'^0[xX]'), '')
            .toLowerCase();
        zeppDiagnostic(
          normalizedPrevious == key.toLowerCase()
              ? 'ACCOUNT_KEY_MATCHES_SAVED'
              : 'ACCOUNT_KEY_DIFFERS_SAVED',
        );
      }
      await widget.client.rememberKey(device, key);
      zeppDiagnostic('ACCOUNT_KEY_SAVED');
      if (!mounted) return;
      setState(() {
        _hasSavedKey = true;
        _key.clear();
        _status =
            'Chiave recuperata e salvata per questo orologio. Nessun brano inviato.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = error is ZeppException
              ? error.message
              : 'Impossibile salvare la chiave nell’archivio sicuro. Riprova.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _accountRecoveryButton() => OutlinedButton.icon(
    key: const Key('zepp-account-connect'),
    onPressed: _busy || _device == null ? null : _recoverAccountKey,
    icon: const Icon(Icons.account_circle_outlined),
    label: Text(
      _hasSavedKey ? 'Recupera nuovamente da Zepp' : 'Collega account Zepp',
    ),
  );

  Future<void> _saveDownloadConfiguration() async {
    final device = _device;
    if (device == null) {
      setState(() => _status = 'Scegli il tuo orologio.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final entered = _key.text.trim();
      final key = entered.isEmpty
          ? await widget.client.savedKey(device)
          : entered;
      if (key == null || !isValidZeppKey(key)) {
        throw const ZeppException(
          'Inserisci la chiave di abbinamento Zepp: 32 cifre esadecimali.',
        );
      }
      if (!await widget.client.authorizeCoordination()) {
        throw const ZeppException(
          'Collega il Debug wireless dalla configurazione qui sotto, poi salva.',
        );
      }
      await widget.client.rememberKey(device, key);
      await widget.client.rememberDownloadDevice(device);
      await widget.client.setCoordinationEnabled(true);
      _key.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = error is ZeppException
              ? error.message
              : 'Configurazione non riuscita. Nessun invio avviato.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    zeppDiagnostic('UI_OPEN');
    unawaited(widget.client.secureScreen(true));
    unawaited(_refreshCoordination());
    if (widget.configureOnly) unawaited(_loadDevices());
    _sub = (widget.events ?? widget.client.events).listen((event) {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    zeppDiagnostic('UI_LIFECYCLE_${state.name}');
  }

  @override
  void dispose() {
    zeppDiagnostic('UI_DISPOSE');
    WidgetsBinding.instance.removeObserver(this);
    if (_busy && !widget.configureOnly) unawaited(widget.client.cancel());
    unawaited(widget.client.secureScreen(false));
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
      final devices = await widget.client.devices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _device = null;
        _key.clear();
        _hasSavedKey = false;
        _status = devices.isEmpty
            ? 'Nessun dispositivo abbinato disponibile.'
            : 'Scegli il tuo orologio dall\'elenco.';
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
    final enteredKey = _key.text.trim();
    _key.clear(); // Il valore salvato non viene ripopolato nel campo.
    setState(() {
      _busy = true;
      _failed = false;
      _progress = null;
      _status = 'Avvio...';
    });
    zeppDiagnostic(send ? 'UI_SEND' : 'UI_VERIFY');
    try {
      final key = enteredKey.isNotEmpty
          ? enteredKey
          : await widget.client.savedKey(device);
      if (key == null || !isValidZeppKey(key)) {
        throw const ZeppException('Reinserisci la chiave di abbinamento.');
      }
      if (enteredKey.isNotEmpty) {
        await widget.client.rememberKey(device, key);
        if (mounted) setState(() => _hasSavedKey = true);
      }
      if (send) {
        await widget.client.send(
          device: device,
          key: key,
          path: widget.file.path,
          title: _title.text,
          artist: _artist.text,
          coordinateZepp: _coordinateZepp,
        );
      } else {
        await widget.client.verify(
          device: device,
          key: key,
          coordinateZepp: _coordinateZepp,
        );
      }
      if (!mounted) return;
      setState(() {
        _status = send
            ? 'Ultimo blocco confermato dall\'orologio. Controlla titolo e riproduzione '
                  'nel lettore Musica: da qui non si puo\' verificare. Poi controlla che Zepp funzioni ancora.'
            : 'Autenticazione riuscita e servizio music presente. Nessun brano inviato.';
        if (_coordinateZepp) {
          _status =
              '$_status\nDispositivi nelle vicinanze di Zepp ripristinato allo stato iniziale.';
        }
      });
    } on ZeppException catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status =
              '${error.message}\nNessun reset e nessun nuovo tentativo automatico.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status =
              'Impossibile accedere all’archivio sicuro della chiave. Operazione interrotta.';
        });
      }
    } finally {
      await _refreshCoordination();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _licenses() async {
    final text = await widget.client.licenses();
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
    title: Text(
      widget.configureOnly
          ? 'Configura invio all’orologio'
          : 'Invia all\'orologio',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: widget.configureOnly ? _downloadSetupBody() : _body(context),
      ),
    ),
    actions: [
      if (widget.configureOnly)
        FilledButton(
          onPressed: _busy ? null : _saveDownloadConfiguration,
          child: const Text('Salva e continua'),
        )
      else
        TextButton(onPressed: _licenses, child: const Text('Licenze')),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Chiudi'),
      ),
    ],
  );

  Widget _downloadSetupBody() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Configura una volta l’orologio. Per inviare un brano premi Invia all’orologio dopo il download. '
        'SyncBeat sospende temporaneamente Dispositivi nelle vicinanze di Zepp durante l’invio '
        'e ripristina lo stato iniziale alla fine. Tieni l’app aperta fino al completamento.',
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<ZeppDevice>(
        key: ValueKey(_devices.length),
        initialValue: _device,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Orologio abbinato'),
        items: [
          for (final device in _devices)
            DropdownMenuItem(value: device, child: Text(device.label)),
        ],
        onChanged: _busy ? null : _selectDevice,
      ),
      const SizedBox(height: 12),
      _accountRecoveryButton(),
      const SizedBox(height: 8),
      TextField(
        controller: _key,
        enabled: !_busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: 'Chiave Zepp',
          helperText: _hasSavedKey
              ? 'Chiave già salvata: lascia vuoto per usarla.'
              : '32 cifre esadecimali; conservata nell’archivio sicuro.',
        ),
      ),
      TextButton(
        onPressed: _busy ? null : () => showEmbeddedAdbSetup(context),
        child: const Text('Configura Debug wireless'),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_status != null) Text(_status!),
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
              'Funzione sperimentale: il trasferimento deve ancora essere verificato sul tuo orologio. '
              'Invia un MP3 al lettore Musica originale via Bluetooth Classic. '
              'Serve la chiave di abbinamento Zepp (32 cifre esadecimali): '
              'viene conservata nell’archivio sicuro del telefono per questo orologio, '
              'senza mostrarla o inviarla online. Puoi cancellarla quando vuoi.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _coordinateZepp,
          onChanged: _busy ? null : _setCoordination,
          title: const Text('Gestisci automaticamente Zepp'),
          subtitle: const Text(
            'Con il debug wireless integrato, sospende Dispositivi nelle vicinanze di Zepp durante verifica e invio e ripristina lo stato iniziale anche in caso di errore.',
          ),
        ),
        if (_coordinateZepp && _coordinationState != 'ready')
          const Text(
            'Il debug wireless non è collegato. Configuralo prima di procedere.',
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await showEmbeddedAdbSetup(context);
                  await _refreshCoordination();
                },
          child: const Text('Configura debug wireless (senza app aggiuntive)'),
        ),
        if (_coordinateZepp || _restorePending) ...[
          Text(switch (_leaseState) {
            'active' => 'Diagnostica sospensione: attiva',
            'idle' => 'Diagnostica sospensione: inattiva',
            'unknown' => 'Diagnostica sospensione: stato non verificabile',
            _ => 'Diagnostica sospensione: servizio non collegato',
          }),
          OutlinedButton(
            onPressed: _busy || _coordinationState != 'ready'
                ? null
                : _prepareZeppHelper,
            child: const Text('Prepara servizio ADB (senza sospensione)'),
          ),
          TextButton(
            onPressed: _busy ? null : _refreshCoordination,
            child: const Text('Aggiorna stato diagnostico'),
          ),
          if (_restorePending)
            const Text(
              'Ripristino Zepp da verificare: premi Ripristina permessi Zepp.',
            ),
          OutlinedButton(
            onPressed: _busy ? null : () => _manageZeppPermissions(test: false),
            child: const Text('Ripristina permessi Zepp'),
          ),
          OutlinedButton(
            onPressed: _busy || _coordinationState != 'ready'
                ? null
                : () => _manageZeppPermissions(test: true),
            child: const Text('Prova sospensione e ripristino (senza file)'),
          ),
        ],
        const Text(
          'Per preparare l’invio senza Wi-Fi servono Wi-Fi e Debug wireless autorizzato. '
          'Se app o servizio vengono terminati, va preparato di nuovo con Wi-Fi.',
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _checkOfflineHelper(prepare: true),
          child: const Text('Prepara invio senza Wi-Fi'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _checkOfflineHelper(prepare: false),
          child: const Text('Verifica canale locale (solo stato)'),
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
            onChanged: _busy ? null : _selectDevice,
          ),
        ],
        const SizedBox(height: 12),
        _accountRecoveryButton(),
        TextFormField(
          key: const Key('zepp-key'),
          controller: _key,
          enabled: !_busy,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: '2. Chiave (32 cifre esadecimali)',
            hintText: _hasSavedKey
                ? 'Chiave salvata: lascia vuoto per usarla'
                : null,
          ),
          validator: (v) =>
              ((v ?? '').trim().isEmpty && _hasSavedKey) ||
                  isValidZeppKey(v ?? '')
              ? null
              : 'Servono 32 cifre esadecimali (0-9, a-f)',
        ),
        if (_hasSavedKey) ...[
          const Text(
            'Chiave salvata per questo orologio. Verrà usata automaticamente.',
          ),
          TextButton(
            onPressed: _busy ? null : _forgetKey,
            child: const Text('Dimentica chiave salvata'),
          ),
        ],
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
              key: const Key('zepp-probe-parallel'),
              onPressed: _busy ? null : _probeParallelBle,
              child: const Text('Verifica connessione parallela (senza invio)'),
            ),
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
                onPressed: () => widget.client.cancel(),
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
