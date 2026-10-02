import 'dart:io';

import 'package:dartssh2/dartssh2.dart' show SSHClient;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../local/local_shell.dart';
import '../ssh/serial.dart';
import '../ssh/ssh_connector.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import '../ssh/file_browser.dart';
import 'connect_form.dart';
import 'files_page.dart';
import 'group_editor_page.dart';
import 'history_page.dart';
import 'host_folders.dart';
import 'server_picker.dart';
import 'identities_page.dart';
import 'import_hosts.dart';
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
  // A serial port is on this computer: nothing to connect through.
  if (host.isSerial) return chain;
  final seen = {host.id};
  var current = host;
  while (true) {
    final id = current.jumpHostId ?? vault.effectiveGroup(current.group)?.jumpHostId;
    final next = id == null ? null : vault.entry<HostEntry>(id);
    if (next == null || !seen.add(next.id)) return chain;
    chain.add(next);
    current = next;
  }
}

/// Hosts that [host] may connect through: any other SSH host whose own
/// chain does not come back to it.
List<HostEntry> jumpCandidatesFor(Vault vault, String? hostId) => [
  for (final h in vault.hosts)
    if (h.isSsh && h.id != hostId && jumpChainOf(vault, h).every((j) => j.id != hostId)) h,
];

/// Serial ports can be opened on desktop computers only.
bool get serialSupported => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Each protocol's usual port; a serial host's is its baud rate.
int defaultPortOf(ConnectionProtocol protocol) => switch (protocol) {
  ConnectionProtocol.ssh || ConnectionProtocol.local => 22,
  ConnectionProtocol.telnet => 23,
  ConnectionProtocol.serial => defaultBaudRate,
};

String localShellName(AppLocalizations t, LocalShell shell) => switch (shell.kind) {
  LocalShellKind.pwsh => 'PowerShell',
  LocalShellKind.windowsPowerShell => 'Windows PowerShell',
  LocalShellKind.cmd => t.shellCmd,
  LocalShellKind.wsl => 'WSL',
  LocalShellKind.posix => t.localTerminal,
};

/// The identity [host] signs in as: its own, or else its group's; null when
/// neither chose one (or it was deleted).
IdentityEntry? identityFor(Vault vault, HostEntry host) =>
    vault.entry<IdentityEntry>(host.identityId ?? vault.effectiveGroup(host.group)?.identityId);

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
      certificate: target.certificate,
      jump: jump,
      proxy: target.proxy,
    );
  }
  if (!context.mounted) return null;
  return _targetFor(context, vault, host, jump);
}

Future<ConnectionTarget?> _targetFor(BuildContext context, Vault vault, HostEntry host, ConnectionTarget? jump) async {
  final group = vault.effectiveGroup(host.group);
  // An identity (the host's, or else the group's) decides who signs in, and
  // how; without one, the host's fields, with the group's for empty ones.
  final identity = host.isSsh ? identityFor(vault, host) : null;
  final effective = HostEntry(
    id: host.id,
    name: host.name,
    group: host.group,
    host: host.host,
    port: host.port,
    protocol: host.protocol,
    username: identity?.username ?? (host.username.trim().isEmpty ? (group?.username ?? '') : host.username),
    auth: identity?.auth ?? host.auth,
    password: identity == null ? host.password : identity.password,
    keyId: identity == null ? host.keyId ?? group?.keyId : identity.keyId,
  );
  String? password;
  KeyEntry? key;
  if (host.isSerial) {
    // A serial console signs in inside the terminal, if at all.
  } else if (host.isTelnet) {
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
    certificate: key?.certificate,
    startupCommand: !host.isSsh
        ? null
        : vault.entry<SnippetEntry>(host.startupSnippetId ?? group?.startupSnippetId)?.command,
    environment: host.isSsh ? {...?group?.env, ...host.env} : const {},
    hostId: host.id,
    jump: jump,
    agentKeys: host.agentForwarding && host.isSsh
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
    this.desktop = false,
    this.searchFocus,
    this.onFiles,
  });

  final Vault vault;
  final void Function(ConnectionTarget target) onConnect;

  /// Opens the port forwarding rules; null hides the button.
  final VoidCallback? onOpenForwards;

  /// The shells for local terminals; null looks for them on the desktop.
  final List<LocalShell>? localShells;

  /// Connects to a saved host outside a session: installing a key on it.
  final HostConnect? connectHost;

  /// In the desktop layout: the hosts as a grid, edited in a side panel,
  /// and no buttons for what the sidebar has.
  final bool desktop;

  /// The search field's focus, for the new connection shortcut.
  final FocusNode? searchFocus;

  /// Shows a host's files (as a tab on the desktop); null opens a page.
  final void Function(FileBrowser browser, String title)? onFiles;

  @override
  State<HostsPage> createState() => _HostsPageState();
}

/// Whether [host] matches every word of [query]: by name, address, user,
/// group, or tag.
bool hostMatches(HostEntry host, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final haystack = [host.name, host.host, host.username, host.group, ...host.tags, host.notes].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

class _HostsPageState extends State<HostsPage> {
  final _search = TextEditingController();
  String _query = '';

  /// Folders folded away on this screen; a search unfolds what matches.
  final _collapsed = <String>{};

  void _toggleFolder(String path) => _collapsed.contains(path) ? _collapsed.remove(path) : _collapsed.add(path);

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

  /// The host's files over SFTP, on a connection of their own: no terminal.
  Future<void> _openFiles(BuildContext context, HostEntry host) async {
    SSHClient? client;
    final browser = FileBrowser(() async {
      final c = client = await widget.connectHost!(context, host);
      return c.sftp();
    }, onClose: () => client?.close());
    final show = widget.onFiles;
    if (show != null) {
      show(browser, host.label);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilesPage(
          browser: browser,
          title: host.label,
          otherServer: widget.connectHost == null
              ? null
              : (context) => pickOtherServer(context, vault, widget.connectHost!, except: host.label),
        ),
      ),
    );
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
    if (widget.desktop) {
      showDialog<void>(
        context: context,
        // The form scrolls itself: the dialog gives it a size.
        builder: (dialog) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 520,
            height: (MediaQuery.sizeOf(dialog).height * 0.8).clamp(320, 640),
            child: Scaffold(
              appBar: AppBar(
                title: Text(AppLocalizations.of(context).quickConnect),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    tooltip: AppLocalizations.of(context).close,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(dialog),
                  ),
                ],
              ),
              body: ConnectForm(
                onConnect: (target) {
                  Navigator.pop(dialog);
                  onConnect(target);
                },
              ),
            ),
          ),
        ),
      );
      return;
    }
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

  /// What the side panel shows in the desktop layout: a host being edited,
  /// a new one, or a group's settings; null when it is closed.
  ({HostEntry? host, String? group})? _panel;

  void _closePanel() => setState(() => _panel = null);

  Future<void> _importHosts(BuildContext context) async {
    final t = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showImportHosts(context, widget.vault);
    if (result == null) return;
    final skipped = result.unreadableKeys.length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          skipped == 0 ? t.importedHosts(result.hosts, result.keys) : t.importedHostsKeysSkipped(result.hosts, skipped),
        ),
      ),
    );
  }

  void _editHost(BuildContext context, HostEntry? host) {
    if (!widget.desktop) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostEditorPage(vault: vault, host: host),
        ),
      );
      return;
    }
    setState(() => _panel = (host: host, group: null));
  }

  void _editGroup(BuildContext context, String group) {
    if (!widget.desktop) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupEditorPage(vault: vault, name: group),
        ),
      );
      return;
    }
    setState(() => _panel = (host: null, group: group));
  }

  /// What a host's menu and its right-click offer.
  Future<void> _hostAction(BuildContext context, String action, HostEntry host) async {
    switch (action) {
      case 'connect':
        await _connectHost(context, host);
      case 'edit':
        _editHost(context, host);
      case 'files':
        await _openFiles(context, host);
      case 'duplicate':
        await _duplicate(context, host);
      case 'delete':
        if (_panel?.host?.id == host.id) _closePanel();
        await _delete(context, host);
    }
  }

  /// Every host in [folder] and the folders inside it, each in a session;
  /// many at once only after asking.
  Future<void> _openFolder(BuildContext context, String folder, Map<String, List<HostEntry>> byFolder) async {
    final t = AppLocalizations.of(context);
    final hosts = [
      for (final MapEntry(:key, :value) in byFolder.entries)
        if (key == folder || key.startsWith('$folder/')) ...value,
    ];
    if (hosts.isEmpty) return;
    if (hosts.length > 5) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.openFolderHostsTitle(hosts.length)),
          content: Text(t.openFolderHostsBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
            FilledButton(
              key: const ValueKey('openFolderConfirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t.openFolderHosts),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    for (final host in hosts) {
      if (!context.mounted) return;
      await _connectHost(context, host);
    }
  }

  /// A copy of [host], everything but its name, then opened for editing.
  Future<void> _duplicate(BuildContext context, HostEntry host) async {
    final t = AppLocalizations.of(context);
    final copy = HostEntry.fromJson(vault.newId(), {...host.dataJson(), 'name': t.copyName(host.name)});
    await vault.put(copy);
    if (context.mounted) _editHost(context, copy);
  }

  List<PopupMenuEntry<String>> _hostMenu(AppLocalizations t, HostEntry host) => [
    PopupMenuItem(value: 'connect', child: Text(t.connectButton)),
    if (widget.connectHost != null && host.isSsh)
      PopupMenuItem(key: const ValueKey('hostFiles'), value: 'files', child: Text(t.filesTitle)),
    PopupMenuItem(key: const ValueKey('hostEdit'), value: 'edit', child: Text(t.editAction)),
    PopupMenuItem(key: const ValueKey('hostDuplicate'), value: 'duplicate', child: Text(t.duplicateAction)),
    PopupMenuItem(value: 'delete', child: Text(t.deleteAction)),
  ];

  /// Hosts on a wide window: a header across the top, the hosts as cards in
  /// as many columns as fit, and editing in a panel beside them.
  Widget _desktopBuild(BuildContext context) {
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
          groups.putIfAbsent(canonicalGroup(h.group), () => []).add(h);
        }
        final names = [
          for (final g in folderOrder(groups.keys))
            if (_query.isNotEmpty || !headerHidden(g, _collapsed)) g,
        ];
        final panel = _panel;
        // A host deleted elsewhere (another device) closes its panel.
        final panelHost = panel?.host == null ? null : vault.entry<HostEntry>(panel!.host!.id);
        final panelOpen = panel != null && (panel.host == null || panelHost != null);

        // Narrow (a side panel open on a small screen): the search goes to
        // its own row, and with less room still the buttons keep only icons.
        final header = LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth - 56;
            final twoRows = width < 760;
            final iconsOnly = width < 520;
            final search = all.isEmpty
                ? null
                : TextField(
                    key: const ValueKey('hostSearch'),
                    focusNode: widget.searchFocus,
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: t.searchHosts,
                      isDense: true,
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: t.clearSearch,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  );
            final actions = [
              if (_shells.isNotEmpty)
                PopupMenuButton<LocalShell>(
                  key: const ValueKey('openLocalTerminal'),
                  tooltip: t.localTerminal,
                  icon: const Icon(Icons.terminal_rounded),
                  onSelected: (shell) => widget.onConnect(ConnectionTarget.local(shell, localShellName(t, shell))),
                  itemBuilder: (_) => [
                    for (final shell in _shells)
                      PopupMenuItem(
                        key: ValueKey('localShell-${shell.kind.name}'),
                        value: shell,
                        child: Text(localShellName(t, shell)),
                      ),
                  ],
                ),
              IconButton(
                key: const ValueKey('importHosts'),
                tooltip: t.importHostsTitle,
                icon: const Icon(Icons.download_rounded),
                onPressed: () => _importHosts(context),
              ),
              const SizedBox(width: 8),
              if (iconsOnly)
                IconButton.outlined(
                  key: const ValueKey('quickConnect'),
                  tooltip: t.quickConnect,
                  icon: const Icon(Icons.bolt, size: 18),
                  onPressed: () => _quickConnect(context),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('quickConnect'),
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text(t.quickConnect),
                  onPressed: () => _quickConnect(context),
                ),
              const SizedBox(width: 10),
              if (iconsOnly)
                IconButton.filled(
                  key: const ValueKey('addHost'),
                  tooltip: t.addHost,
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _editHost(context, null),
                )
              else
                FilledButton.icon(
                  key: const ValueKey('addHost'),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t.addHost),
                  onPressed: () => _editHost(context, null),
                ),
            ];
            final title = Text(
              t.hostsTitle,
              overflow: TextOverflow.ellipsis,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            );
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(28, 24, 28, 8),
              child: twoRows
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: title),
                            ...actions,
                          ],
                        ),
                        if (search != null) ...[const SizedBox(height: 12), search],
                      ],
                    )
                  : Row(
                      children: [
                        title,
                        const SizedBox(width: 24),
                        if (search != null) SizedBox(width: 340, child: search),
                        const Spacer(),
                        ...actions,
                      ],
                    ),
            );
          },
        );

        final list = ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(28, 8, 28, 32),
          children: [
            if (vault.damaged.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(t.damagedRecords, style: TextStyle(color: c.danger)),
              ),
            if (_query.isEmpty && _recent().isNotEmpty) ...[
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
              const SizedBox(height: 12),
            ],
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(t.noHostsYet, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
              ),
            if (all.isNotEmpty && hosts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(t.noHostsMatch, style: text.bodyLarge?.copyWith(color: c.muted, height: 1.5)),
              ),
            for (final group in names) ...[
              Padding(
                padding: EdgeInsetsDirectional.only(top: 14, bottom: 8, start: depthOf(group) * 22.0),
                child: Row(
                  children: [
                    _FolderToggle(
                      path: group,
                      collapsed: _collapsed.contains(group),
                      onToggle: () => setState(() => _toggleFolder(group)),
                    ),
                    Text(
                      group.isEmpty ? t.ungrouped : leafOf(group),
                      style: text.titleSmall?.copyWith(color: c.muted, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text('${hostCountUnder(group, groups)}', style: text.labelMedium?.copyWith(color: c.muted)),
                    if (group.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        key: ValueKey('groupSettings-$group'),
                        tooltip: t.groupSettings,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: vault.groupNamed(group) == null ? c.muted : c.brand,
                        ),
                        onPressed: () => _editGroup(context, group),
                      ),
                      IconButton(
                        key: ValueKey('openFolder-$group'),
                        tooltip: t.openFolderHosts,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.playlist_play_rounded, size: 20, color: c.muted),
                        onPressed: () => _openFolder(context, group, groups),
                      ),
                    ],
                  ],
                ),
              ),
              if (groups[group] != null && (_query.isNotEmpty || !hostsHidden(group, _collapsed)))
                LayoutBuilder(
                  builder: (context, box) {
                    const gap = 12.0;
                    final columns = ((box.maxWidth + gap) / (280 + gap)).floor().clamp(1, 6);
                    final width = (box.maxWidth - gap * (columns - 1)) / columns;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final host in groups[group]!)
                          SizedBox(
                            width: width,
                            child: _HostCard(
                              host: host,
                              via: switch (jumpChainOf(vault, host)) {
                                [final first, ...] => t.viaHost(first.name),
                                _ => null,
                              },
                              selected: panelHost?.id == host.id,
                              onConnect: () => _connectHost(context, host),
                              menu: () => _hostMenu(t, host),
                              onAction: (action) => _hostAction(context, action, host),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ],
        );

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  header,
                  Expanded(child: list),
                ],
              ),
            ),
            if (panelOpen)
              Container(
                width: 460,
                decoration: BoxDecoration(
                  border: BorderDirectional(start: BorderSide(color: c.line)),
                ),
                child: panel.group != null
                    ? GroupEditorPage(
                        key: ValueKey('group-${panel.group}'),
                        vault: vault,
                        name: panel.group!,
                        onDone: _closePanel,
                      )
                    : HostEditorPage(
                        key: ValueKey('editor-${panelHost?.id ?? 'new'}'),
                        vault: vault,
                        host: panelHost,
                        onDone: _closePanel,
                      ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    if (widget.desktop) return _desktopBuild(context);

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
          groups.putIfAbsent(canonicalGroup(h.group), () => []).add(h);
        }
        final names = [
          for (final g in folderOrder(groups.keys))
            if (_query.isNotEmpty || !headerHidden(g, _collapsed)) g,
        ];

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
                    if (!widget.desktop) ...[
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
                        key: const ValueKey('openIdentities'),
                        tooltip: t.identitiesTitle,
                        icon: const Icon(Icons.badge_outlined),
                        onPressed: () => Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => IdentitiesPage(vault: vault))),
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
                    focusNode: widget.searchFocus,
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
                    padding: EdgeInsetsDirectional.fromSTEB(4 + depthOf(group) * 18.0, 8, 0, 2),
                    child: Row(
                      children: [
                        _FolderToggle(
                          path: group,
                          collapsed: _collapsed.contains(group),
                          onToggle: () => setState(() => _toggleFolder(group)),
                        ),
                        Expanded(
                          child: Text(
                            '${group.isEmpty ? t.ungrouped : leafOf(group)}  ${hostCountUnder(group, groups)}',
                            style: text.labelLarge?.copyWith(color: c.muted, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (group.isNotEmpty)
                          IconButton(
                            key: ValueKey('openFolder-$group'),
                            tooltip: t.openFolderHosts,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.playlist_play_rounded, size: 20, color: c.muted),
                            onPressed: () => _openFolder(context, group, groups),
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
                  if (groups[group] != null && (_query.isNotEmpty || !hostsHidden(group, _collapsed)))
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
                                key: ValueKey('hostMenu-${host.id}'),
                                onSelected: (action) => switch (action) {
                                  'edit' => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => HostEditorPage(vault: vault, host: host),
                                    ),
                                  ),
                                  'files' => _openFiles(context, host),
                                  'duplicate' => _duplicate(context, host),
                                  _ => _delete(context, host),
                                },
                                itemBuilder: (_) => [
                                  if (widget.connectHost != null && host.isSsh)
                                    PopupMenuItem(
                                      key: const ValueKey('hostFiles'),
                                      value: 'files',
                                      child: Text(t.filesTitle),
                                    ),
                                  PopupMenuItem(value: 'edit', child: Text(t.editAction)),
                                  PopupMenuItem(
                                    key: const ValueKey('hostDuplicate'),
                                    value: 'duplicate',
                                    child: Text(t.duplicateAction),
                                  ),
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
  const HostEditorPage({super.key, required this.vault, this.host, this.onDone});

  final Vault vault;
  final HostEntry? host;

  /// In a side panel: called instead of closing a page, and the bar has a
  /// close button instead of the way back.
  final VoidCallback? onDone;

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
  late final _notes = TextEditingController(text: widget.host?.notes);
  late final _env = TextEditingController(text: formatEnv(widget.host?.env ?? const {}));
  late String? _jumpHostId = widget.host?.jumpHostId;
  late bool _agentForwarding = widget.host?.agentForwarding ?? false;
  late String? _proxyId = widget.host?.proxyId;
  late String? _identityId = widget.host?.identityId;
  late ConnectionProtocol _protocol = widget.host?.protocol ?? ConnectionProtocol.ssh;
  bool get _telnet => _protocol == ConnectionProtocol.telnet;
  bool get _serial => _protocol == ConnectionProtocol.serial;
  bool get _ssh => _protocol == ConnectionProtocol.ssh;

  @override
  void dispose() {
    for (final c in [_name, _group, _host, _port, _username, _password, _tags, _env, _notes]) {
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
        group: canonicalGroup(_group.text),
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        username: _serial ? '' : _username.text.trim(),
        auth: _ssh ? _auth : HostAuth.password,
        password: !_serial && (_telnet || _auth == HostAuth.password) && _savePassword ? _password.text : null,
        keyId: _ssh && _auth == HostAuth.key ? _keyId : null,
        protocol: _protocol,
        startupSnippetId: _startupSnippetId,
        tags: [
          for (final tag in _tags.text.split(','))
            if (tag.trim().isNotEmpty) tag.trim(),
        ],
        env: parseEnv(_env.text) ?? const {},
        agentForwarding: _agentForwarding,
        identityId: _ssh ? _identityId : null,
        jumpHostId: _serial ? null : _jumpHostId,
        proxyId: _serial ? null : _proxyId,
        notes: _notes.text.trim(),
      ),
    );
    if (!mounted) return;
    final done = widget.onDone;
    done == null ? Navigator.pop(context) : done();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    String? required(String? v) => (v == null || v.trim().isEmpty) ? t.fieldRequired : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host == null ? t.addHost : t.editHost),
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
          final group = widget.vault.effectiveGroup(_group.text);
          final groupJump = widget.vault.entry<HostEntry>(group?.jumpHostId);
          if (_proxyId != null && widget.vault.entry<ProxyEntry>(_proxyId) == null) _proxyId = null;
          final groupProxy = widget.vault.entry<ProxyEntry>(group?.proxyId);
          final identities = widget.vault.identities;
          if (_identityId != null && identities.every((x) => x.id != _identityId)) _identityId = null;
          final groupIdentity = widget.vault.entry<IdentityEntry>(group?.identityId);
          // With an identity (this host's or the group's), it signs in: the
          // fields below are not used, so they are not shown.
          final identity = !_ssh ? null : widget.vault.entry<IdentityEntry>(_identityId) ?? groupIdentity;
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
                      segments: [
                        const ButtonSegment(value: ConnectionProtocol.ssh, label: Text('SSH')),
                        const ButtonSegment(value: ConnectionProtocol.telnet, label: Text('Telnet')),
                        if (serialSupported || _serial)
                          ButtonSegment(value: ConnectionProtocol.serial, label: Text(t.serial)),
                      ],
                      selected: {_protocol},
                      onSelectionChanged: (s) => setState(() {
                        // Move a default port along with the protocol.
                        if (_port.text.trim() == '${defaultPortOf(_protocol)}') {
                          _port.text = '${defaultPortOf(s.first)}';
                        }
                        _protocol = s.first;
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
                            decoration: _serial
                                ? InputDecoration(
                                    labelText: t.serialPortLabel,
                                    hintText: Platform.isWindows ? 'COM3' : '/dev/ttyUSB0',
                                    suffixIcon: PopupMenuButton<String>(
                                      key: const ValueKey('serialPorts'),
                                      icon: const Icon(Icons.usb_rounded),
                                      tooltip: t.serialPortsFound,
                                      onSelected: (v) => setState(() => _host.text = v),
                                      itemBuilder: (_) {
                                        final ports = serialPortNames();
                                        return [
                                          if (ports.isEmpty)
                                            PopupMenuItem(enabled: false, child: Text(t.noSerialPorts)),
                                          for (final p in ports) PopupMenuItem(value: p, child: Text(p)),
                                        ];
                                      },
                                    ),
                                  )
                                : InputDecoration(labelText: t.hostLabel, hintText: t.hostHint),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: _serial ? 120 : 96,
                          child: TextFormField(
                            key: const ValueKey('port'),
                            controller: _port,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              final port = int.tryParse(v?.trim() ?? '');
                              if (_serial) return port == null || port < 1 || port > 4000000 ? t.baudRateInvalid : null;
                              return port == null || port < 1 || port > 65535 ? t.portInvalid : null;
                            },
                            decoration: InputDecoration(labelText: _serial ? t.baudRateLabel : t.portLabel),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_ssh) ...[
                      DropdownButtonFormField<String?>(
                        key: const ValueKey('hostIdentity'),
                        initialValue: _identityId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t.identityLabel,
                          helperText: identity == null
                              ? t.identityHelp
                              : identityCredentials(t, widget.vault, identity),
                          helperMaxLines: 3,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(groupIdentity == null ? t.noIdentity : t.fromGroup(groupIdentity.name)),
                          ),
                          for (final x in identities) DropdownMenuItem(value: x.id, child: Text(x.name)),
                        ],
                        onChanged: (v) => setState(() => _identityId = v),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const ValueKey('hostNewIdentity'),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(t.addIdentity),
                          onPressed: () async {
                            final id = await showIdentityEditor(context, widget.vault);
                            if (id != null) setState(() => _identityId = id);
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (identity == null && !_serial) ...[
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
                    ],
                    if (!_serial) ...[
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
                    ],
                    const SizedBox(height: 6),
                    if (_ssh)
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
                    TextFormField(
                      key: const ValueKey('hostNotes'),
                      controller: _notes,
                      minLines: 2,
                      maxLines: 8,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        labelText: t.notesLabel,
                        hintText: t.notesHint,
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_ssh)
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
                    if (_ssh)
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

/// A host in the desktop grid: a click connects, the menu or a right-click
/// offers the rest, and the border answers the pointer.
class _HostCard extends StatefulWidget {
  const _HostCard({
    required this.host,
    required this.via,
    required this.selected,
    required this.onConnect,
    required this.menu,
    required this.onAction,
  });

  final HostEntry host;

  /// The jump host it goes through, as a line; null when direct.
  final String? via;

  /// Open in the side panel.
  final bool selected;
  final VoidCallback onConnect;
  final List<PopupMenuEntry<String>> Function() menu;
  final ValueChanged<String> onAction;

  @override
  State<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<_HostCard> {
  var _hover = false;

  Future<void> _contextMenu(Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: widget.menu(),
    );
    if (action != null) widget.onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final host = widget.host;
    final ltrStart = Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left;
    final border = widget.selected
        ? c.brand
        : _hover
        ? c.brand.withValues(alpha: 0.5)
        : c.line;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: widget.selected ? 1.5 : 1),
        ),
        child: InkWell(
          key: ValueKey('host-${host.id}'),
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onConnect,
          onSecondaryTapUp: (d) => _contextMenu(d.globalPosition),
          onLongPress: () {
            final box = context.findRenderObject()! as RenderBox;
            _contextMenu(box.localToGlobal(box.size.center(Offset.zero)));
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    host.isSerial
                        ? Icons.usb_rounded
                        : host.isTelnet
                        ? Icons.lan_outlined
                        : host.auth == HostAuth.key
                        ? Icons.key_rounded
                        : Icons.dns_outlined,
                    size: 20,
                    color: c.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        host.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      // A connection label is Latin content: LTR, at the start.
                      Text(
                        host.label,
                        textDirection: TextDirection.ltr,
                        textAlign: ltrStart,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                      if (widget.via != null) Text(widget.via!, style: TextStyle(color: c.muted, fontSize: 11.5)),
                      if (host.notes.isNotEmpty)
                        Tooltip(
                          message: host.notes,
                          child: Row(
                            key: ValueKey('notes-${host.id}'),
                            children: [
                              Icon(Icons.sticky_note_2_outlined, size: 13, color: c.muted),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  host.notes.split('\n').first,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.muted, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (host.tags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            for (final tag in host.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(
                                  color: c.brand.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(tag, style: TextStyle(fontSize: 11.5, color: c.brand)),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('hostMenu-${host.id}'),
                  iconSize: 20,
                  onSelected: widget.onAction,
                  itemBuilder: (_) => widget.menu(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The arrow that folds a folder away, or opens it.
class _FolderToggle extends StatelessWidget {
  const _FolderToggle({required this.path, required this.collapsed, required this.onToggle});

  final String path;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return IconButton(
      key: ValueKey('folderToggle-$path'),
      tooltip: collapsed ? t.expandFolder : t.collapseFolder,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
        size: 20,
        color: c.muted,
        // In Hebrew the closed arrow points to the start, to the left.
        textDirection: Directionality.of(context),
      ),
      onPressed: onToggle,
    );
  }
}
