import 'package:flutter/material.dart';

import 'zepp_account.dart';
import 'zepp_client.dart';

/// Open only inside the secure watch configuration screen. Credentials stay in
/// this dialog and are cleared after each explicit attempt and on disposal.
Future<String?> showZeppAccountRecovery(
  BuildContext context, {
  required ZeppDevice device,
  required ZeppAccount account,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ZeppAccountDialog(device: device, account: account),
);

class ZeppAccountDialog extends StatefulWidget {
  const ZeppAccountDialog({
    super.key,
    required this.device,
    required this.account,
  });
  final ZeppDevice device;
  final ZeppAccount account;

  @override
  State<ZeppAccountDialog> createState() => _ZeppAccountDialogState();
}

class _ZeppAccountDialogState extends State<ZeppAccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.clear();
    _password.clear();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(
        () => _error = 'Inserisci email e password del tuo account Zepp.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final pending = widget.account.recoverKey(
        email: _email.text.trim(),
        password: _password.text,
        device: widget.device,
      );
      _email.clear();
      _password.clear();
      final key = await pending;
      if (mounted) Navigator.pop(context, key);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ZeppException
              ? error.message
              : 'Recupero non riuscito. Nessuna chiave modificata.',
        );
      }
    } finally {
      _email.clear();
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Collega account Zepp'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recupera la chiave per ${widget.device.label} e salvala su questo telefono. '
                'Email e password vengono inviate solo ai server Zepp e non vengono salvate.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Recupero sperimentale. Usa email e password Zepp; '
                'l’accesso diretto con Google o Apple non è supportato. '
                'Dopo il recupero controlla che Zepp sia ancora collegata.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('zepp-account-email'),
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Email Zepp'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('zepp-account-password'),
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Password Zepp'),
                onSubmitted: _busy ? null : (_) => _recover(),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const Text('Recupero della chiave in corso…'),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _busy ? null : _recover,
          child: const Text('Recupera chiave'),
        ),
      ],
    ),
  );
}
