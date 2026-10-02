import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../server_check.dart';
import '../sync/account_service.dart';
import '../theme.dart';
import '../vault/password_rules.dart';
import '../vault/vault.dart';
import 'account_page.dart';

/// The frame of the password screens: a title, an intro, and a form.
class _PasswordScreen extends StatelessWidget {
  const _PasswordScreen({required this.title, required this.intro, required this.children});

  final String title;
  final String intro;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(backgroundColor: c.desk, foregroundColor: c.deskInk),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 10),
                  Text(intro, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A new master password and its confirmation, with the vault's rules.
class _NewPasswordFields extends StatelessWidget {
  const _NewPasswordFields({
    required this.password,
    required this.confirm,
    required this.common,
    required this.enabled,
  });

  final TextEditingController password;
  final TextEditingController confirm;
  final CommonPasswords common;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        TextFormField(
          key: const ValueKey('newPassword'),
          controller: password,
          obscureText: true,
          textDirection: TextDirection.ltr,
          enabled: enabled,
          decoration: InputDecoration(labelText: t.newPasswordLabel, helperText: t.pwTooShort),
          validator: (v) => switch (checkMasterPassword(v ?? '', common)) {
            PasswordProblem.tooShort => t.pwTooShort,
            PasswordProblem.common => t.pwCommon,
            null => null,
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          key: const ValueKey('newPasswordConfirm'),
          controller: confirm,
          obscureText: true,
          textDirection: TextDirection.ltr,
          enabled: enabled,
          decoration: InputDecoration(labelText: t.confirmPasswordLabel),
          validator: (v) => v == password.text ? null : t.pwMismatch,
        ),
      ],
    );
  }
}

Widget _errorLine(BuildContext context, String? message) => message == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(
          message,
          key: const ValueKey('passwordError'),
          style: TextStyle(color: context.colors.danger, height: 1.4),
        ),
      );

/// Changes the master password. The vault and its records stay as they
/// are; only the password that opens the vault changes.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.services});

  final SyncServices services;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _signOutOthers = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.accounts.changePassword(
        current: _current.text,
        newPassword: _password.text,
        signOutOtherDevices: _signOutOthers,
      );
      messenger.showSnackBar(SnackBar(content: Text(t.passwordChanged)));
      navigator.maybePop();
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorText(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final signedIn = widget.services.vault.account != null;
    return _PasswordScreen(
      title: t.changePasswordTitle,
      intro: t.changePasswordIntro,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('currentPassword'),
                controller: _current,
                obscureText: true,
                autofocus: true,
                textDirection: TextDirection.ltr,
                enabled: !_busy,
                decoration: InputDecoration(labelText: t.currentPasswordLabel),
                validator: (v) => (v ?? '').isEmpty ? t.fieldRequired : null,
              ),
              const SizedBox(height: 14),
              _NewPasswordFields(
                password: _password,
                confirm: _confirm,
                common: widget.services.commonPasswords,
                enabled: !_busy,
              ),
              if (signedIn) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const ValueKey('signOutOthers'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _signOutOthers,
                  onChanged: _busy ? null : (v) => setState(() => _signOutOthers = v ?? true),
                  title: Text(t.signOutOthers),
                  subtitle: Text(t.signOutOthersHelp),
                ),
              ],
            ],
          ),
        ),
        _errorLine(context, _error),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('changePassword'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? t.working : t.changePasswordButton),
        ),
      ],
    );
  }
}

/// Sets a new master password with the recovery key. Opened from the
/// unlock screen or from sign-in; closes itself once the vault is open.
class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key, required this.services});

  final SyncServices services;

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _deviceName = TextEditingController(text: AccountService.defaultDeviceName());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_address, _email, _key, _password, _confirm, _deviceName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = widget.services;
      final check = await s.checker.check(_address.text);
      if (check is ServerFailed) throw check;
      await s.accounts.recover(
        address: ServerChecker.parseAddress(_address.text).toString(),
        email: _email.text.trim(),
        recoveryKey: _key.text,
        newPassword: _password.text,
        deviceName: _deviceName.text.trim(),
      );
      s.engine.sync();
      if (s.vault.status == VaultStatus.unlocked) navigator.maybePop();
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorText(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    String? required(String? v) => (v ?? '').trim().isEmpty ? t.fieldRequired : null;
    return _PasswordScreen(
      title: t.recoverTitle,
      intro: t.recoverIntro,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('recoverAddress'),
                controller: _address,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enabled: !_busy,
                validator: required,
                decoration: InputDecoration(labelText: t.serverAddressLabel, hintText: t.serverAddressHint),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('recoverEmail'),
                controller: _email,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enabled: !_busy,
                validator: required,
                decoration: InputDecoration(labelText: t.emailLabel),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('recoverKey'),
                controller: _key,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enabled: !_busy,
                minLines: 2,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
                validator: required,
                decoration: InputDecoration(labelText: t.recoveryKeyLabel),
              ),
              const SizedBox(height: 14),
              _NewPasswordFields(
                password: _password,
                confirm: _confirm,
                common: widget.services.commonPasswords,
                enabled: !_busy,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('recoverDeviceName'),
                controller: _deviceName,
                enabled: !_busy,
                maxLength: 100,
                validator: required,
                decoration: InputDecoration(labelText: t.deviceNameLabel),
              ),
            ],
          ),
        ),
        _errorLine(context, _error),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('recover'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? t.working : t.recoverButton),
        ),
      ],
    );
  }
}
