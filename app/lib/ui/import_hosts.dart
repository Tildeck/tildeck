import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/local_files.dart';
import '../ssh/ssh_config.dart';
import '../theme.dart';
import '../vault/host_import.dart';
import '../vault/vault.dart';

/// Where an import reads from: this computer's ~/.ssh/config, a file the
/// user picks, and the key files the configuration names.
class SshConfigSource {
  const SshConfigSource({this.files = const DeviceFiles(), this.environment});

  final LocalFiles files;

  /// Null reads the process environment.
  final Map<String, String>? environment;

  Map<String, String> get _env => environment ?? Platform.environment;

  String? get _home => _env['HOME'] ?? _env['USERPROFILE'];

  String expand(String path) {
    final home = _home;
    if (home != null && (path == '~' || path.startsWith('~/') || path.startsWith(r'~\'))) {
      return '$home${path.substring(1)}';
    }
    return path;
  }

  /// ~/.ssh/config, or null when this device has none.
  Future<String?> readDefault() async {
    final home = _home;
    if (home == null) return null;
    final file = File('$home${Platform.pathSeparator}.ssh${Platform.pathSeparator}config');
    return await file.exists() ? file.readAsString() : null;
  }

  Future<String?> pick() async {
    final picked = await files.pickToUpload();
    if (picked.isEmpty) return null;
    final bytes = await picked.first.read().fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<String?> readFile(String path) async {
    final file = File(expand(path));
    try {
      return await file.exists() ? await file.readAsString() : null;
    } on FileSystemException {
      return null;
    }
  }

  String get defaultUser => sshDefaultUser(_env);
}

/// Picks hosts from an SSH configuration and saves them. Returns what was
/// imported, or null when cancelled.
Future<HostImportResult?> showImportHosts(BuildContext context, Vault vault, {SshConfigSource? source}) =>
    showDialog<HostImportResult>(
      context: context,
      builder: (_) => _ImportHosts(vault: vault, source: source ?? const SshConfigSource()),
    );

class _ImportHosts extends StatefulWidget {
  const _ImportHosts({required this.vault, required this.source});

  final Vault vault;
  final SshConfigSource source;

  @override
  State<_ImportHosts> createState() => _ImportHostsState();
}

class _ImportHostsState extends State<_ImportHosts> {
  List<SshConfigHost>? _hosts;
  final _chosen = <String>{};
  bool _loading = true;
  bool _busy = false;
  bool _fromDefault = true;

  @override
  void initState() {
    super.initState();
    widget.source.readDefault().then((text) => _show(text, fromDefault: true));
  }

  void _show(String? text, {required bool fromDefault}) {
    if (!mounted) return;
    final hosts = text == null ? null : parseSshConfig(text);
    final user = widget.source.defaultUser;
    setState(() {
      _loading = false;
      _fromDefault = fromDefault;
      _hosts = hosts;
      _chosen
        ..clear()
        ..addAll([
          for (final h in hosts ?? const <SshConfigHost>[])
            if (!alreadySaved(widget.vault, h, user)) h.alias,
        ]);
    });
  }

  Future<void> _pick() async {
    final text = await widget.source.pick();
    if (text != null) _show(text, fromDefault: false);
  }

  Future<void> _import() async {
    final hosts = _hosts;
    if (hosts == null || _chosen.isEmpty) return;
    setState(() => _busy = true);
    final result = await importSshHosts(
      widget.vault,
      [
        for (final h in hosts)
          if (_chosen.contains(h.alias)) h,
      ],
      readFile: widget.source.readFile,
      defaultUser: widget.source.defaultUser,
    );
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final hosts = _hosts;
    final user = widget.source.defaultUser;
    final Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (hosts == null || hosts.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          hosts == null ? t.importNoConfig : t.importNothingFound,
          key: const ValueKey('importEmpty'),
          style: TextStyle(color: c.muted, height: 1.5),
        ),
      );
    } else {
      body = Flexible(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final h in hosts)
              () {
                final saved = alreadySaved(widget.vault, h, user);
                final details = [
                  '${h.user ?? user}@${h.address}${h.port == null || h.port == 22 ? '' : ':${h.port}'}',
                  if (h.identityFiles.isNotEmpty) t.importKeyFile(h.identityFiles.first.split(RegExp(r'[\\/]')).last),
                  if (h.proxyJump != null) t.importThrough(h.proxyJump!),
                ].join(' · ');
                return CheckboxListTile(
                  key: ValueKey('import-${h.alias}'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: !saved && _chosen.contains(h.alias),
                  onChanged: saved || _busy
                      ? null
                      : (v) => setState(() => v == true ? _chosen.add(h.alias) : _chosen.remove(h.alias)),
                  title: Text(h.alias, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    saved ? t.importAlreadySaved : details,
                    textDirection: saved ? null : TextDirection.ltr,
                    textAlign: Directionality.of(context) == TextDirection.rtl && !saved ? TextAlign.right : null,
                    style: TextStyle(color: c.muted),
                  ),
                );
              }(),
          ],
        ),
      );
    }
    return AlertDialog(
      title: Text(t.importHostsTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_fromDefault ? t.importFromDefault : t.importFromFile, style: TextStyle(color: c.muted)),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('importPickFile'),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(t.importChooseFile),
          onPressed: _busy ? null : _pick,
        ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('importHostsConfirm'),
          onPressed: _busy || _chosen.isEmpty ? null : _import,
          child: Text(_busy ? t.working : t.importCount(_chosen.length)),
        ),
      ],
    );
  }
}
