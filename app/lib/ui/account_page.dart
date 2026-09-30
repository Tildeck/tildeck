import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:tildeck_api/api.dart' as api;

import '../l10n/app_localizations.dart';
import '../server_check.dart';
import '../sync/account_service.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_server.dart';
import '../theme.dart';
import '../vault/vault.dart';

/// Everything the sync screens need.
class SyncServices {
  const SyncServices({required this.vault, required this.engine, required this.accounts, required this.checker});

  final Vault vault;
  final SyncEngine engine;
  final AccountService accounts;
  final ServerChecker checker;
}

/// The localized message for a failed account request.
String accountErrorText(AppLocalizations t, Object error) => switch (error) {
  WrongMasterPassword() => t.errorWrongMasterPassword,
  DifferentVault() => t.errorDifferentVault,
  ServerFailed(:final problem) => switch (problem) {
    ServerProblem.invalidAddress => t.errorInvalidAddress,
    ServerProblem.unreachable => t.errorUnreachable,
    ServerProblem.notTildeck => t.errorNotTildeck,
    ServerProblem.unsupportedProtocol => t.errorUnsupportedProtocol,
    ServerProblem.databaseUnavailable => t.errorDatabaseUnavailable,
  },
  SyncFailure(unreachable: true, code: null) => t.errorUnreachable,
  SyncFailure(:final code) => switch (code) {
    'invalid_credentials' => t.errorInvalidCredentials,
    'email_taken' => t.errorEmailTaken,
    'registration_closed' => t.errorRegistrationClosed,
    'registration_invite_required' => t.errorRegistrationInvite,
    'registration_needs_email' => t.errorRegistrationNeedsEmail,
    'invalid_email' => t.errorInvalidEmail,
    'rate_limited' => t.errorRateLimited,
    'account_disabled' => t.errorAccountDisabled,
    'device_revoked' => t.errorDeviceRevoked,
    'unsupported_protocol' => t.errorUnsupportedProtocol,
    _ => t.errorSyncFailed,
  },
  _ => t.errorSyncFailed,
};

/// The sync screen: sign in or create an account; once signed in, the sync
/// status and the account's devices.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.services});

  final SyncServices services;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  String? _recoveryKey;
  PendingDevice? _pending;

  @override
  void dispose() {
    _pending?.abandon();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final s = widget.services;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.desk,
        foregroundColor: c.deskInk,
        title: Text(t.syncTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([s.vault, s.engine]),
          builder: (context, _) {
            final Widget content;
            if (_recoveryKey != null) {
              content = RecoveryKeyView(recoveryKey: _recoveryKey!, onDone: () => setState(() => _recoveryKey = null));
            } else if (_pending != null) {
              content = PendingDeviceView(
                pending: _pending!,
                deviceName: _pending!.deviceName,
                onDone: () {
                  setState(() => _pending = null);
                  // Approved: sync now rather than at the next interval.
                  if (s.vault.account != null) s.engine.sync();
                },
              );
            } else if (s.vault.account == null) {
              content = AccountForm(
                services: s,
                allowRegister: true,
                onRegistered: (key) => setState(() => _recoveryKey = key),
                onPending: (p) => setState(() => _pending = p),
              );
            } else {
              content = _SignedInView(services: s, onPending: (p) => setState(() => _pending = p));
            }
            return _Page(child: content);
          },
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 32, 24, 32), child: child),
    ),
  );
}

/// The sign-in or registration form. With no vault on the device yet, only
/// sign-in is offered: the vault comes from the account.
class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    required this.services,
    required this.allowRegister,
    this.onRegistered,
    required this.onPending,
    this.onSignedIn,
  });

  final SyncServices services;
  final bool allowRegister;
  final ValueChanged<String>? onRegistered;
  final ValueChanged<PendingDevice> onPending;
  final VoidCallback? onSignedIn;

  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: AccountService.defaultDeviceName());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _email.dispose();
    _password.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool register}) async {
    if (_busy || !_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = widget.services;
    // Read everything now: signing in switches the page away from this
    // form, which may be gone by the time the server answers.
    final input = _address.text;
    final email = _email.text.trim();
    final password = _password.text;
    final deviceName = _deviceName.text.trim();
    final onRegistered = widget.onRegistered, onPending = widget.onPending, onSignedIn = widget.onSignedIn;
    try {
      final check = await s.checker.check(input);
      if (check is ServerFailed) throw check;
      final address = ServerChecker.parseAddress(input).toString();
      if (register) {
        final key = await s.accounts.register(
          address: address,
          email: email,
          password: password,
          locale: locale == 'he' ? 'he' : 'en',
          deviceName: deviceName,
        );
        if (mounted) _password.clear();
        onRegistered?.call(key);
        s.engine.sync();
      } else {
        final pending = await s.accounts.signIn(
          address: address,
          email: email,
          password: password,
          deviceName: deviceName,
        );
        if (mounted) _password.clear();
        if (pending != null) {
          onPending(pending);
        } else {
          onSignedIn?.call();
          s.engine.sync();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorText(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    String? required(String? v) => (v ?? '').trim().isEmpty ? t.fieldRequired : null;

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.allowRegister ? t.connectTitle : t.signInTitle,
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 10),
          Text(
            widget.allowRegister ? t.syncIntro : t.signInIntro,
            style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5),
          ),
          const SizedBox(height: 28),
          // Addresses and email are Latin content end to end: always LTR,
          // even in a Hebrew interface.
          TextFormField(
            key: const ValueKey('syncAddress'),
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
            key: const ValueKey('syncEmail'),
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
            key: const ValueKey('syncPassword'),
            controller: _password,
            obscureText: true,
            textDirection: TextDirection.ltr,
            enabled: !_busy,
            validator: required,
            onFieldSubmitted: (_) => _submit(register: false),
            decoration: InputDecoration(labelText: t.masterPasswordLabel, helperText: t.masterPasswordProof),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const ValueKey('syncDeviceName'),
            controller: _deviceName,
            enabled: !_busy,
            maxLength: 100,
            validator: required,
            decoration: InputDecoration(labelText: t.deviceNameLabel),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              key: const ValueKey('syncError'),
              style: TextStyle(color: c.danger, height: 1.4),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                key: const ValueKey('syncSignIn'),
                onPressed: _busy ? null : () => _submit(register: false),
                child: Text(_busy ? t.working : t.signInButton),
              ),
              if (widget.allowRegister)
                OutlinedButton(
                  key: const ValueKey('syncRegister'),
                  onPressed: _busy ? null : () => _submit(register: true),
                  child: Text(t.createAccountButton),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows the recovery key once, and continues only after the user says it
/// is saved.
class RecoveryKeyView extends StatefulWidget {
  const RecoveryKeyView({super.key, required this.recoveryKey, required this.onDone});

  final String recoveryKey;
  final VoidCallback onDone;

  @override
  State<RecoveryKeyView> createState() => _RecoveryKeyViewState();
}

class _RecoveryKeyViewState extends State<RecoveryKeyView> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.recoveryTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 10),
        Text(t.recoveryIntro, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
          ),
          child: SelectableText(
            widget.recoveryKey,
            key: const ValueKey('recoveryKey'),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 18, height: 1.6, letterSpacing: 0.5),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(t.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.recoveryKey));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.copied)));
            },
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('recoverySaved'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _saved,
          onChanged: (v) => setState(() => _saved = v ?? false),
          title: Text(t.recoverySaved),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('recoveryContinue'),
          onPressed: _saved ? widget.onDone : null,
          child: Text(t.continueButton),
        ),
      ],
    );
  }
}

/// A new device waiting for approval: asks the server every few seconds
/// and continues by itself once approved.
class PendingDeviceView extends StatefulWidget {
  const PendingDeviceView({
    super.key,
    required this.pending,
    required this.deviceName,
    required this.onDone,
    this.pollEvery = const Duration(seconds: 5),
  });

  final PendingDevice pending;
  final String deviceName;

  /// Called once approved, or when the wait is cancelled.
  final VoidCallback onDone;
  final Duration pollEvery;

  @override
  State<PendingDeviceView> createState() => _PendingDeviceViewState();
}

class _PendingDeviceViewState extends State<PendingDeviceView> {
  Timer? _timer;
  bool _asking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollEvery, (_) => _ask());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_asking) return;
    _asking = true;
    final t = AppLocalizations.of(context);
    try {
      if (await widget.pending.collect()) {
        _timer?.cancel();
        widget.onDone();
      } else if (_error != null && mounted) {
        setState(() => _error = null);
      }
    } on SyncFailure catch (e) {
      // No answer: keep asking. A refusal ends the wait.
      if (!e.unreachable) _timer?.cancel();
      if (mounted) setState(() => _error = accountErrorText(t, e));
    } catch (e) {
      _timer?.cancel();
      if (mounted) setState(() => _error = accountErrorText(t, e));
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final pending = widget.pending.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.pendingTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 10),
        Text(
          pending.emailApproval ? t.pendingBodyEmail(widget.deviceName) : t.pendingBody(widget.deviceName),
          style: text.bodyLarge?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t.pendingWaiting, style: text.bodyMedium?.copyWith(color: c.muted)),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: c.danger, height: 1.4)),
        ],
        const SizedBox(height: 24),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            onPressed: () {
              _timer?.cancel();
              widget.pending.abandon();
              widget.onDone();
            },
            child: Text(t.cancel),
          ),
        ),
      ],
    );
  }
}

class _SignedInView extends StatefulWidget {
  const _SignedInView({required this.services, required this.onPending});

  final SyncServices services;
  final ValueChanged<PendingDevice> onPending;

  @override
  State<_SignedInView> createState() => _SignedInViewState();
}

class _SignedInViewState extends State<_SignedInView> {
  List<api.DeviceView>? _devices;
  bool _sent = false;

  SyncServices get s => widget.services;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final account = s.vault.account;
    if (account == null) return;
    try {
      final view = await s.engine.serverFor(account.server).account(account.token);
      final devices = view.devices.where((d) => d.status != api.DeviceViewStatusEnum.revoked).toList();
      if (mounted) setState(() => _devices = devices);
    } on SyncFailure {
      // The reason shows in the sync status; the list returns with the
      // next successful load.
      if (mounted) setState(() => _devices ??= const []);
    }
  }

  Future<void> _deviceAction(Future<void> Function(SyncServer, String) action) async {
    final account = s.vault.account;
    if (account == null) return;
    try {
      await action(s.engine.serverFor(account.server), account.token);
    } on SyncFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(accountErrorText(AppLocalizations.of(context), e))));
      }
    }
    await _loadDevices();
  }

  Future<void> _remove(api.DeviceView device) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.removeDeviceTitle(device.name)),
        content: Text(t.removeDeviceBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.removeDevice)),
        ],
      ),
    );
    if (ok == true) await _deviceAction((server, token) => server.revoke(token, device.id));
  }

  /// A device whose token expired signs in again with its own id and needs
  /// no approval; a removed one waits for approval as a new device.
  Future<void> _signInAgain() async {
    final t = AppLocalizations.of(context);
    final account = s.vault.account!;
    final typed = await showDialog<String>(context: context, builder: (_) => const _PasswordDialog());
    if (typed == null || typed.isEmpty) return;
    try {
      final pending = await s.accounts.signIn(
        address: account.server,
        email: account.email,
        password: typed,
        deviceName: account.deviceName,
      );
      if (pending != null) {
        widget.onPending(pending);
      } else {
        await s.engine.sync();
        await _loadDevices();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(accountErrorText(t, e))));
      }
    }
  }

  Future<void> _signOut() async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.signOutOfSync),
        content: Text(t.signOutBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.signOutOfSync)),
        ],
      ),
    );
    if (ok == true) await s.accounts.signOut();
  }

  String _time(BuildContext context, DateTime time) =>
      DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_Hm().format(time.toLocal());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final account = s.vault.account!;
    final engine = s.engine;

    final (String status, Color dot) = switch (engine.problem) {
      _ when engine.running => (t.syncing, c.muted),
      null => (
        engine.lastSynced == null ? t.notSyncedYet : t.lastSynced(_time(context, engine.lastSynced!)),
        c.success,
      ),
      SyncProblem.emailNotConfirmed => (t.problemEmailNotConfirmed(account.email), c.danger),
      SyncProblem.signedOut => (t.problemSignedOut, c.danger),
      SyncProblem.unreachable => (t.problemUnreachable, c.danger),
      SyncProblem.unsupportedProtocol => (t.errorUnsupportedProtocol, c.danger),
      SyncProblem.failed => (t.errorSyncFailed, c.danger),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.signedInAs(account.email),
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
        ),
        const SizedBox(height: 4),
        Text(t.onServer(account.server), style: text.bodyMedium?.copyWith(color: c.muted)),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: engine.problem == null ? c.line : c.danger),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status,
                      key: const ValueKey('syncStatus'),
                      style: text.titleMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('syncNow'),
                    onPressed: engine.running ? null : () => engine.sync().then((_) => _loadDevices()),
                    child: Text(t.syncNow),
                  ),
                  if (engine.problem == SyncProblem.signedOut)
                    OutlinedButton(
                      key: const ValueKey('signInAgain'),
                      onPressed: _signInAgain,
                      child: Text(t.signInButton),
                    ),
                  if (engine.problem == SyncProblem.emailNotConfirmed)
                    OutlinedButton(
                      onPressed: _sent
                          ? null
                          : () async {
                              await _deviceAction((server, token) => server.resendVerification(token));
                              if (mounted) setState(() => _sent = true);
                            },
                      child: Text(_sent ? t.emailSent : t.resendEmail),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(t.devicesTitle, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_devices == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final device in _devices!) _deviceTile(context, device),
        const SizedBox(height: 28),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: const ValueKey('signOutOfSync'),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            onPressed: _signOut,
            child: Text(t.signOutOfSync),
          ),
        ),
      ],
    );
  }

  Widget _deviceTile(BuildContext context, api.DeviceView device) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final pending = device.status == api.DeviceViewStatusEnum.pending;
    final subtitle = device.current
        ? t.thisDevice
        : pending
        ? t.devicePending
        : device.lastSeenAt == null
        ? null
        : t.deviceLastSeen(_time(context, device.lastSeenAt!));

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pending ? c.brand : c.line),
      ),
      child: Row(
        children: [
          Icon(device.current ? Icons.computer_rounded : Icons.devices_other_rounded, color: c.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(color: pending ? c.brand : c.muted, fontSize: 13)),
              ],
            ),
          ),
          if (pending)
            FilledButton(
              key: ValueKey('approve-${device.id}'),
              onPressed: () => _deviceAction((server, token) => server.approve(token, device.id)),
              child: Text(t.approveDevice),
            ),
          if (!device.current) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: () => _remove(device), child: Text(t.removeDevice)),
          ],
        ],
      ),
    );
  }
}

/// Asks for the master password; the dialog owns its field, so the field
/// outlives the closing animation.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.signInButton),
      content: TextField(
        key: const ValueKey('signInAgainPassword'),
        controller: _password,
        obscureText: true,
        autofocus: true,
        textDirection: TextDirection.ltr,
        onSubmitted: (_) => Navigator.pop(context, _password.text),
        decoration: InputDecoration(labelText: t.masterPasswordLabel, helperText: t.masterPasswordProof),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _password.text), child: Text(t.signInButton)),
      ],
    );
  }
}
