import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../sync/account_service.dart';
import '../sync/sync_server.dart';
import '../theme.dart';
import 'account_page.dart';

/// Runs [attempt] without a code; when the account has two-factor sign-in
/// on, asks for a code from the authenticator app and runs it again with
/// it. Cancelling the question rethrows [TotpRequired].
Future<T> withSecondFactor<T>(BuildContext context, Future<T> Function(String? code) attempt) async {
  try {
    return await attempt(null);
  } on TotpRequired {
    if (!context.mounted) rethrow;
    final code = await askTotpCode(context);
    if (code == null) rethrow;
    return attempt(code);
  }
}

/// A code from the authenticator app, or null when cancelled.
Future<String?> askTotpCode(BuildContext context, {String? title}) => showDialog<String>(
  context: context,
  builder: (_) => _CodeDialog(title: title),
);

class _CodeDialog extends StatefulWidget {
  const _CodeDialog({this.title});

  final String? title;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _done() {
    final code = _code.text.replaceAll(' ', '');
    if (code.length == 6) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title ?? t.totpCodeTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.totpCodeHelp),
            const SizedBox(height: 16),
            _CodeField(controller: _code, onSubmitted: _done),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(key: const ValueKey('totpCodeContinue'), onPressed: _done, child: Text(t.continueButton)),
      ],
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return TextField(
      key: const ValueKey('totpCode'),
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLength: 7,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9 ]'))],
      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 26, letterSpacing: 6),
      decoration: InputDecoration(labelText: t.totpCodeLabel, counterText: ''),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Two-factor sign-in for the account: whether it is on, and turning it on
/// (scan, then confirm a code) or off (with a current code).
class TwoFactorSettings extends StatefulWidget {
  const TwoFactorSettings({super.key, required this.services});

  final SyncServices services;

  @override
  State<TwoFactorSettings> createState() => _TwoFactorSettingsState();
}

class _TwoFactorSettingsState extends State<TwoFactorSettings> {
  bool? _enabled;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await widget.services.accounts.twoFactorEnabled();
      if (mounted) setState(() => _enabled = enabled);
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorText(AppLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _turnOn() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final setup = await widget.services.accounts.startTwoFactor();
      if (!mounted) return;
      final on = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EnrollDialog(setup: setup, accounts: widget.services.accounts),
      );
      if (on == true && mounted) {
        setState(() => _enabled = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.totpTurnedOn)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = accountErrorText(t, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final t = AppLocalizations.of(context);
    final code = await askTotpCode(context, title: t.totpTurnOffTitle);
    if (code == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.services.accounts.disableTwoFactor(code);
      if (mounted) {
        setState(() => _enabled = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.totpTurnedOff)));
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
    final enabled = _enabled;
    final Widget action;
    if (_loading) {
      action = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
    } else if (enabled == null) {
      action = const SizedBox.shrink();
    } else if (enabled) {
      action = OutlinedButton(
        key: const ValueKey('totpTurnOff'),
        onPressed: _busy ? null : _turnOff,
        child: Text(t.turnOff),
      );
    } else {
      action = FilledButton(
        key: const ValueKey('totpTurnOn'),
        onPressed: _busy ? null : _turnOn,
        child: Text(t.turnOn),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(t.totpTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      if (enabled == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          key: const ValueKey('totpOn'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            t.totpOn,
                            style: TextStyle(color: c.success, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    enabled == null && !_loading ? t.totpNeedsAccount : t.totpHelp,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            action,
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const ValueKey('totpError'),
            style: TextStyle(color: c.danger),
          ),
        ],
      ],
    );
  }
}

/// Scan the QR code (or type the secret), then confirm with a code.
class _EnrollDialog extends StatefulWidget {
  const _EnrollDialog({required this.setup, required this.accounts});

  final TotpSetup setup;
  final AccountService accounts;

  @override
  State<_EnrollDialog> createState() => _EnrollDialogState();
}

class _EnrollDialogState extends State<_EnrollDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final t = AppLocalizations.of(context);
    if (_busy || _code.text.replaceAll(' ', '').length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.accounts.confirmTwoFactor(_code.text);
      if (mounted) Navigator.pop(context, true);
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
    return AlertDialog(
      title: Text(t.totpSetupTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.totpSetupScan),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: QrImageView(
                    key: const ValueKey('totpQr'),
                    data: widget.setup.uri,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(t.totpSetupManual, style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.setup.secret,
                      key: const ValueKey('totpSecret'),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14),
                    ),
                  ),
                  IconButton(
                    tooltip: t.copy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => Clipboard.setData(ClipboardData(text: widget.setup.secret)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(t.totpSetupConfirm),
              const SizedBox(height: 10),
              _CodeField(controller: _code, onSubmitted: _confirm),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const ValueKey('totpSetupError'),
                  style: TextStyle(color: c.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('totpConfirm'),
          onPressed: _busy ? null : _confirm,
          child: Text(_busy ? t.working : t.turnOn),
        ),
      ],
    );
  }
}
