import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/local_files.dart';
import '../theme.dart';
import '../vault/backup.dart';
import '../vault/vault.dart';
import '../vault/vault_crypto.dart';

/// Saving the vault to an encrypted file, and adding a backup's entries to
/// it: no sync server needed.
class BackupPanel extends StatefulWidget {
  const BackupPanel({super.key, required this.vault, this.files = const DeviceFiles(), this.clock = DateTime.now});

  final Vault vault;
  final LocalFiles files;
  final DateTime Function() clock;

  @override
  State<BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<BackupPanel> {
  bool _busy = false;
  String? _error;

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _export() async {
    final t = AppLocalizations.of(context);
    final password = await _askPassword(t.backupExportPasswordTitle, t.backupExportPasswordBody);
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Someone at an unlocked device must not walk away with a copy to
      // guess at: the master password is asked for.
      final keys = await widget.vault.passwordKeys(password);
      if (keys == null) {
        if (mounted) setState(() => _error = t.wrongPassword);
        return;
      }
      keys.dispose();
      final name = backupFileName(widget.clock());
      final file = await widget.files.downloadTarget(name);
      await file.writeAsString(exportBackup(widget.vault), flush: true);
      final kept = await widget.files.keep(file, name);
      if (kept != null && mounted) _message(t.backupSaved(kept));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final t = AppLocalizations.of(context);
    final picked = await widget.files.pickToUpload();
    if (picked.isEmpty || !mounted) return;
    final bytes = await picked.first.read().fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    final text = utf8.decode(bytes, allowMalformed: true);
    if (!mounted) return;
    final password = await _askPassword(t.backupImportPasswordTitle, t.backupImportPasswordBody);
    if (password == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries = await readBackup(text, password, await VaultCrypto.load());
      final result = await importBackup(widget.vault, entries);
      if (mounted) _message(t.backupImported(result.added, result.kept));
    } on BackupException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.problem) {
            BackupProblem.notABackup => t.backupNotABackup,
            BackupProblem.newerVersion => t.backupNewer,
            BackupProblem.wrongPassword => t.backupWrongPassword,
          },
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword(String title, String body) => showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(title: title, body: body),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    Widget section(Key key, IconData icon, String title, String help, VoidCallback onPressed) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.brand),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(help, style: TextStyle(color: c.muted, fontSize: 13)),
                const SizedBox(height: 10),
                OutlinedButton(key: key, onPressed: _busy ? null : onPressed, child: Text(title)),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.backupIntro, style: TextStyle(color: c.muted, height: 1.5)),
        const SizedBox(height: 22),
        section(const ValueKey('backupExport'), Icons.save_alt_rounded, t.backupExport, t.backupExportHelp, _export),
        section(const ValueKey('backupImport'), Icons.restore_rounded, t.backupImport, t.backupImportHelp, _import),
        if (_error != null)
          Text(
            _error!,
            key: const ValueKey('backupError'),
            style: TextStyle(color: c.danger),
          ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title, required this.body});

  final String title;
  final String body;

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
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.body),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('backupPassword'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.masterPasswordLabel),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('backupPasswordContinue'),
          onPressed: () => Navigator.pop(context, _password.text),
          child: Text(t.continueButton),
        ),
      ],
    );
  }
}
