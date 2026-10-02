import 'package:dartssh2/dartssh2.dart' show SSHClient;
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../logo.dart';
import '../settings/device_settings.dart';
import '../ssh/file_browser.dart';
import '../ssh/history_recorder.dart';
import '../ssh/port_forwarding.dart';
import '../ssh/ssh_connector.dart';
import '../ssh/terminal_session.dart';
import '../terminal/terminal_themes.dart';
import '../theme.dart';
import '../vault/biometric_unlock.dart';
import '../vault/models.dart';
import '../vault/vault.dart';
import 'account_page.dart';
import 'desktop_sidebar.dart';
import 'files_page.dart';
import 'history_page.dart';
import 'keys_page.dart';
import 'known_hosts_page.dart';
import 'host_key_dialog.dart';
import 'port_forwards_page.dart';
import 'snippets_page.dart';
import 'settings_page.dart';
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
    required this.settings,
    this.biometrics,
  });

  final Vault vault;
  final SshConnector connector;
  final SyncServices sync;
  final DeviceSettingsStore settings;
  final BiometricUnlock? biometrics;
  final bool showKeyBar;
  final VoidCallback onToggleLocale;
  final VoidCallback onToggleTheme;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

/// An open tab: a terminal, or the files of a server.
sealed class _Tab {
  Listenable get changes;
  void dispose();
}

final class _TermTab extends _Tab {
  _TermTab(this.session);
  final TerminalSession session;

  @override
  Listenable get changes => session;

  @override
  void dispose() => session.dispose();
}

final class _FilesTab extends _Tab {
  _FilesTab(this.browser, this.title);
  final FileBrowser browser;

  /// Who and where: user@host.
  final String title;

  @override
  Listenable get changes => browser;

  /// The files page owns its browser and closes it with itself.
  @override
  void dispose() {}
}

class _SessionsPageState extends State<SessionsPage> {
  final _tabs = <_Tab>[];

  /// The terminal in tab [i]; null for a files tab.
  TerminalSession? _term(int i) => switch (_tabs[i]) {
    _TermTab(:final session) => session,
    _FilesTab() => null,
  };

  /// -1 is the hosts tab, or on the desktop the chosen section.
  int _selected = -1;

  /// The desktop layout's section, shown when no session is.
  DeskSection _section = DeskSection.hosts;

  /// The section's page, in place of the hosts list.
  Widget _sectionPage() => switch (_section) {
    DeskSection.hosts => _hostsPage(desktop: true),
    DeskSection.keys => KeysPage(vault: widget.vault, connect: _connectFor),
    DeskSection.knownHosts => KnownHostsPage(vault: widget.vault),
    DeskSection.forwards => PortForwardsPage(vault: widget.vault, manager: _forwards, connect: _connectFor),
    DeskSection.snippets => SnippetsPage(vault: widget.vault),
    DeskSection.history => HistoryPage(
      vault: widget.vault,
      onReconnect: (host) async {
        final target = await connectionTargetFor(context, widget.vault, host);
        if (target != null) _open(target);
      },
    ),
    DeskSection.settings => SettingsPage(
      vault: widget.vault,
      settings: widget.settings,
      sync: widget.sync,
      biometrics: widget.biometrics,
    ),
  };

  Widget _hostsPage({required bool desktop}) => HostsPage(
    vault: widget.vault,
    onConnect: _open,
    // On the desktop, the sidebar has these.
    onOpenForwards: desktop ? null : _openForwards,
    desktop: desktop,
    connectHost: _connectFor,
    searchFocus: _hostSearch,
    onFiles: _showFiles,
  );

  /// A second session shown beside the selected one, on a wide screen.
  int? _splitWith;

  static const _splitMinWidth = 840.0;

  /// Two terminals side by side; a files tab is not split.
  bool get _splitShown =>
      _selected >= 0 &&
      _splitWith != null &&
      _splitWith! < _tabs.length &&
      _splitWith != _selected &&
      _term(_selected) != null &&
      _term(_splitWith!) != null;

  /// Port forwarding rules that run, for as long as the app does.
  final _forwards = ForwardManager();

  /// The hosts search, which a new connection (Ctrl+Shift+T) starts in.
  final _hostSearch = FocusNode(debugLabel: 'hostSearch');

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    _forwards.dispose();
    _hostSearch.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// To the hosts, typing into their search.
  void _newConnection() {
    setState(() {
      _selected = -1;
      _section = DeskSection.hosts;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _hostSearch.requestFocus());
  }

  /// The next or previous tab, the hosts counted as the first.
  void _cycle(int step) {
    final count = _tabs.length + 1;
    setState(() => _selected = (_selected + 1 + step) % count - 1);
  }

  void _closeOthers(int keep) {
    final kept = _tabs[keep];
    for (final tab in _tabs.where((tab) => tab != kept).toList()) {
      tab.dispose();
    }
    setState(() {
      _tabs
        ..clear()
        ..add(kept);
      _selected = 0;
      _splitWith = null;
    });
  }

  /// The app's keys, as Windows Terminal has them: with Shift, so the
  /// shell's own Ctrl keys (Ctrl+W deletes a word) stay the shell's.
  Map<ShortcutActivator, VoidCallback> get _keys => {
    const SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true): _newConnection,
    const SingleActivator(LogicalKeyboardKey.keyW, control: true, shift: true): () {
      if (_selected >= 0) _close(_selected);
    },
    const SingleActivator(LogicalKeyboardKey.tab, control: true): () => _cycle(1),
    const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): () => _cycle(-1),
    const SingleActivator(LogicalKeyboardKey.keyL, control: true, shift: true): widget.vault.lock,
    const SingleActivator(LogicalKeyboardKey.slash, control: true): () => showShortcuts(context),
  };

  /// Takes the app's keys before whatever has the focus (a terminal, a
  /// field), and without taking the focus itself: typing must reach the
  /// shell. Only while this page is on top: a page over it keeps its keys.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    for (final MapEntry(key: activator, value: action) in _keys.entries) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        action();
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
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
        _tabs.add(_TermTab(session));
        _selected = _tabs.length - 1;
      } else {
        _tabs[replacing].dispose();
        _tabs[replacing] = _TermTab(session);
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
        // The most recent other terminal.
        for (var i = _tabs.length - 1; i >= 0; i--) {
          if (i != _selected && _term(i) != null) {
            _splitWith = i;
            break;
          }
        }
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
    final tab = _tabs[i];
    if (tab is _FilesTab) {
      return FilesPage(key: ObjectKey(tab), browser: tab.browser, title: tab.title);
    }
    final session = (tab as _TermTab).session;
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
    _showFiles(FileBrowser(session.openSftp), '${target.username}@${target.host}');
  }

  /// Files open as a tab beside the terminals on the desktop, and as a page
  /// on a phone.
  void _showFiles(FileBrowser browser, String title) {
    if (isDesktopLayout(context)) {
      setState(() {
        _tabs.add(_FilesTab(browser, title));
        _selected = _tabs.length - 1;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FilesPage(browser: browser, title: title),
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
      _tabs.removeAt(index).dispose();
      // Keep showing the same session when a tab before it closes; when the
      // shown tab closes, show its left neighbour (or the new connection tab).
      if (index <= _selected) _selected--;
    });
  }

  /// The tabs, and the selected session's actions beside them.
  Widget _sessionBar(BuildContext context, {required bool showHome}) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: _TabStrip(
            tabs: _tabs,
            selected: _selected,
            showHome: showHome,
            onSelect: (i) => setState(() => _selected = i),
            onClose: _close,
            onCloseOthers: _closeOthers,
          ),
        ),
        if (_selected >= 0 && _term(_selected) != null)
          ListenableBuilder(
            listenable: _term(_selected)!,
            builder: (context, _) {
              final session = _term(_selected)!;
              final connected = session.state == SessionState.connected;
              final terminals = [for (var i = 0; i < _tabs.length; i++) _term(i)].nonNulls.length;
              final canSplit = terminals > 1 && MediaQuery.sizeOf(context).width >= _splitMinWidth;
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
    );
  }

  /// The selected session, the split, or [home] when no session is chosen.
  Widget _content(BuildContext context, Widget home) {
    final c = context.colors;
    return _splitShown && MediaQuery.sizeOf(context).width >= _splitMinWidth
        ? Row(
            children: [
              Expanded(child: _pane(_selected, active: true)),
              VerticalDivider(width: 2, thickness: 2, color: c.brand.withValues(alpha: 0.5)),
              Expanded(child: _pane(_splitWith!, active: false)),
            ],
          )
        : IndexedStack(index: _selected + 1, children: [home, for (final (i, _) in _tabs.indexed) _panel(i)]);
  }

  /// A sidebar with the sections, the tabs above the content: a desktop
  /// app, not a phone screen stretched.
  Widget _desktop(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Row(
        children: [
          DesktopSidebar(
            section: _section,
            sectionShown: _selected < 0,
            onSection: (s) => setState(() {
              _section = s;
              _selected = -1;
            }),
            onLock: widget.vault.lock,
            onToggleLocale: widget.onToggleLocale,
            onToggleTheme: widget.onToggleTheme,
            onShortcuts: () => showShortcuts(context),
            otherLanguageName: _otherLanguageName(context),
          ),
          Expanded(
            child: ColoredBox(
              color: c.page,
              child: Column(
                children: [
                  if (_tabs.isNotEmpty) _sessionBar(context, showHome: false),
                  Expanded(
                    // Each section keeps its own state while another shows.
                    child: _content(
                      context,
                      KeyedSubtree(key: ValueKey(_section), child: deskSectionTheme(context, _sectionPage())),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopLayout(context)) return _desktop(context);
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
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(
                        vault: widget.vault,
                        settings: widget.settings,
                        sync: widget.sync,
                        biometrics: widget.biometrics,
                      ),
                    ),
                  );
                case 'language':
                  widget.onToggleLocale();
                case 'theme':
                  widget.onToggleTheme();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const ValueKey('openSettings'),
                value: 'settings',
                child: ListTile(leading: const Icon(Icons.settings_outlined), title: Text(t.settingsTitle)),
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
            _sessionBar(context, showHome: true),
            Expanded(child: _content(context, _hostsPage(desktop: false))),
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
  const _TabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.showHome,
  });

  final ValueChanged<int> onCloseOthers;

  final List<_Tab> tabs;
  final int selected;

  /// The hosts tab; on the desktop the sidebar takes its place.
  final bool showHome;
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
      VoidCallback? onMiddleClick,
      void Function(Offset at)? onMenu,
      Key? key,
    }) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      // A middle click closes a tab, as in a browser.
      child: Listener(
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) onMiddleClick?.call();
        },
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
            onSecondaryTapUp: onMenu == null ? null : (d) => onMenu(d.globalPosition),
            child: Padding(padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8), child: child),
          ),
        ),
      ),
    );

    Future<void> menu(Offset at, int i, TerminalSession? session) async {
      final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
      final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
        items: [
          if (session != null)
            PopupMenuItem(key: const ValueKey('tabRename'), value: 'rename', child: Text(t.renameTab)),
          PopupMenuItem(key: const ValueKey('tabClose'), value: 'close', child: Text(t.closeSession)),
          if (tabs.length > 1)
            PopupMenuItem(key: const ValueKey('tabCloseOthers'), value: 'others', child: Text(t.closeOtherTabs)),
        ],
      );
      if (!context.mounted) return;
      switch (action) {
        case 'rename':
          await _rename(context, session!);
        case 'close':
          onClose(i);
        case 'others':
          onCloseOthers(i);
      }
    }

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
          for (final (i, item) in tabs.indexed)
            ListenableBuilder(
              listenable: item.changes,
              builder: (context, _) {
                final session = switch (item) {
                  _TermTab(:final session) => session,
                  _FilesTab() => null,
                };
                final close = IconButton(
                  tooltip: t.closeSession,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: c.muted,
                  icon: const Icon(Icons.close),
                  onPressed: () => onClose(i),
                );
                return tab(
                  key: ValueKey('tab-$i'),
                  on: i == selected,
                  onTap: () => onSelect(i),
                  onRename: session == null ? null : () => _rename(context, session),
                  onMiddleClick: () => onClose(i),
                  onMenu: (at) => menu(at, i, session),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: switch (item) {
                      _TermTab(:final session) => [
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
                        // A connection label is Latin content: always LTR. A
                        // name the user gave keeps its own direction.
                        Text(
                          session.title ?? session.target.label,
                          textDirection: session.title == null ? TextDirection.ltr : null,
                          style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        close,
                      ],
                      _FilesTab(:final title) => [
                        Icon(Icons.folder_open_rounded, size: 16, color: c.brand),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(color: c.ink, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        close,
                      ],
                    },
                  ),
                );
              },
            ),
          if (showHome)
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
