import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/biometric.dart';
import '../theme.dart';
import '../vault/biometric_unlock.dart';

/// Biometric unlock on this device: shown only where the system offers it.
/// Turning it on takes the master password once, then the system's check.
class BiometricSettings extends StatefulWidget {
  const BiometricSettings({super.key, required this.biometrics});

  final BiometricUnlock biometrics;

  @override
  State<BiometricSettings> createState() => _BiometricSettingsState();
}

class _BiometricSettingsState extends State<BiometricSettings> {
  bool _available = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.biometrics.available().then((available) {
      if (mounted) setState(() => _available = available);
    });
  }

  Future<void> _set(bool on) async {
    final t = AppLocalizations.of(context);
    final biometrics = widget.biometrics;
    setState(() => _error = null);
    if (!on) {
      setState(() => _busy = true);
      await biometrics.disable();
      if (mounted) setState(() => _busy = false);
      return;
    }
    final password = await showDialog<String>(context: context, builder: (_) => const _MasterPasswordDialog());
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final text = BiometricPromptText(
        title: t.biometricEnableTitle,
        subtitle: t.biometricPromptSubtitle,
        cancel: t.cancel,
      );
      final ok = await biometrics.enable(password, text);
      if (mounted) setState(() => _error = ok ? null : t.wrongPassword);
    } on BiometricException catch (e) {
      final quiet = e.failure == BiometricFailure.cancelled || e.failure == BiometricFailure.interrupted;
      if (mounted && !quiet) setState(() => _error = t.biometricFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.biometrics.vault,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            key: const ValueKey('biometricSwitch'),
            contentPadding: EdgeInsets.zero,
            value: widget.biometrics.vault.biometricEnabled,
            onChanged: _busy ? null : _set,
            title: Text(
              Platform.isWindows ? t.unlockWindowsHello : t.unlockBiometric,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(t.biometricSettingHelp, style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          if (_error != null)
            Text(
              _error!,
              key: const ValueKey('biometricError'),
              style: TextStyle(color: c.danger),
            ),
        ],
      ),
    );
  }
}

class _MasterPasswordDialog extends StatefulWidget {
  const _MasterPasswordDialog();

  @override
  State<_MasterPasswordDialog> createState() => _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends State<_MasterPasswordDialog> {
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
      title: Text(t.biometricEnableTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.biometricEnableBody),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('biometricPassword'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.masterPasswordLabel),
              onSubmitted: (_) => Navigator.pop(context, _password.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('biometricConfirm'),
          onPressed: () => Navigator.pop(context, _password.text),
          child: Text(t.continueButton),
        ),
      ],
    );
  }
}
