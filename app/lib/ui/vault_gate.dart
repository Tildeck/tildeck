import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../activity.dart';
import '../l10n/app_localizations.dart';
import '../logo.dart';
import '../platform/biometric.dart';
import '../settings/device_settings.dart';
import '../sync/account_service.dart';
import '../theme.dart';
import '../vault/biometric_unlock.dart';
import '../vault/password_rules.dart';
import '../vault/vault.dart';
import 'account_page.dart';
import 'password_pages.dart';

/// Shows the vault's creation or unlock screen until it is open, then
/// [unlocked]. Once built, [unlocked] stays alive (offstage) while the vault
/// is locked again, so open sessions survive a lock; it is never shown or
/// focusable while locked.
class VaultGate extends StatefulWidget {
  const VaultGate({
    super.key,
    required this.vault,
    required this.commonPasswords,
    required this.unlocked,
    this.sync,
    this.autoLock,
    this.settings,
    this.biometrics,
  });

  final Vault vault;
  final CommonPasswords commonPasswords;
  final WidgetBuilder unlocked;

  /// Offers signing in to an existing sync account instead of creating a
  /// vault. Null hides it.
  final SyncServices? sync;

  /// Biometric unlock on this device; null offers only the master password.
  final BiometricUnlock? biometrics;

  /// Locks the vault after this long without a key press, a touch, or
  /// typing into a terminal ([userActivity]). Null takes the time from the
  /// vault's preferences.
  final Duration? autoLock;

  /// This device's settings: when to lock after the app goes to the
  /// background. Null never locks for that.
  final DeviceSettingsStore? settings;

  @override
  State<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends State<VaultGate> with WidgetsBindingObserver {
  Widget? _content;
  Timer? _idle;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    widget.vault.addListener(_changed);
    HardwareKeyboard.instance.addHandler(_onKey);
    userActivity.addListener(_touch);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Timers do not run while the app is in the background, so the time
  /// away is measured when it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final after = widget.settings?.value.backgroundLock.after;
    final open = widget.vault.status == VaultStatus.unlocked;
    switch (state) {
      case AppLifecycleState.paused:
        _hiddenAt ??= DateTime.now();
        if (open && after == Duration.zero) widget.vault.lock();
      case AppLifecycleState.resumed:
        final hiddenAt = _hiddenAt;
        _hiddenAt = null;
        if (open && after != null && hiddenAt != null && DateTime.now().difference(hiddenAt) >= after) {
          widget.vault.lock();
        }
      default:
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.vault.removeListener(_changed);
    HardwareKeyboard.instance.removeHandler(_onKey);
    userActivity.removeListener(_touch);
    _idle?.cancel();
    super.dispose();
  }

  void _changed() {
    final status = widget.vault.status;
    if (status == VaultStatus.unlocked) {
      _touch();
    } else if (status == VaultStatus.locked) {
      _idle?.cancel();
      // Screens and dialogs opened from the vault (an editor with a typed
      // password, the keys list, a password prompt) sit on the app's
      // navigator above this gate; they must not survive the lock.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
    setState(() {});
  }

  bool _onKey(KeyEvent _) {
    _touch();
    return false;
  }

  void _touch() {
    _idle?.cancel();
    if (widget.vault.status != VaultStatus.unlocked) return;
    _idle = Timer(widget.autoLock ?? widget.vault.preferences.autoLock, widget.vault.lock);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.vault.status;
    if (status == VaultStatus.unlocked) _content ??= Builder(builder: widget.unlocked);
    final locked = status != VaultStatus.unlocked;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      child: Stack(
        children: [
          if (_content != null)
            Offstage(
              offstage: locked,
              child: ExcludeFocus(
                excluding: locked,
                child: TickerMode(enabled: !locked, child: _content!),
              ),
            ),
          if (locked)
            switch (status) {
              VaultStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
              VaultStatus.missing => CreateVaultPage(
                vault: widget.vault,
                commonPasswords: widget.commonPasswords,
                sync: widget.sync,
              ),
              _ => UnlockPage(vault: widget.vault, sync: widget.sync, biometrics: widget.biometrics),
            },
        ],
      ),
    );
  }
}

/// The shared frame of the create and unlock screens.
class _VaultScreen extends StatelessWidget {
  const _VaultScreen({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(28),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TildeckLogo(tile: c.brand, stroke: c.brandContrast, size: 48),
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CreateVaultPage extends StatefulWidget {
  const CreateVaultPage({super.key, required this.vault, required this.commonPasswords, this.sync});

  final Vault vault;
  final CommonPasswords commonPasswords;
  final SyncServices? sync;

  @override
  State<CreateVaultPage> createState() => _CreateVaultPageState();
}

class _CreateVaultPageState extends State<CreateVaultPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final password = _password.text;
    _password.clear();
    _confirm.clear();
    await widget.vault.create(password);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return _VaultScreen(
      children: [
        Text(t.createVaultTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(t.createVaultIntro, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.danger.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: c.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t.noResetWarning, style: TextStyle(color: c.ink, height: 1.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                key: const ValueKey('masterPassword'),
                controller: _password,
                obscureText: true,
                autofocus: true,
                textDirection: TextDirection.ltr,
                enabled: !_busy,
                decoration: InputDecoration(labelText: t.masterPasswordLabel, helperText: t.pwTooShort),
                validator: (v) => switch (checkMasterPassword(v ?? '', widget.commonPasswords)) {
                  PasswordProblem.tooShort => t.pwTooShort,
                  PasswordProblem.common => t.pwCommon,
                  null => null,
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const ValueKey('confirmPassword'),
                controller: _confirm,
                obscureText: true,
                textDirection: TextDirection.ltr,
                enabled: !_busy,
                onFieldSubmitted: (_) => _create(),
                decoration: InputDecoration(labelText: t.confirmPasswordLabel),
                validator: (v) => v == _password.text ? null : t.pwMismatch,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('createVault'),
          onPressed: _busy ? null : _create,
          child: Text(_busy ? t.working : t.createVaultButton),
        ),
        if (widget.sync != null) ...[
          const SizedBox(height: 10),
          TextButton(
            key: const ValueKey('haveAccount'),
            onPressed: _busy
                ? null
                : () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => SignInPage(services: widget.sync!))),
            child: Text(t.haveAccount),
          ),
        ],
      ],
    );
  }
}

/// Signs in to an existing sync account on a device with no vault yet: the
/// vault comes from the account. Closes itself once the vault is open.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.services});

  final SyncServices services;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  PendingDevice? _pending;

  @override
  void dispose() {
    _pending?.abandon();
    super.dispose();
  }

  void _opened() {
    if (mounted && widget.services.vault.status == VaultStatus.unlocked) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(backgroundColor: c.desk, foregroundColor: c.deskInk),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: _pending == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AccountForm(
                          services: widget.services,
                          allowRegister: false,
                          onPending: (p) => setState(() => _pending = p),
                          onSignedIn: _opened,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const ValueKey('signInForgot'),
                            onPressed: () => Navigator.of(
                              context,
                            ).push(MaterialPageRoute<void>(builder: (_) => RecoveryPage(services: widget.services))),
                            child: Text(AppLocalizations.of(context).forgotPassword),
                          ),
                        ),
                      ],
                    )
                  : PendingDeviceView(
                      pending: _pending!,
                      deviceName: _pending!.deviceName,
                      onDone: () {
                        setState(() => _pending = null);
                        _opened();
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.vault, this.sync, this.biometrics});

  final Vault vault;

  /// Unlocking with a fingerprint, a face, or Windows Hello, when this
  /// device has it turned on. Null offers only the master password.
  final BiometricUnlock? biometrics;

  /// Offers recovery with the recovery key. Null hides it.
  final SyncServices? sync;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _wrong = false;
  bool _biometric = false;
  String? _biometricProblem;

  @override
  void initState() {
    super.initState();
    _offerBiometric();
  }

  /// Shows the biometric button, and asks once at once: the reason the
  /// user turned it on.
  Future<void> _offerBiometric() async {
    final biometrics = widget.biometrics;
    if (biometrics == null || !await biometrics.offered() || !mounted) return;
    setState(() => _biometric = true);
    await _unlockWithBiometrics();
  }

  Future<void> _unlockWithBiometrics() async {
    final biometrics = widget.biometrics;
    if (biometrics == null || _busy) return;
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _biometricProblem = null;
    });
    try {
      final text = BiometricPromptText(
        title: t.biometricPromptTitle,
        subtitle: t.biometricPromptSubtitle,
        cancel: t.biometricPromptCancel,
      );
      final ok = await biometrics.unlock(text);
      if (!ok && mounted && widget.vault.status == VaultStatus.locked && !widget.vault.biometricEnabled) {
        setState(() => _biometricProblem = t.biometricFailed);
      }
    } on BiometricException catch (e) {
      if (mounted) {
        setState(() {
          _biometric = widget.vault.biometricEnabled;
          _biometricProblem = e.failure == BiometricFailure.invalidated ? t.biometricInvalidated : t.biometricFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final ok = await widget.vault.unlock(_password.text);
    if (!mounted) return;
    _password.clear();
    setState(() {
      _busy = false;
      _wrong = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return _VaultScreen(
      children: [
        Text(t.unlockTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('unlockPassword'),
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _unlock(),
          decoration: InputDecoration(labelText: t.masterPasswordLabel, errorText: _wrong ? t.wrongPassword : null),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const ValueKey('unlock'),
          onPressed: _busy ? null : _unlock,
          child: Text(_busy ? t.working : t.unlockButton),
        ),
        if (_biometric) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('unlockBiometric'),
            icon: Icon(Platform.isWindows ? Icons.face_rounded : Icons.fingerprint_rounded),
            label: Text(Platform.isWindows ? t.unlockWindowsHello : t.unlockBiometric),
            onPressed: _busy ? null : _unlockWithBiometrics,
          ),
        ],
        if (_biometricProblem != null) ...[
          const SizedBox(height: 8),
          Text(
            _biometricProblem!,
            key: const ValueKey('biometricProblem'),
            style: TextStyle(color: context.colors.danger),
          ),
        ],
        if (widget.sync != null) ...[
          const SizedBox(height: 10),
          TextButton(
            key: const ValueKey('forgotPassword'),
            onPressed: _busy
                ? null
                : () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => RecoveryPage(services: widget.sync!))),
            child: Text(t.forgotPassword),
          ),
        ],
      ],
    );
  }
}
