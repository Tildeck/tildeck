import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import '../logo.dart';

/// From this window width, the app lays out as a desktop app: a sidebar,
/// with each section in place instead of one page over another. A wide
/// tablet gets it too; a narrow window gets the phone layout.
const desktopMinWidth = 900.0;

bool isDesktopLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= desktopMinWidth;

/// The sections of the desktop layout's sidebar.
enum DeskSection { hosts, keys, knownHosts, forwards, snippets, history, appearance, account, password }

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
    required this.otherLanguageName,
  });

  final DeskSection section;

  /// False while a session is shown: no section is highlighted then.
  final bool sectionShown;
  final ValueChanged<DeskSection> onSection;
  final VoidCallback onLock;
  final VoidCallback onToggleLocale;
  final VoidCallback onToggleTheme;
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

    Widget action(Key key, IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(key: key, tooltip: tooltip, color: c.deskMuted, icon: Icon(icon, size: 20), onPressed: onPressed);

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
                  item(DeskSection.knownHosts, Icons.verified_user_outlined, t.knownHostsTitle),
                  item(DeskSection.forwards, Icons.swap_horiz_rounded, t.forwardsTitle),
                  item(DeskSection.snippets, Icons.code_rounded, t.snippetsTitle),
                  item(DeskSection.history, Icons.history_rounded, t.historyTitle),
                  heading(t.navSettings),
                  item(DeskSection.appearance, Icons.palette_outlined, t.terminalSettingsTitle),
                  item(DeskSection.account, Icons.cloud_sync_outlined, t.syncTitle),
                  item(DeskSection.password, Icons.password_rounded, t.navMasterPassword),
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
                  // The other language, named in itself: a word, not an icon.
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        key: const ValueKey('toggleLanguage'),
                        style: TextButton.styleFrom(foregroundColor: c.deskMuted),
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
