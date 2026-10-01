import 'package:dartssh2/dartssh2.dart' show SSHClient;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../logo.dart';
import '../ssh/file_browser.dart';
import '../ssh/history_recorder.dart';
import '../ssh/port_forwarding.dart';
import '../ssh/ssh_connector.dart';
import '../ssh/terminal_session.dart';
import '../terminal/terminal_themes.dart';
import '../theme.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'account_page.dart';
import 'files_page.dart';
import 'host_key_dialog.dart';
import 'password_pages.dart';
import 'port_forwards_page.dart';
import 'snippets_page.dart';
import 'terminal_settings_page.dart';
import 'hosts_page.dart';
import 'terminal_panel.dart';

/// The main screen: saved hosts, and open SSH sessions in tabs. Terminals
/// stay alive while another tab is shown.
class SessionsPage extends StatefulWidget {
  const SessionsPage({
    super.key,
    required this.vault,
    required this.connector,
    required this.sync,
    required this.showKeyBar,
    required this.onToggleLocale,
    required this.onToggleTheme,
  });

  final Vault vault;
  final SshConnector connector;
  final SyncServices sync;
  final bool showKeyBar;
  final VoidCallback onToggleLocale;
  final VoidCallback onToggleTheme;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  final _sessions = <TerminalSession>[];

  /// -1 is the hosts tab.
  int _selected = -1;

  /// A second session shown beside the selected one, on a wide screen.
  int? _splitWith;

  static const _splitMinWidth = 840.0;

  bool get _splitShown =>
      _selected >= 0 && _splitWith != null && _splitWith! < _sessions.length && _splitWith != _selected;

  /// Port forwarding rules that run, for as long as the app does.
  final _forwards = ForwardManager();

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    _forwards.dispose();
    super.dispose();
  }

  /// An authenticated connection to a saved host, for a forwarding rule.
  Future<SSHClient> _connectFor(BuildContext context, HostEntry host) async {
    final target = await connectionTargetFor(context, widget.vault, host);
    if (target == null) throw const ForwardException(ForwardProblem.connectFailed);
    return widget.connector.connect(
      target,
      promptHostKey: ({required target, required presented, required status, previous}) async => mounted
          ? showHostKeyDialog(context, target: target, presented: presented, status: status, previous: previous)
          : false,
    );
  }

  void _openForwards() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PortForwardsPage(vault: widget.vault, manager: _forwards, connect: _connectFor),
      ),
    );
  }

  void _open(ConnectionTarget target, {int? replacing}) {
    final session = TerminalSession(target)..autocomplete = widget.vault.preferences.autocomplete ?? true;
    setState(() {
      if (replacing == null) {
        _sessions.add(session);
        _selected = _sessions.length - 1;
      } else {
        _sessions[replacing].dispose();
        _sessions[replacing] = session;
        _selected = replacing;
      }
    });
    // A local shell is not a server: it stays out of the synced history.
    if (target.protocol != ConnectionProtocol.local) recordHistory(widget.vault, session);
    session.start(
      widget.connector,
      // The prompt arrives after network round trips; if the page is gone
      // by then, the key is simply not trusted.
      ({required target, required presented, required status, previous}) async => mounted
          ? showHostKeyDialog(context, target: target, presented: presented, status: status, previous: previous)
          : false,
    );
  }

  /// Splits the view with the most recent other session, or unsplits it.
  void _toggleSplit() {
    setState(() {
      if (_splitShown) {
        _splitWith = null;
      } else {
        _splitWith = _sessions.length - 1 == _selected ? _sessions.length - 2 : _sessions.length - 1;
      }
    });
  }

  /// One side of the split. A click on the other side makes it the active
  /// one, whose tab is selected and whose actions the bar shows.
  Widget _pane(int i, {required bool active}) => Listener(
    onPointerDown: active
        ? null
        : (_) => setState(() {
            _splitWith = _selected;
            _selected = i;
          }),
    child: _panel(i),
  );

  Widget _panel(int i) {
    final session = _sessions[i];
    return ListenableBuilder(
      key: ObjectKey(session),
      listenable: widget.vault,
      builder: (context, _) {
        final prefs = widget.vault.preferences;
        return TerminalPanel(
          session: session,
          showKeyBar: widget.showKeyBar,
          onReconnect: () => _open(session.target, replacing: i),
          theme: themeById(prefs.terminalTheme).theme,
          fontSize: prefs.fontSize ?? defaultFontSize,
          onFontSize: (size) => widget.vault.put(prefs.copyWith(fontSize: size)),
          snippets: {for (final x in widget.vault.snippets) x.name: x.command},
        );
      },
    );
  }

  /// Runs a snippet here, or opens a session on each chosen host and runs
  /// it there.
  Future<void> _runSnippet(TerminalSession session) async {
    final choice = await showSnippetPicker(context, widget.vault);
    if (choice == null || !mounted) return;
    switch (choice) {
      case RunHere(:final snippet):
        session.run(snippet.command);
      case RunOnHosts(:final snippet, :final hosts):
        for (final host in hosts) {
          if (!mounted) return;
          final target = await connectionTargetFor(context, widget.vault, host);
          if (target != null) _open(target.withStartupCommand(snippet.command));
        }
    }
  }

  void _openFiles(TerminalSession session) {
    final target = session.target;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilesPage(browser: FileBrowser(session.openSftp), title: '${target.username}@${target.host}'),
      ),
    );
  }

  void _close(int index) {
    setState(() {
      if (_splitWith == index) {
        _splitWith = null;
      } else if (_splitWith != null && _splitWith! > index) {
        _splitWith = _splitWith! - 1;
      }
      _sessions.removeAt(index).dispose();
      // Keep showing the same session when a tab before it closes; when the
      // shown tab closes, show its left neighbour (or the new connection tab).
      if (index <= _selected) _selected--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.desk,
        foregroundColor: c.deskInk,
        titleSpacing: 16,
        title: Row(
          children: [
            TildeckLogo(tile: c.deskBright, stroke: c.desk, size: 26),
            const SizedBox(width: 10),
            Text(t.appName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('lockVault'),
            tooltip: t.lockNow,
            color: c.deskMuted,
            icon: const Icon(Icons.lock_outline),
            onPressed: widget.vault.lock,
          ),
          IconButton(
            key: const ValueKey('openSync'),
            tooltip: t.syncTitle,
            color: c.deskMuted,
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountPage(services: widget.sync))),
          ),
          // The rest in one menu, so the bar fits a phone.
          PopupMenuButton<String>(
            key: const ValueKey('moreMenu'),
            tooltip: t.moreActions,
            iconColor: c.deskMuted,
            onSelected: (action) {
              switch (action) {
                case 'appearance':
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => TerminalSettingsPage(vault: widget.vault)));
                case 'password':
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => ChangePasswordPage(services: widget.sync)));
                case 'language':
                  widget.onToggleLocale();
                case 'theme':
                  widget.onToggleTheme();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const ValueKey('openTerminalSettings'),
                value: 'appearance',
                child: ListTile(leading: const Icon(Icons.palette_outlined), title: Text(t.terminalSettingsTitle)),
              ),
              PopupMenuItem(
                key: const ValueKey('openPassword'),
                value: 'password',
                child: ListTile(leading: const Icon(Icons.password_rounded), title: Text(t.changePasswordTitle)),
              ),
              PopupMenuItem(
                value: 'language',
                child: ListTile(leading: const Icon(Icons.translate_rounded), title: Text(_otherLanguageName(context))),
              ),
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  title: Text(dark ? t.switchToLight : t.switchToDark),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _TabStrip(
                    sessions: _sessions,
                    selected: _selected,
                    onSelect: (i) => setState(() => _selected = i),
                    onClose: _close,
                  ),
                ),
                if (_selected >= 0)
                  ListenableBuilder(
                    listenable: _sessions[_selected],
                    builder: (context, _) {
                      final session = _sessions[_selected];
                      final connected = session.state == SessionState.connected;
                      final canSplit = _sessions.length > 1 && MediaQuery.sizeOf(context).width >= _splitMinWidth;
                      if (!connected && !canSplit) return const SizedBox.shrink();
                      return Container(
                        height: 52,
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        decoration: BoxDecoration(
                          color: c.page,
                          border: Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Row(
                          children: [
                            if (canSplit) ...[
                              IconButton(
                                key: const ValueKey('splitView'),
                                tooltip: _splitShown ? t.unsplitView : t.splitView,
                                isSelected: _splitShown,
                                icon: const Icon(Icons.vertical_split_outlined),
                                selectedIcon: const Icon(Icons.vertical_split),
                                onPressed: _toggleSplit,
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (connected) ...[
                              OutlinedButton.icon(
                                key: const ValueKey('openSnippetPicker'),
                                onPressed: () => _runSnippet(session),
                                icon: const Icon(Icons.code_rounded, size: 18),
                                label: Text(t.snippetsTitle),
                              ),
                              if (session.isSsh) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  key: const ValueKey('openFiles'),
                                  onPressed: () => _openFiles(session),
                                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                                  label: Text(t.filesTitle),
                                ),
                              ],
                            ],
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
            Expanded(
              child: _splitShown && MediaQuery.sizeOf(context).width >= _splitMinWidth
                  ? Row(
                      children: [
                        Expanded(child: _pane(_selected, active: true)),
                        VerticalDivider(width: 2, thickness: 2, color: c.brand.withValues(alpha: 0.5)),
                        Expanded(child: _pane(_splitWith!, active: false)),
                      ],
                    )
                  : IndexedStack(
                      index: _selected + 1,
                      children: [
                        HostsPage(vault: widget.vault, onConnect: _open, onOpenForwards: _openForwards),
                        for (final (i, _) in _sessions.indexed) _panel(i),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// The other language, named in its own language.
  String _otherLanguageName(BuildContext context) {
    final other = Localizations.localeOf(context).languageCode == 'he' ? const Locale('en') : const Locale('he');
    return lookupAppLocalizations(other).nativeLanguageName;
  }
}

/// Asks for a tab name; an empty one brings back the connection label.
Future<void> _rename(BuildContext context, TerminalSession session) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: session.title ?? ''),
  );
  if (name != null) session.rename(name);
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.renameTab),
      content: TextField(
        key: const ValueKey('tabName'),
        controller: _name,
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(context, _name.text),
        decoration: InputDecoration(labelText: t.tabNameLabel, helperText: t.tabNameHelp),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: Text(t.save)),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.sessions, required this.selected, required this.onSelect, required this.onClose});

  final List<TerminalSession> sessions;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;

    Widget tab({
      required bool on,
      required Widget child,
      required VoidCallback onTap,
      VoidCallback? onRename,
      Key? key,
    }) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Material(
        key: key,
        color: on ? c.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: on ? c.brand : c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onDoubleTap: onRename,
          onLongPress: onRename,
          child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8), child: child),
        ),
      ),
    );

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: c.page,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (i, session) in sessions.indexed)
            ListenableBuilder(
              listenable: session,
              builder: (context, _) => tab(
                key: ValueKey('tab-$i'),
                on: i == selected,
                onTap: () => onSelect(i),
                onRename: () => _rename(context, session),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (session.state) {
                          SessionState.connected => c.success,
                          SessionState.connecting => c.brandBright,
                          SessionState.closed => session.problem == null ? c.muted : c.danger,
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // A connection label is Latin content: always LTR. A name
                    // the user gave keeps its own direction.
                    Text(
                      session.title ?? session.target.label,
                      textDirection: session.title == null ? TextDirection.ltr : null,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: t.closeSession,
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      color: c.muted,
                      icon: const Icon(Icons.close),
                      onPressed: () => onClose(i),
                    ),
                  ],
                ),
              ),
            ),
          tab(
            key: const ValueKey('hostsTab'),
            on: selected == -1,
            onTap: () => onSelect(-1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dns_outlined, size: 18, color: c.brand),
                const SizedBox(width: 6),
                Text(
                  t.hostsTitle,
                  style: TextStyle(color: c.brand, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
