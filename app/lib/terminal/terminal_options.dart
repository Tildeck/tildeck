import 'dart:io';

import 'package:xterm/xterm.dart';

import '../vault/models.dart';

enum BellMode { none, visual, sound }

/// A monospace font: the bundled one, or one the system has.
typedef TerminalFont = ({String family, String label});

/// The fonts offered: JetBrains Mono ships with the app; the others are
/// the system's own monospace fonts, which every install of the system has.
List<TerminalFont> terminalFonts({bool? windows, bool? android}) => [
  (family: 'JetBrainsMono', label: 'JetBrains Mono'),
  if (windows ?? Platform.isWindows) ...[
    (family: 'Cascadia Mono', label: 'Cascadia Mono'),
    (family: 'Consolas', label: 'Consolas'),
    (family: 'Courier New', label: 'Courier New'),
  ],
  if (android ?? Platform.isAndroid) (family: 'monospace', label: 'Droid Sans Mono'),
];

const scrollbackChoices = [1000, 5000, 10000, 50000];
const minLineHeight = 1.0, maxLineHeight = 1.6;

/// The terminal's look and behavior from the vault's preferences, with the
/// defaults for what is not chosen, and only valid values: preferences
/// sync from other devices and versions.
class TerminalOptions {
  const TerminalOptions({
    this.fontFamily = 'JetBrainsMono',
    this.lineHeight = 1.2,
    this.cursor = TerminalCursorType.block,
    this.bell = BellMode.visual,
    this.scrollback = 10000,
    this.copyOnSelect = false,
  });

  factory TerminalOptions.of(PreferencesEntry prefs) {
    final lineHeight = prefs.lineHeight;
    return TerminalOptions(
      fontFamily: prefs.fontFamily ?? 'JetBrainsMono',
      lineHeight: lineHeight == null || lineHeight < minLineHeight || lineHeight > maxLineHeight ? 1.2 : lineHeight,
      cursor: switch (prefs.cursorStyle) {
        'underline' => TerminalCursorType.underline,
        'bar' => TerminalCursorType.verticalBar,
        _ => TerminalCursorType.block,
      },
      bell: BellMode.values.where((b) => b.name == prefs.bell).firstOrNull ?? BellMode.visual,
      scrollback: scrollbackChoices.contains(prefs.scrollback) ? prefs.scrollback! : 10000,
      copyOnSelect: prefs.copyOnSelect ?? false,
    );
  }

  final String fontFamily;
  final double lineHeight;
  final TerminalCursorType cursor;
  final BellMode bell;
  final int scrollback;
  final bool copyOnSelect;

  /// The bundled font behind a system one that is missing.
  List<String> get fontFallback => fontFamily == 'JetBrainsMono' ? const [] : const ['JetBrainsMono'];
}
