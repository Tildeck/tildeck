import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';

enum _Auth { password, privateKey }

/// Where to connect and how to sign in. Hosts, usernames, and keys are Latin
/// content end to end, so those fields stay LTR in a Hebrew interface.
class ConnectForm extends StatefulWidget {
  const ConnectForm({super.key, required this.onConnect});

  final void Function(ConnectionTarget target) onConnect;

  @override
  State<ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends State<ConnectForm> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  _Auth _auth = _Auth.password;

  @override
  void dispose() {
    for (final c in [_host, _port, _username, _password, _privateKey, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    widget.onConnect(
      ConnectionTarget(
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: _username.text.trim(),
        password: _auth == _Auth.password ? _password.text : null,
        privateKey: _auth == _Auth.privateKey ? _privateKey.text : null,
        passphrase: _auth == _Auth.privateKey ? _passphrase.text : null,
      ),
    );
    // Credentials do not linger in the form once handed over.
    _password.clear();
    _passphrase.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    String? required(String? v) => (v == null || v.trim().isEmpty) ? t.fieldRequired : null;
    const mono = TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            children: [
              Text(t.newConnection, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(t.newConnectionIntro, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('host'),
                      controller: _host,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: required,
                      decoration: InputDecoration(labelText: t.hostLabel, hintText: t.hostHint),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      key: const ValueKey('port'),
                      controller: _port,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final port = int.tryParse(v?.trim() ?? '');
                        return port == null || port < 1 || port > 65535 ? t.portInvalid : null;
                      },
                      decoration: InputDecoration(labelText: t.portLabel),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('username'),
                controller: _username,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                validator: required,
                decoration: InputDecoration(labelText: t.usernameLabel),
              ),
              const SizedBox(height: 18),
              SegmentedButton<_Auth>(
                segments: [
                  ButtonSegment(value: _Auth.password, label: Text(t.authPassword), icon: const Icon(Icons.password)),
                  ButtonSegment(value: _Auth.privateKey, label: Text(t.authPrivateKey), icon: const Icon(Icons.key)),
                ],
                selected: {_auth},
                onSelectionChanged: (s) => setState(() => _auth = s.first),
              ),
              const SizedBox(height: 14),
              if (_auth == _Auth.password)
                TextFormField(
                  key: const ValueKey('password'),
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  validator: required,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(labelText: t.passwordLabel),
                )
              else ...[
                TextFormField(
                  key: const ValueKey('privateKey'),
                  controller: _privateKey,
                  textDirection: TextDirection.ltr,
                  style: mono,
                  minLines: 4,
                  maxLines: 8,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: required,
                  decoration: InputDecoration(
                    labelText: t.privateKeyLabel,
                    hintText: t.privateKeyHint,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('passphrase'),
                  controller: _passphrase,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t.passphraseLabel),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(key: const ValueKey('connect'), onPressed: _submit, child: Text(t.connectButton)),
            ],
          ),
        ),
      ),
    );
  }
}
