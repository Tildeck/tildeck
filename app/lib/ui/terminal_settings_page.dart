import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../terminal/terminal_themes.dart';
import '../theme.dart';
import '../vault/vault.dart';

/// How terminals look: the color scheme and the font size. Kept in the
/// vault's preferences record, so every device follows.
class TerminalSettingsPage extends StatelessWidget {
  const TerminalSettingsPage({super.key, required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(t.terminalSettingsTitle)),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final prefs = vault.preferences;
          final current = themeById(prefs.terminalTheme);
          final size = prefs.fontSize ?? defaultFontSize;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  _Preview(theme: current.theme, fontSize: size),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(t.fontSizeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Text(
                        '${size.round()}',
                        key: const ValueKey('fontSizeValue'),
                        style: TextStyle(color: c.muted),
                      ),
                    ],
                  ),
                  Slider(
                    key: const ValueKey('fontSize'),
                    value: size,
                    min: minFontSize,
                    max: maxFontSize,
                    divisions: (maxFontSize - minFontSize).round(),
                    label: '${size.round()}',
                    onChanged: (v) => vault.put(prefs.copyWith(fontSize: v.roundToDouble())),
                  ),
                  Text(t.fontSizeHelp, style: TextStyle(color: c.muted, fontSize: 13)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const ValueKey('autocompleteSwitch'),
                    contentPadding: EdgeInsets.zero,
                    value: prefs.autocomplete ?? true,
                    onChanged: (v) => vault.put(prefs.copyWith(autocomplete: v)),
                    title: Text(t.autocompleteLabel),
                    subtitle: Text(t.autocompleteHelp, style: TextStyle(color: c.muted, fontSize: 13)),
                  ),
                  const SizedBox(height: 24),
                  Text(t.terminalThemeLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final theme in terminalThemes)
                        _ThemeChip(
                          theme: theme,
                          selected: theme.id == current.id,
                          onTap: () => vault.put(prefs.copyWith(terminalTheme: theme.id)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A few lines of a shell in the chosen scheme and size.
class _Preview extends StatelessWidget {
  const _Preview({required this.theme, required this.fontSize});

  final TerminalTheme theme;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    TextSpan span(String text, Color color, {bool bold = false}) => TextSpan(
      text: text,
      style: TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        key: const ValueKey('terminalPreview'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: theme.background, borderRadius: BorderRadius.circular(14)),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: fontSize, height: 1.3, color: theme.foreground),
            children: [
              span('deploy@web-01', theme.green, bold: true),
              span(':', theme.foreground),
              span('~/app', theme.blue, bold: true),
              span(r'$ ', theme.foreground),
              span('git status\n', theme.foreground),
              span('On branch ', theme.foreground),
              span('main\n', theme.cyan),
              span('modified:   ', theme.red),
              span('config/nginx.conf\n', theme.red),
              span('warning: ', theme.yellow, bold: true),
              span('2 files changed\n', theme.foreground),
              span('deploy@web-01', theme.green, bold: true),
              span(':', theme.foreground),
              span('~/app', theme.blue, bold: true),
              span(r'$ ', theme.foreground),
              span(' ', theme.foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({required this.theme, required this.selected, required this.onTap});

  final NamedTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = theme.theme;
    return InkWell(
      key: ValueKey('theme-${theme.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: s.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? c.brand : c.line, width: selected ? 3 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    theme.name,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: s.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                if (selected) Icon(Icons.check_circle, size: 16, color: s.cursor),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final color in [s.red, s.green, s.yellow, s.blue, s.magenta, s.cyan])
                  Expanded(child: Container(height: 8, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
