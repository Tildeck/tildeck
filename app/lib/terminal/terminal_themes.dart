import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// A named terminal color scheme the user can pick.
class NamedTheme {
  const NamedTheme(this.id, this.name, this.theme, {this.light = false});

  final String id;
  final String name;
  final TerminalTheme theme;

  /// A light background, for the preview list.
  final bool light;
}

/// A theme from its background, foreground, cursor, and the 16 ANSI colors
/// (normal then bright, in black, red, green, yellow, blue, magenta, cyan,
/// white order).
TerminalTheme _scheme(int background, int foreground, int cursor, List<int> ansi) {
  assert(ansi.length == 16);
  Color c(int v) => Color(0xFF000000 | v);
  return TerminalTheme(
    cursor: c(cursor),
    selection: c(cursor).withValues(alpha: 0.35),
    foreground: c(foreground),
    background: c(background),
    black: c(ansi[0]),
    red: c(ansi[1]),
    green: c(ansi[2]),
    yellow: c(ansi[3]),
    blue: c(ansi[4]),
    magenta: c(ansi[5]),
    cyan: c(ansi[6]),
    white: c(ansi[7]),
    brightBlack: c(ansi[8]),
    brightRed: c(ansi[9]),
    brightGreen: c(ansi[10]),
    brightYellow: c(ansi[11]),
    brightBlue: c(ansi[12]),
    brightMagenta: c(ansi[13]),
    brightCyan: c(ansi[14]),
    brightWhite: c(ansi[15]),
    searchHitBackground: const Color(0xFFFBBF24),
    searchHitBackgroundCurrent: const Color(0xFF2DD4BF),
    searchHitForeground: const Color(0xFF0B181B),
  );
}

/// The schemes on offer. The first is the default. The palettes are the
/// published ones of each scheme.
final terminalThemes = <NamedTheme>[
  NamedTheme(
    'tildeck-dark',
    'Tildeck Dark',
    _scheme(0x0B181B, 0xE7F4F2, 0x5EEAD4, [
      0x1B2B2F, 0xF87171, 0x4ADE80, 0xFBBF24, 0x60A5FA, 0xF472B6, 0x2DD4BF, 0xD5E3E1, //
      0x5B7075, 0xFCA5A5, 0x86EFAC, 0xFDE68A, 0x93C5FD, 0xF9A8D4, 0x5EEAD4, 0xFFFFFF,
    ]),
  ),
  NamedTheme(
    'tildeck-light',
    'Tildeck Light',
    _scheme(0xF7FBFA, 0x14262A, 0x0F766E, [
      0x14262A, 0xB91C1C, 0x15803D, 0xA16207, 0x1D4ED8, 0xBE185D, 0x0F766E, 0xA3B8B5, //
      0x54666B, 0xDC2626, 0x16A34A, 0xCA8A04, 0x2563EB, 0xDB2777, 0x0D9488, 0xD5E3E1,
    ]),
    light: true,
  ),
  NamedTheme(
    'solarized-dark',
    'Solarized Dark',
    _scheme(0x002B36, 0x839496, 0x93A1A1, [
      0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5, //
      0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
    ]),
  ),
  NamedTheme(
    'solarized-light',
    'Solarized Light',
    _scheme(0xFDF6E3, 0x657B83, 0x586E75, [
      0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5, //
      0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
    ]),
    light: true,
  ),
  NamedTheme(
    'nord',
    'Nord',
    _scheme(0x2E3440, 0xD8DEE9, 0xD8DEE9, [
      0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0, //
      0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B, 0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4,
    ]),
  ),
  NamedTheme(
    'gruvbox-dark',
    'Gruvbox Dark',
    _scheme(0x282828, 0xEBDBB2, 0xEBDBB2, [
      0x282828, 0xCC241D, 0x98971A, 0xD79921, 0x458588, 0xB16286, 0x689D6A, 0xA89984, //
      0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F, 0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2,
    ]),
  ),
  NamedTheme(
    'one-dark',
    'One Dark',
    _scheme(0x282C34, 0xABB2BF, 0x528BFF, [
      0x282C34, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xABB2BF, //
      0x5C6370, 0xE06C75, 0x98C379, 0xE5C07B, 0x61AFEF, 0xC678DD, 0x56B6C2, 0xFFFFFF,
    ]),
  ),
  NamedTheme(
    'monokai',
    'Monokai',
    _scheme(0x272822, 0xF8F8F2, 0xF8F8F0, [
      0x272822, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF8F8F2, //
      0x75715E, 0xF92672, 0xA6E22E, 0xF4BF75, 0x66D9EF, 0xAE81FF, 0xA1EFE4, 0xF9F8F5,
    ]),
  ),
  NamedTheme(
    'dracula',
    'Dracula',
    _scheme(0x282A36, 0xF8F8F2, 0xF8F8F2, [
      0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C, 0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2, //
      0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5, 0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
    ]),
  ),
  NamedTheme(
    'github-light',
    'GitHub Light',
    _scheme(0xFFFFFF, 0x24292F, 0x0969DA, [
      0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781, //
      0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F,
    ]),
    light: true,
  ),
];

NamedTheme themeById(String? id) => terminalThemes.firstWhere((t) => t.id == id, orElse: () => terminalThemes.first);

const minFontSize = 9.0;
const maxFontSize = 28.0;
const defaultFontSize = 14.0;
