import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../local/local_shell.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'connect_form.dart';
import 'group_editor_page.dart';
import 'history_page.dart';
import 'keys_page.dart';
import 'proxy_editor.dart';
import 'snippets_page.dart';

/// The home tab: saved hosts by group, and the ways to add one or connect
/// without saving.

/// What it takes to connect to a saved host: its password (asked now
/// when it is not saved), its key, its environment, and its startup
/// snippet. Empty host settings take the group's. Null when the user
/// cancels the password prompt.
/// The hosts [host] connects through, nearest first. A loop (possible only
/// through edits on two devices) ends the chain where it repeats.
List<HostEntry> jumpChainOf(Vault vault, HostEntry host) {
  final chain = <HostEntry>[];
  final seen = {host.id};
  var current = host;
  while (true) {
    final id = current.jumpHostId ?? vault.groupNamed(current.group)?.jumpHostId;
    final next = id == null ? null : vault.entry<HostEntry>(id);
    if (next == null || !seen.add(next.id)) return chain;
    chain.add(next);
    current = next;
  }
}

/// Hosts that [host] may connect through: any other host whose own chain
/// does not come back to it.
List<HostEntry> jumpCandidatesFor(Vault vault, String? hostId) => [
  for (final h in vault.hosts)
    if (h.id != hostId && jumpChainOf(vault, h).every((j) => j.id != hostId)) h,
];

String localShellName(AppLocalizations t, LocalShell shell) => switch (shell.kind) {
  LocalShellKind.pwsh => 'PowerShell',
  LocalShellKind.windowsPowerShell => 'Windows PowerShell',
  LocalShellKind.cmd => t.shellCmd,
  LocalShellKind.wsl => 'WSL',
  LocalShellKind.posix => t.localTerminal,
};

Future<ConnectionTarget?> connectionTargetFor(BuildContext context, Vault vault, HostEntry host) async {
  // The farthest jump host is connected to first.
  ConnectionTarget? jump;
  for (final hop in jumpChainOf(vault, host).reversed) {
    if (!context.mounted) return null;
    final target = await _targetFor(context, vault, hop, jump);
    if (target == null) return null;
    jump = ConnectionTarget(
      host: target.host,
      port: target.port,
      username: target.username,
      password: target.password,
      privateKey: target.privateKey,
      passphrase: target.passphrase,
      jump: jump,
      proxy: target.proxy,
    );
  }
  if (!context.mounted) return null;
  return _targetFor(context, vault, host, jump);
}

Future<ConnectionTarget?> _targetFor(BuildContext context, Vault vault, HostEntry host, ConnectionTarget? jump) async {
  final group = vault.groupNamed(host.group);
  final effective = HostEntry(
    id: host.id,
    name: host.name,
    group: host.group,
    host: host.host,
    port: host.port,
    protocol: host.protocol,
    username: host.username.trim().isEmpty ? (group?.username ?? '') : host.username,
    auth: host.auth,
    password: host.password,
    keyId: host.keyId ?? group?.keyId,
  );
  String? password;
  KeyEntry? key;
  if (host.isTelnet) {
    // Telnet signs in inside the terminal; a saved password is offered there.
    password = host.password;
  } else if (effective.auth == HostAuth.password) {
    password = effective.password ?? await _askPassword(context, effective);
    if (password == null) return null;
  } else {
    key = vault.entry<KeyEntry>(effective.keyId);
  }
  return ConnectionTarget(
    host: effective.host,
    port: effective.port,
    username: effective.username,
    password: password,
    privateKey: key?.privateKey,
    passphrase: key?.passphrase,
    startupCommand: host.isTelnet
        ? null
        : vault.entry<SnippetEntry>(host.startupSnippetId ?? group?.startupSnippetId)?.command,
    environment: host.isTelnet ? const {} : {...?group?.env, ...host.env},
    hostId: host.id,
    jump: jump,
    agentKeys: host.agentForwarding && !host.isTelnet
        ? [for (final k in vault.keys) (privateKey: k.privateKey, passphrase: k.passphrase)]
        : null,
    // Only the hop that connects directly uses it; the connector decides.
    proxy: vault.entry<ProxyEntry>(host.proxyId ?? group?.proxyId)?.config,
    protocol: host.protocol,
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

class HostsPage extends StatefulWidget {
  const HostsPage({
    super.key,
    required this.vault,
    required this.onConnect,
    this.onOpenForwards,
    this.localShells,
    this.connectHost,
  });

  final Vault vault;
  final void Function(ConnectionTarget target) onConnect;

  /// Opens the port forwarding rules; null hides the button.
  final VoidCallback? onOpenForwards;

  /// The shells for local terminals; null looks for them on the desktop.
  final List<LocalShell>? localShells;

  /// Connects to a saved host outside a session: installing a key on it.
  final HostConnect? connectHost;

  @override
  State<HostsPage> createState() => _HostsPageState();
}

/// Whether [host] matches every word of [query]: by name, address, user,
/// group, or tag.
bool hostMatches(HostEntry host, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final haystack = [host.name, host.host, host.username, host.group, ...host.tags].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

class _HostsPageState extends State<HostsPage> {
  final _search = TextEditingController();
  String _query = '';

  Vault get vault => widget.vault;
  void Function(ConnectionTarget target) get onConnect => widget.onConnect;

  List<LocalShell> get _shells => widget.localShells ?? _found;

  /// Looked for once: the shells installed do not change while it runs.
  late final List<LocalShell> _found = localTerminalsSupported ? findLocalShells() : const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The saved hosts connected to most recently, each once, newest first.
  List<HostEntry> _recent() {
    final seen = <String>{};
    final hosts = <HostEntry>[];
    for (final entry in vault.history) {
      final host = vault.entry<HostEntry>(entry.hostId);
      if (host != null && seen.add(host.id)) hosts.add(host);
      if (hosts.length == 5) break;
    }
    return hosts;
  }

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
        final all = vault.hosts;
        final hosts = [
          for (final h in all)
            if (hostMatches(h, _query)) h,
        ];
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
                    if (_shells.isNotEmpty)
                      PopupMenuButton<LocalShell>(
                        key: const ValueKey('openLocalTerminal'),
                        tooltip: t.localTerminal,
                        icon: const Icon(Icons.terminal_rounded),
                        onSelected: (shell) =>
                            widget.onConnect(ConnectionTarget.local(shell, localShellName(t, shell))),
                        itemBuilder: (_) => [
                          for (final shell in _shells)
                            PopupMenuItem(
                              key: ValueKey('localShell-${shell.kind.name}'),
                              value: shell,
                              child: Text(localShellName(t, shell)),
                            ),
                        ],
                      ),
                    if (widget.onOpenForwards != null)
                      IconButton(
                        key: const ValueKey('openForwards'),
                        tooltip: t.forwardsTitle,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        onPressed: widget.onOpenForwards,
                      ),
                    IconButton(
                      key: const ValueKey('openHistory'),
                      tooltip: t.historyTitle,
                      icon: const Icon(Icons.history_rounded),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HistoryPage(vault: vault, onReconnect: (h) => _connectHost(context, h)),
                        ),
                      ),
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
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => KeysPage(vault: vault, connect: widget.connectHost),
                        ),
                      ),
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
                if (all.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('hostSearch'),
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: t.searchHosts,
                      isDense: true,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: t.clearSearch,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ],
                if (_query.isEmpty && _recent().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    t.recentTitle,
                    style: text.labelLarge?.copyWith(color: c.muted, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final host in _recent())
                        ActionChip(
                          key: ValueKey('recent-${host.id}'),
                          avatar: Icon(Icons.history_rounded, size: 18, color: c.brand),
                          label: Text(host.name),
                          onPressed: () => _connectHost(context, host),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                if (all.isEmpty) Text(t.noHostsYet, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
                if (all.isNotEmpty && hosts.isEmpty)
                  Text(t.noHostsMatch, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
                for (final group in names) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 0, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.isEmpty ? t.ungrouped : group,
                            style: text.labelLarge?.copyWith(color: c.muted, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (group.isNotEmpty)
                          IconButton(
                            key: ValueKey('groupSettings-$group'),
                            tooltip: t.groupSettings,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: vault.groupNamed(group) == null ? c.muted : c.brand,
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => GroupEditorPage(vault: vault, name: group),
                              ),
                            ),
                          ),
                      ],
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
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  host.label,
                                  textDirection: TextDirection.ltr,
                                  textAlign: Directionality.of(context) == TextDirection.rtl
                                      ? TextAlign.right
                                      : TextAlign.left,
                                ),
                                if (jumpChainOf(vault, host) case [final first, ...])
                                  Text(
                                    t.viaHost(first.name),
                                    key: ValueKey('via-${host.id}'),
                                    style: TextStyle(fontSize: 12, color: c.muted),
                                  ),
                                if (host.tags.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final tag in host.tags)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: c.brand.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(tag, style: TextStyle(fontSize: 12, color: c.brand)),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
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
  late final _tags = TextEditingController(text: widget.host?.tags.join(', '));
  late final _env = TextEditingController(text: formatEnv(widget.host?.env ?? const {}));
  late String? _jumpHostId = widget.host?.jumpHostId;
  late bool _agentForwarding = widget.host?.agentForwarding ?? false;
  late String? _proxyId = widget.host?.proxyId;
  late ConnectionProtocol _protocol = widget.host?.protocol ?? ConnectionProtocol.ssh;
  bool get _telnet => _protocol == ConnectionProtocol.telnet;

  @override
  void dispose() {
    for (final c in [_name, _group, _host, _port, _username, _password, _tags, _env]) {
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
        auth: _telnet ? HostAuth.password : _auth,
        password: (_telnet || _auth == HostAuth.password) && _savePassword ? _password.text : null,
        keyId: !_telnet && _auth == HostAuth.key ? _keyId : null,
        protocol: _protocol,
        startupSnippetId: _startupSnippetId,
        tags: [
          for (final tag in _tags.text.split(','))
            if (tag.trim().isNotEmpty) tag.trim(),
        ],
        env: parseEnv(_env.text) ?? const {},
        jumpHostId: _jumpHostId,
        agentForwarding: _agentForwarding,
        proxyId: _proxyId,
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
          final jumps = jumpCandidatesFor(widget.vault, widget.host?.id);
          if (_jumpHostId != null && jumps.every((h) => h.id != _jumpHostId)) _jumpHostId = null;
          // Settings the group provides may be left empty here.
          final group = widget.vault.groupNamed(_group.text);
          final groupJump = widget.vault.entry<HostEntry>(group?.jumpHostId);
          if (_proxyId != null && widget.vault.entry<ProxyEntry>(_proxyId) == null) _proxyId = null;
          final groupProxy = widget.vault.entry<ProxyEntry>(group?.proxyId);
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
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: t.groupLabel, hintText: t.groupHint),
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<ConnectionProtocol>(
                      key: const ValueKey('hostProtocol'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: ConnectionProtocol.ssh, label: Text('SSH')),
                        ButtonSegment(value: ConnectionProtocol.telnet, label: Text('Telnet')),
                      ],
                      selected: {_protocol},
                      onSelectionChanged: (s) => setState(() {
                        _protocol = s.first;
                        // Move a default port along with the protocol.
                        final port = _port.text.trim();
                        if (port == '22' && _telnet) _port.text = '23';
                        if (port == '23' && !_telnet) _port.text = '22';
                      }),
                    ),
                    if (_telnet) ...[
                      const SizedBox(height: 8),
                      Text(t.telnetWarning, style: TextStyle(color: c.danger, fontSize: 12.5, height: 1.4)),
                    ],
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
                      validator: _telnet || group?.username?.isNotEmpty == true ? null : required,
                      decoration: InputDecoration(
                        labelText: _telnet ? t.usernameOptional : t.usernameLabel,
                        helperText: group?.username?.isNotEmpty == true ? t.fromGroup(group!.username!) : null,
                      ),
                    ),
                    SizedBox(height: _telnet ? 8 : 18),
                    if (!_telnet)
                      SegmentedButton<HostAuth>(
                        segments: [
                          ButtonSegment(
                            value: HostAuth.password,
                            label: Text(t.authPassword),
                            icon: const Icon(Icons.password),
                          ),
                          ButtonSegment(
                            value: HostAuth.key,
                            label: Text(t.authPrivateKey),
                            icon: const Icon(Icons.key),
                          ),
                        ],
                        selected: {_auth},
                        onSelectionChanged: (s) => setState(() => _auth = s.first),
                      ),
                    const SizedBox(height: 14),
                    if (_telnet || _auth == HostAuth.password) ...[
                      SwitchListTile(
                        key: const ValueKey('savePassword'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.savePassword),
                        subtitle: Text(
                          _telnet ? t.telnetPasswordHelp : t.askPasswordEachTime,
                          style: TextStyle(color: c.muted),
                        ),
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
                        validator: (v) => v == null && group?.keyId == null ? t.fieldRequired : null,
                        items: [for (final k in keys) DropdownMenuItem(value: k.id, child: Text(k.name))],
                        onChanged: (v) => setState(() => _keyId = v),
                      ),
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            key: const ValueKey('hostGenerateKey'),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(t.generateKey),
                            onPressed: () async {
                              final id = await showKeyGenerator(context, widget.vault);
                              if (id != null) setState(() => _keyId = id);
                            },
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.file_download_outlined),
                            label: Text(t.importKey),
                            onPressed: () async {
                              final id = await showKeyEditor(context, widget.vault);
                              if (id != null) setState(() => _keyId = id);
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('jumpHost'),
                      initialValue: _jumpHostId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t.jumpHostLabel,
                        helperText: _jumpHostId == null && groupJump != null && groupJump.id != widget.host?.id
                            ? t.fromGroup(groupJump.name)
                            : t.jumpHostHelp,
                        helperMaxLines: 3,
                      ),
                      items: [
                        DropdownMenuItem(value: null, child: Text(t.directConnection)),
                        for (final h in jumps) DropdownMenuItem(value: h.id, child: Text(h.name)),
                      ],
                      onChanged: (v) => setState(() => _jumpHostId = v),
                    ),
                    const SizedBox(height: 14),
                    ProxyField(
                      vault: widget.vault,
                      value: _proxyId,
                      helperText: _proxyId == null && groupProxy != null ? t.fromGroup(groupProxy.name) : null,
                      onChanged: (v) => setState(() => _proxyId = v),
                    ),
                    const SizedBox(height: 6),
                    if (!_telnet)
                      SwitchListTile(
                        key: const ValueKey('agentForwarding'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.agentForwarding),
                        subtitle: Text(t.agentForwardingHelp, style: TextStyle(color: c.muted)),
                        value: _agentForwarding,
                        onChanged: (v) => setState(() => _agentForwarding = v),
                      ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const ValueKey('hostTags'),
                      controller: _tags,
                      decoration: InputDecoration(labelText: t.tagsLabel, hintText: t.tagsHint),
                    ),
                    const SizedBox(height: 14),
                    if (!_telnet)
                      TextFormField(
                        key: const ValueKey('hostEnv'),
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
                    const SizedBox(height: 14),
                    if (!_telnet)
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
