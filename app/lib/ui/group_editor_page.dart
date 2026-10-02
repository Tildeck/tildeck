import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'proxy_editor.dart';

/// Settings every host in a group inherits when it leaves them empty: the
/// username, the key, environment variables, and a startup snippet.
class GroupEditorPage extends StatefulWidget {
  const GroupEditorPage({super.key, required this.vault, required this.name, this.onDone});

  final Vault vault;

  /// The group's name, as its hosts write it.
  final String name;

  /// In a side panel: called instead of closing a page.
  final VoidCallback? onDone;

  void _close(BuildContext context) => onDone == null ? Navigator.pop(context) : onDone!();

  @override
  State<GroupEditorPage> createState() => _GroupEditorPageState();
}

class _GroupEditorPageState extends State<GroupEditorPage> {
  final _form = GlobalKey<FormState>();
  late final GroupEntry? _existing = widget.vault.groupNamed(widget.name);
  late final _username = TextEditingController(text: _existing?.username);
  late final _env = TextEditingController(text: formatEnv(_existing?.env ?? const {}));
  late String? _keyId = _existing?.keyId;
  late String? _snippetId = _existing?.startupSnippetId;
  late String? _jumpHostId = _existing?.jumpHostId;
  late String? _proxyId = _existing?.proxyId;
  late String? _identityId = _existing?.identityId;

  @override
  void dispose() {
    _username.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final username = _username.text.trim();
    await widget.vault.put(
      GroupEntry(
        id: _existing?.id ?? widget.vault.newId(),
        name: widget.name.trim(),
        username: username.isEmpty ? null : username,
        keyId: _keyId,
        startupSnippetId: _snippetId,
        env: parseEnv(_env.text) ?? const {},
        jumpHostId: _jumpHostId,
        proxyId: _proxyId,
        identityId: _identityId,
      ),
    );
    if (mounted) widget._close(context);
  }

  Future<void> _clear() async {
    final existing = _existing;
    if (existing != null) await widget.vault.delete(existing.id);
    if (mounted) widget._close(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final keys = widget.vault.keys;
    final snippets = widget.vault.snippets;
    if (_keyId != null && keys.every((k) => k.id != _keyId)) _keyId = null;
    if (_snippetId != null && snippets.every((s) => s.id != _snippetId)) _snippetId = null;
    final hosts = widget.vault.hosts;
    if (_jumpHostId != null && hosts.every((h) => h.id != _jumpHostId)) _jumpHostId = null;
    if (_proxyId != null && widget.vault.entry<ProxyEntry>(_proxyId) == null) _proxyId = null;

    return Scaffold(
      // The name keeps its own direction inside a Hebrew title (first-strong
      // isolate around it).
      appBar: AppBar(
        title: Text(t.groupSettingsTitle('${String.fromCharCode(0x2068)}${widget.name}${String.fromCharCode(0x2069)}')),
        automaticallyImplyLeading: widget.onDone == null,
        actions: [
          if (widget.onDone != null)
            IconButton(
              key: const ValueKey('closePanel'),
              tooltip: t.close,
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.onDone,
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(t.groupSettingsIntro, style: TextStyle(color: c.muted, height: 1.5)),
                const SizedBox(height: 20),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('groupIdentity'),
                  initialValue: widget.vault.identities.any((x) => x.id == _identityId) ? _identityId : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.identityLabel,
                    helperText: t.groupIdentityHelp,
                    helperMaxLines: 3,
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.noIdentity)),
                    for (final x in widget.vault.identities) DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ],
                  onChanged: (v) => setState(() => _identityId = v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('groupUsername'),
                  controller: _username,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: t.usernameLabel),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('groupKey'),
                  initialValue: _keyId,
                  decoration: InputDecoration(labelText: t.keyLabel),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.noneOption)),
                    for (final k in keys) DropdownMenuItem(value: k.id, child: Text(k.name)),
                  ],
                  onChanged: (v) => setState(() => _keyId = v),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('groupSnippet'),
                  initialValue: _snippetId,
                  decoration: InputDecoration(labelText: t.startupSnippetLabel),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.noneOption)),
                    for (final s in snippets) DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _snippetId = v),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('groupJumpHost'),
                  initialValue: _jumpHostId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.jumpHostLabel,
                    helperText: t.groupJumpHostHelp,
                    helperMaxLines: 3,
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.directConnection)),
                    for (final h in hosts) DropdownMenuItem(value: h.id, child: Text(h.name)),
                  ],
                  onChanged: (v) => setState(() => _jumpHostId = v),
                ),
                const SizedBox(height: 14),
                ProxyField(vault: widget.vault, value: _proxyId, onChanged: (v) => setState(() => _proxyId = v)),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('groupEnv'),
                  controller: _env,
                  minLines: 2,
                  maxLines: 6,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                  validator: (v) => parseEnv(v ?? '') == null ? t.envInvalid : null,
                  decoration: InputDecoration(
                    labelText: t.envLabel,
                    hintText: 'LANG=en_US.UTF-8',
                    helperText: t.envHelp,
                    helperMaxLines: 3,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(key: const ValueKey('saveGroup'), onPressed: _save, child: Text(t.save)),
                if (_existing != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    key: const ValueKey('clearGroup'),
                    style: TextButton.styleFrom(foregroundColor: c.danger),
                    onPressed: _clear,
                    child: Text(t.clearGroupSettings),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
