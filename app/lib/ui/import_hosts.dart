import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/local_files.dart';
import '../ssh/putty_sessions.dart';
import '../ssh/ssh_config.dart';
import '../theme.dart';
import '../vault/host_csv.dart';
import '../vault/host_import.dart';
import '../vault/vault.dart';

/// Where an import reads from: this computer's ~/.ssh/config, a file the
/// user picks, and the key files the configuration names.
class SshConfigSource {
  const SshConfigSource({this.files = const DeviceFiles(), this.environment, this.readPutty = readPuttyRegistry});

  final LocalFiles files;

  /// PuTTY's saved sessions as `reg query` prints them; null without PuTTY.
  final Future<String?> Function() readPutty;

  /// Whether PuTTY's sessions are offered: on Windows.
  bool get puttyOffered => Platform.isWindows || readPutty != readPuttyRegistry;

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

/// Picks hosts from an SSH configuration, a CSV, or PuTTY, and saves them. Returns what was
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

enum _From { sshConfig, file, putty }

class _ImportHostsState extends State<_ImportHosts> {
  List<SshConfigHost>? _hosts;
  final _chosen = <String>{};
  bool _loading = true;
  bool _busy = false;
  _From _from = _From.sshConfig;
  String? _exported;

  @override
  void initState() {
    super.initState();
    widget.source.readDefault().then((text) => _show(text, from: _From.sshConfig));
  }

  void _show(String? text, {required _From from}) {
    if (!mounted) return;
    // A picked file is a hosts CSV (Termius's export, a spreadsheet) or an
    // SSH configuration.
    final hosts = text == null
        ? null
        : switch (from) {
            _From.putty => parsePuttyRegistry(text),
            _ when looksLikeHostsCsv(text) => parseHostsCsv(text),
            _ => parseSshConfig(text),
          };
    final user = widget.source.defaultUser;
    setState(() {
      _loading = false;
      _from = from;
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
    if (text != null) _show(text, from: _From.file);
  }

  Future<void> _putty() async {
    final text = await widget.source.readPutty();
    _show(text ?? '', from: _From.putty);
  }

  /// The saved hosts as CSV, without passwords or keys.
  Future<void> _export() async {
    const name = 'tildeck-hosts.csv';
    final file = await widget.source.files.downloadTarget(name);
    await file.writeAsString(hostsToCsv(widget.vault.hosts), flush: true);
    final kept = await widget.source.files.keep(file, name);
    if (mounted && kept != null) setState(() => _exported = kept);
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
            Text(switch (_from) {
              _From.sshConfig => t.importFromDefault,
              _From.file => t.importFromFile,
              _From.putty => t.importFromPutty,
            }, style: TextStyle(color: c.muted)),
            const SizedBox(height: 8),
            body,
            if (_exported != null) ...[
              const SizedBox(height: 10),
              Text(
                t.hostsExported(_exported!),
                key: const ValueKey('hostsExported'),
                style: TextStyle(color: c.muted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.source.puttyOffered)
          TextButton(key: const ValueKey('importPutty'), onPressed: _busy ? null : _putty, child: Text(t.importPutty)),
        TextButton(
          key: const ValueKey('exportHostsCsv'),
          onPressed: _busy || widget.vault.hosts.isEmpty ? null : _export,
          child: Text(t.exportHostsCsv),
        ),
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
