import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../logo.dart';
import '../ssh/file_browser.dart';
import '../ssh/ssh_connector.dart';
import '../ssh/terminal_session.dart';
import '../theme.dart';
import '../vault/vault.dart';
import 'account_page.dart';
import 'files_page.dart';
import 'host_key_dialog.dart';
import 'password_pages.dart';
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

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  void _open(ConnectionTarget target, {int? replacing}) {
    final session = TerminalSession(target);
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
    session.start(
      widget.connector,
      // The prompt arrives after network round trips; if the page is gone
      // by then, the key is simply not trusted.
      ({required target, required presented, required status, previous}) async => mounted
          ? showHostKeyDialog(context, target: target, presented: presented, status: status, previous: previous)
          : false,
    );
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
            key: const ValueKey('openPassword'),
            tooltip: t.changePasswordTitle,
            color: c.deskMuted,
            icon: const Icon(Icons.password_rounded),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => ChangePasswordPage(services: widget.sync))),
          ),
          IconButton(
            key: const ValueKey('openSync'),
            tooltip: t.syncTitle,
            color: c.deskMuted,
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountPage(services: widget.sync))),
          ),
          TextButton(
            onPressed: widget.onToggleLocale,
            style: TextButton.styleFrom(foregroundColor: c.deskMuted),
            child: Text(_otherLanguageName(context)),
          ),
          IconButton(
            onPressed: widget.onToggleTheme,
            tooltip: dark ? t.switchToLight : t.switchToDark,
            color: c.deskMuted,
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
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
                      if (session.state != SessionState.connected) return const SizedBox.shrink();
                      return Container(
                        height: 52,
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        decoration: BoxDecoration(
                          color: c.page,
                          border: Border(bottom: BorderSide(color: c.line)),
                        ),
                        child: Center(
                          child: OutlinedButton.icon(
                            key: const ValueKey('openFiles'),
                            onPressed: () => _openFiles(session),
                            icon: const Icon(Icons.folder_open_rounded, size: 18),
                            label: Text(t.filesTitle),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            Expanded(
              child: IndexedStack(
                index: _selected + 1,
                children: [
                  HostsPage(vault: widget.vault, onConnect: _open),
                  for (final (i, session) in _sessions.indexed)
                    TerminalPanel(
                      key: ObjectKey(session),
                      session: session,
                      showKeyBar: widget.showKeyBar,
                      onReconnect: () => _open(session.target, replacing: i),
                    ),
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

    Widget tab({required bool on, required Widget child, required VoidCallback onTap, Key? key}) => Padding(
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
                on: i == selected,
                onTap: () => onSelect(i),
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
                    // A connection label is Latin content: always LTR.
                    Text(
                      session.target.label,
                      textDirection: TextDirection.ltr,
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
