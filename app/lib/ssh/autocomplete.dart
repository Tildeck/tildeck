/// Autocomplete for a shell: suggestions from the server's own history,
/// read over a separate exec channel and never stored here, and from the
/// user's snippets. The line being typed is followed only to filter the
/// suggestions; it is kept in memory and forgotten at Enter.
library;

/// Reads the server's history files. Any failure (a server that refuses
/// exec channels, a shell without history) just means no suggestions.
const historyCommand =
    r'cat ~/.bash_history ~/.zsh_history ~/.local/share/fish/fish_history 2>/dev/null | tail -n 3000';

/// The most commands kept from the history.
const maxHistory = 2000;

/// Commands from bash, zsh (extended `: 1700000000:0;command` lines), and
/// fish (`- cmd: command` lines) history, newest last, without duplicates
/// (a repeated command keeps its newest place).
List<String> parseHistory(String text) {
  final commands = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    var line = raw;
    final zsh = RegExp(r'^: \d+:\d+;').firstMatch(line);
    if (zsh != null) line = line.substring(zsh.end);
    if (line.startsWith('- cmd: ')) line = line.substring(7);
    if (line.startsWith('  when: ') || line.startsWith('  paths:') || line.startsWith('    - ')) continue;
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    commands.add(line);
  }
  final seen = <String>{};
  final newestFirst = <String>[];
  for (final c in commands.reversed) {
    if (seen.add(c)) newestFirst.add(c);
    if (newestFirst.length == maxHistory) break;
  }
  return newestFirst.reversed.toList();
}

/// A suggestion: a command and where it came from.
class Suggestion {
  const Suggestion(this.command, {this.snippetName});

  final String command;

  /// Set when the suggestion is a snippet.
  final String? snippetName;
}

/// Up to [limit] suggestions for [typed]: snippets whose name or command
/// starts with it, then history commands that start with it (newest
/// first), then history commands that contain it. Nothing for fewer than
/// two typed characters, or for a typed line that is already a whole
/// suggestion.
List<Suggestion> suggest(String typed, List<String> history, {Map<String, String> snippets = const {}, int limit = 4}) {
  final needle = typed.trimLeft();
  if (needle.length < 2) return const [];
  final lower = needle.toLowerCase();
  final out = <Suggestion>[];
  final seen = <String>{needle};
  void add(Suggestion s) {
    if (out.length < limit && seen.add(s.command)) out.add(s);
  }

  for (final e in snippets.entries) {
    if (e.key.toLowerCase().startsWith(lower) || e.value.toLowerCase().startsWith(lower)) {
      add(Suggestion(e.value, snippetName: e.key));
    }
  }
  for (final c in history.reversed) {
    if (c.startsWith(needle)) add(Suggestion(c));
  }
  for (final c in history.reversed) {
    if (c.toLowerCase().contains(lower)) add(Suggestion(c));
  }
  return out;
}

/// Follows what is being typed on the current shell line, from the bytes
/// the terminal sends. Anything it cannot follow (arrow keys, history
/// recall, completion) makes the line unknown until Enter, and an unknown
/// line gets no suggestions.
class LineTracker {
  String _line = '';
  bool _known = true;

  /// The line as typed, or null when it is not known.
  String? get line => _known ? _line : null;

  void reset() {
    _line = '';
    _known = true;
  }

  void feed(String data) {
    for (final rune in data.runes) {
      switch (rune) {
        case 0x0d || 0x0a: // Enter
          reset();
        case 0x7f || 0x08: // Backspace
          if (_line.isNotEmpty) _line = String.fromCharCodes(_line.runes.toList()..removeLast());
        case 0x15 || 0x03: // Ctrl+U clears the line, Ctrl+C abandons it
          reset();
        case 0x09 || 0x1b: // Tab completion and escape sequences change it unseen
          _known = false;
        default:
          if (rune >= 0x20) {
            _line += String.fromCharCode(rune);
          } else {
            _known = false;
          }
      }
    }
  }
}

/// The input that turns [typed] into [command]: the rest of it when it
/// continues what was typed, or Ctrl+U and the whole command otherwise.
/// It never presses Enter: the user runs it.
String completionInput(String typed, String command) =>
    command.startsWith(typed) ? command.substring(typed.length) : '\x15$command';

/// Whether the cursor's line asks for a password (sudo, su, ssh, passwd,
/// and the like), so the saved password can be offered.
bool isPasswordPrompt(String line) =>
    RegExp(r'(password|passphrase|passcode)[^:]{0,40}:$', caseSensitive: false).hasMatch(line.trimRight());
