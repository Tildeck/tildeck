import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'connect_form.dart';
import 'snippets_page.dart';

/// The home tab: saved hosts by group, and the ways to add one or connect
/// without saving.

/// What it takes to connect to a saved host: its password (asked now
/// when it is not saved), its key, and its startup snippet. Null when the
/// user cancels the password prompt.
Future<ConnectionTarget?> connectionTargetFor(BuildContext context, Vault vault, HostEntry host) async {
  String? password;
  KeyEntry? key;
  if (host.auth == HostAuth.password) {
    password = host.password ?? await _askPassword(context, host);
    if (password == null) return null;
  } else {
    key = vault.entry<KeyEntry>(host.keyId);
  }
  return ConnectionTarget(
    host: host.host,
    port: host.port,
    username: host.username,
    password: password,
    privateKey: key?.privateKey,
    passphrase: key?.passphrase,
    startupCommand: vault.entry<SnippetEntry>(host.startupSnippetId)?.command,
  );
}

Future<String?> _askPassword(BuildContext context, HostEntry host) {
  final t = AppLocalizations.of(context);
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.passwordFor(host.label)),
      content: TextField(
        key: const ValueKey('askPassword'),
        controller: controller,
        obscureText: true,
        autofocus: true,
        textDirection: TextDirection.ltr,
        onSubmitted: (v) => Navigator.pop(context, v),
        decoration: InputDecoration(labelText: t.passwordLabel),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(t.connectButton)),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class HostsPage extends StatelessWidget {
  const HostsPage({super.key, required this.vault, required this.onConnect});

  final Vault vault;
  final void Function(ConnectionTarget target) onConnect;

  Future<void> _connectHost(BuildContext context, HostEntry host) async {
    final target = await connectionTargetFor(context, vault, host);
    if (target != null) onConnect(target);
  }

  Future<void> _delete(BuildContext context, HostEntry host) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await vault.delete(host.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.hostDeleted),
        action: SnackBarAction(label: t.undo, onPressed: () => vault.put(host)),
      ),
    );
  }

  void _quickConnect(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(AppLocalizations.of(context).quickConnect)),
          body: ConnectForm(
            onConnect: (target) {
              Navigator.pop(context);
              onConnect(target);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final hosts = vault.hosts;
        final groups = <String, List<HostEntry>>{};
        for (final h in hosts) {
          groups.putIfAbsent(h.group.trim(), () => []).add(h);
        }
        final names = groups.keys.where((g) => g.isNotEmpty).toList()..sort();
        if (groups.containsKey('')) names.add('');

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(t.hostsTitle, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(
                      key: const ValueKey('openSnippets'),
                      tooltip: t.snippetsTitle,
                      icon: const Icon(Icons.code_rounded),
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => SnippetsPage(vault: vault))),
                    ),
                    IconButton(
                      tooltip: t.keysTitle,
                      icon: const Icon(Icons.key),
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KeysPage(vault: vault))),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('addHost'),
                      icon: const Icon(Icons.add),
                      label: Text(t.addHost),
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => HostEditorPage(vault: vault))),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('quickConnect'),
                      icon: const Icon(Icons.bolt),
                      label: Text(t.quickConnect),
                      onPressed: () => _quickConnect(context),
                    ),
                  ],
                ),
                if (vault.damaged.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(t.damagedRecords, style: TextStyle(color: c.danger)),
                ],
                const SizedBox(height: 20),
                if (hosts.isEmpty) Text(t.noHostsYet, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
                for (final group in names) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                    child: Text(
                      group.isEmpty ? t.ungrouped : group,
                      style: text.labelLarge?.copyWith(color: c.muted, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Card.outlined(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, host) in groups[group]!.indexed) ...[
                          if (i > 0) Divider(height: 1, color: c.line),
                          ListTile(
                            key: ValueKey('host-${host.id}'),
                            leading: Icon(host.auth == HostAuth.key ? Icons.key : Icons.dns_outlined, color: c.brand),
                            title: Text(host.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            // Connection labels are Latin content: always LTR.
                            subtitle: Text(
                              host.label,
                              textDirection: TextDirection.ltr,
                              textAlign: Directionality.of(context) == TextDirection.rtl
                                  ? TextAlign.right
                                  : TextAlign.left,
                            ),
                            onTap: () => _connectHost(context, host),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) => action == 'edit'
                                  ? Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => HostEditorPage(vault: vault, host: host),
                                      ),
                                    )
                                  : _delete(context, host),
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'edit', child: Text(t.editAction)),
                                PopupMenuItem(value: 'delete', child: Text(t.deleteAction)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class HostEditorPage extends StatefulWidget {
  const HostEditorPage({super.key, required this.vault, this.host});

  final Vault vault;
  final HostEntry? host;

  @override
  State<HostEditorPage> createState() => _HostEditorPageState();
}

class _HostEditorPageState extends State<HostEditorPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.host?.name);
  late final _group = TextEditingController(text: widget.host?.group);
  late final _host = TextEditingController(text: widget.host?.host);
  late final _port = TextEditingController(text: '${widget.host?.port ?? 22}');
  late final _username = TextEditingController(text: widget.host?.username);
  late final _password = TextEditingController(text: widget.host?.password);
  late HostAuth _auth = widget.host?.auth ?? HostAuth.password;
  late bool _savePassword = widget.host?.password != null;
  late String? _keyId = widget.host?.keyId;
  late String? _startupSnippetId = widget.host?.startupSnippetId;

  @override
  void dispose() {
    for (final c in [_name, _group, _host, _port, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await widget.vault.put(
      HostEntry(
        id: widget.host?.id ?? widget.vault.newId(),
        name: _name.text.trim(),
        group: _group.text.trim(),
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: _username.text.trim(),
        auth: _auth,
        password: _auth == HostAuth.password && _savePassword ? _password.text : null,
        keyId: _auth == HostAuth.key ? _keyId : null,
        startupSnippetId: _startupSnippetId,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    String? required(String? v) => (v == null || v.trim().isEmpty) ? t.fieldRequired : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.host == null ? t.addHost : t.editHost)),
      body: ListenableBuilder(
        listenable: widget.vault,
        builder: (context, _) {
          final keys = widget.vault.keys;
          if (_keyId != null && keys.every((k) => k.id != _keyId)) _keyId = null;
          final snippets = widget.vault.snippets;
          if (_startupSnippetId != null && snippets.every((x) => x.id != _startupSnippetId)) {
            _startupSnippetId = null;
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextFormField(
                      key: const ValueKey('hostName'),
                      controller: _name,
                      validator: required,
                      decoration: InputDecoration(labelText: t.hostNameLabel, hintText: t.hostNameHint),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const ValueKey('hostGroup'),
                      controller: _group,
                      decoration: InputDecoration(labelText: t.groupLabel, hintText: t.groupHint),
                    ),
                    const SizedBox(height: 14),
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
                    SegmentedButton<HostAuth>(
                      segments: [
                        ButtonSegment(
                          value: HostAuth.password,
                          label: Text(t.authPassword),
                          icon: const Icon(Icons.password),
                        ),
                        ButtonSegment(value: HostAuth.key, label: Text(t.authPrivateKey), icon: const Icon(Icons.key)),
                      ],
                      selected: {_auth},
                      onSelectionChanged: (s) => setState(() => _auth = s.first),
                    ),
                    const SizedBox(height: 14),
                    if (_auth == HostAuth.password) ...[
                      SwitchListTile(
                        key: const ValueKey('savePassword'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.savePassword),
                        subtitle: Text(t.askPasswordEachTime, style: TextStyle(color: c.muted)),
                        value: _savePassword,
                        onChanged: (v) => setState(() => _savePassword = v),
                      ),
                      if (_savePassword)
                        TextFormField(
                          key: const ValueKey('password'),
                          controller: _password,
                          obscureText: true,
                          textDirection: TextDirection.ltr,
                          validator: required,
                          decoration: InputDecoration(labelText: t.passwordLabel),
                        ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        key: const ValueKey('keyChoice'),
                        initialValue: _keyId,
                        decoration: InputDecoration(labelText: t.keyLabel, hintText: t.chooseKey),
                        validator: (v) => v == null ? t.fieldRequired : null,
                        items: [for (final k in keys) DropdownMenuItem(value: k.id, child: Text(k.name))],
                        onChanged: (v) => setState(() => _keyId = v),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(t.addKey),
                          onPressed: () async {
                            final id = await showKeyEditor(context, widget.vault);
                            if (id != null) setState(() => _keyId = id);
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('startupSnippet'),
                      initialValue: _startupSnippetId,
                      decoration: InputDecoration(labelText: t.startupSnippetLabel, helperText: t.startupSnippetHelp),
                      items: [
                        DropdownMenuItem(value: null, child: Text(t.noStartupSnippet)),
                        for (final x in snippets) DropdownMenuItem(value: x.id, child: Text(x.name)),
                      ],
                      onChanged: (v) => setState(() => _startupSnippetId = v),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(key: const ValueKey('saveHost'), onPressed: _save, child: Text(t.save)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Adds a private key to the vault; returns its id.
Future<String?> showKeyEditor(BuildContext context, Vault vault) {
  final t = AppLocalizations.of(context);
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final pem = TextEditingController();
  final passphrase = TextEditingController();
  String? required(String? v) => (v == null || v.trim().isEmpty) ? t.fieldRequired : null;

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.addKey),
      content: SizedBox(
        width: 480,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('keyName'),
                  controller: name,
                  validator: required,
                  decoration: InputDecoration(labelText: t.keyNameLabel, hintText: t.keyNameHint),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('keyPem'),
                  controller: pem,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12),
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
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('keyPassphrase'),
                  controller: passphrase,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t.passphraseLabel),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('saveKey'),
          onPressed: () async {
            if (!form.currentState!.validate()) return;
            final id = vault.newId();
            await vault.put(
              KeyEntry(
                id: id,
                name: name.text.trim(),
                privateKey: pem.text.trim(),
                passphrase: passphrase.text.isEmpty ? null : passphrase.text,
              ),
            );
            if (context.mounted) Navigator.pop(context, id);
          },
          child: Text(t.save),
        ),
      ],
    ),
  ).whenComplete(() {
    name.dispose();
    pem.dispose();
    passphrase.dispose();
  });
}

class KeysPage extends StatelessWidget {
  const KeysPage({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(t.keysTitle)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(t.addKey),
        onPressed: () => showKeyEditor(context, vault),
      ),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final keys = vault.keys;
          if (keys.isEmpty) {
            return Center(
              child: Text(t.noKeysYet, style: TextStyle(color: c.muted)),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final key in keys)
                ListTile(
                  leading: Icon(Icons.key, color: c.brand),
                  title: Text(key.name),
                  trailing: IconButton(
                    tooltip: t.deleteAction,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      if (vault.hosts.any((h) => h.keyId == key.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.keyInUse)));
                        return;
                      }
                      vault.delete(key.id);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
