import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../logo.dart';

/// From this window width, the app lays out as a desktop app: a sidebar,
/// with each section in place instead of one page over another. A wide
/// tablet gets it too; a narrow window gets the phone layout.
const desktopMinWidth = 900.0;

bool isDesktopLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopMinWidth;

/// Every section's bar in the desktop layout looks like one header: a
/// large title on the page, actions at the end, no shade.
Widget deskSectionTheme(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  final c = context.colors;
  return Theme(
    data: theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: c.page,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 80,
        titleSpacing: 28,
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: c.ink),
        actionsPadding: const EdgeInsetsDirectional.only(end: 20),
      ),
    ),
    child: child,
  );
}

/// The sections of the desktop layout's sidebar.
enum DeskSection { hosts, keys, identities, knownHosts, forwards, snippets, history, settings }

/// The desktop layout's navigation: the vault's sections, then the app's
/// own settings and the lock.
class DesktopSidebar extends StatelessWidget {
  const DesktopSidebar({
    super.key,
    required this.section,
    required this.sectionShown,
    required this.onSection,
    required this.onLock,
    required this.onToggleLocale,
    required this.onToggleTheme,
    required this.onShortcuts,
    required this.otherLanguageName,
  });

  final DeskSection section;

  /// False while a session is shown: no section is highlighted then.
  final bool sectionShown;
  final ValueChanged<DeskSection> onSection;
  final VoidCallback onLock;
  final VoidCallback onToggleLocale;
  final VoidCallback onToggleTheme;
  final VoidCallback onShortcuts;
  final String otherLanguageName;

  static const width = 232.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget item(DeskSection s, IconData icon, String label) {
      final on = sectionShown && section == s;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: on ? c.brand.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey('nav-${s.name}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSection(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: on ? c.brandBright : c.deskMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: on ? c.deskInk : c.deskMuted,
                        fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 16, 6),
      child: Text(
        text,
        style: TextStyle(color: c.deskMuted.withValues(alpha: 0.7), fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );

    // Compact, so the language beside them is never cut short.
    Widget action(Key key, IconData icon, String tooltip, VoidCallback onPressed) => IconButton(
      key: key,
      tooltip: tooltip,
      color: c.deskMuted,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
    );

    return Container(
      width: width,
      color: c.desk,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 16, 10),
              child: Row(
                children: [
                  TildeckLogo(tile: c.deskBright, stroke: c.desk, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    t.appName,
                    style: TextStyle(color: c.deskInk, fontWeight: FontWeight.w800, fontSize: 19),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  heading(t.navVault),
                  item(DeskSection.hosts, Icons.dns_outlined, t.hostsTitle),
                  item(DeskSection.keys, Icons.key_outlined, t.keysTitle),
                  item(DeskSection.identities, Icons.badge_outlined, t.identitiesTitle),
                  item(DeskSection.knownHosts, Icons.verified_user_outlined, t.knownHostsTitle),
                  item(DeskSection.forwards, Icons.swap_horiz_rounded, t.forwardsTitle),
                  item(DeskSection.snippets, Icons.code_rounded, t.snippetsTitle),
                  item(DeskSection.history, Icons.history_rounded, t.historyTitle),
                  heading(t.navSettings),
                  item(DeskSection.settings, Icons.settings_outlined, t.settingsTitle),
                ],
              ),
            ),
            Divider(height: 1, color: c.deskMuted.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  action(const ValueKey('lockVault'), Icons.lock_outline, t.lockNow, onLock),
                  action(
                    const ValueKey('toggleTheme'),
                    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    dark ? t.switchToLight : t.switchToDark,
                    onToggleTheme,
                  ),
                  action(const ValueKey('showShortcuts'), Icons.keyboard_outlined, t.keyboardShortcuts, onShortcuts),
                  // The other language, named in itself: a word, not an icon.
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        key: const ValueKey('toggleLanguage'),
                        style: TextButton.styleFrom(
                          foregroundColor: c.deskMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: onToggleLocale,
                        child: Text(otherLanguageName, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's keyboard shortcuts, listed.
Future<void> showShortcuts(BuildContext context) {
  final t = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.keyboardShortcuts),
      content: const SizedBox(width: 420, child: ShortcutsList()),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.close))],
    ),
  );
}

/// Each shortcut beside what it does.
class ShortcutsList extends StatelessWidget {
  const ShortcutsList({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final rows = [
      ('Ctrl+Shift+T', t.shortcutNewConnection),
      ('Ctrl+Shift+W', t.shortcutCloseTab),
      ('Ctrl+Tab', t.shortcutNextTab),
      ('Ctrl+Shift+Tab', t.shortcutPreviousTab),
      ('Ctrl+Shift+L', t.lockNow),
      ('Ctrl+Shift+C', t.shortcutCopy),
      ('Ctrl+Shift+V', t.shortcutPaste),
      ('Ctrl+Shift+F', t.shortcutFind),
      ('Ctrl+ +  /  Ctrl+ -', t.shortcutFontSize),
      ('Ctrl+Shift+P', t.paletteTitle),
      ('Ctrl+/', t.keyboardShortcuts),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (keys, what) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(what)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.page,
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      keys,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
