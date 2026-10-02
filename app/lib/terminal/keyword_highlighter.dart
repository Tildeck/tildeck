import 'dart:async';
import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

/// Words that stand out in the terminal: errors, warnings, and successes,
/// each with its color.
class KeywordRules {
  const KeywordRules({this.errors = defaultErrors, this.warnings = defaultWarnings, this.success = defaultSuccess});

  static const defaultErrors = [
    'error',
    'errors',
    'failed',
    'failure',
    'fatal',
    'denied',
    'refused',
    'panic',
    'exception',
    'critical',
  ];
  static const defaultWarnings = ['warning', 'warnings', 'warn', 'deprecated'];
  static const defaultSuccess = ['ok', 'success', 'succeeded', 'passed', 'done', 'active', 'running'];

  final List<String> errors;
  final List<String> warnings;
  final List<String> success;

  static const errorColor = Color(0xFFE5484D);
  static const warningColor = Color(0xFFF5A524);
  static const successColor = Color(0xFF30A46C);

  /// Each group's pattern, whole words, any case; groups without words are
  /// left out.
  List<(RegExp, Color)> get patterns => [
    for (final (words, color) in [(errors, errorColor), (warnings, warningColor), (success, successColor)])
      if (words.any((w) => w.trim().isNotEmpty))
        (
          RegExp(
            '(?<![\\w-])(?:${[for (final w in words)
              if (w.trim().isNotEmpty) RegExp.escape(w.trim())].join('|')})(?![\\w-])',
            caseSensitive: false,
          ),
          color,
        ),
  ];

  /// The hits in one line of text: where they start and end, and their color.
  static List<(int, int, Color)> find(String line, List<(RegExp, Color)> patterns) => [
    for (final (pattern, color) in patterns)
      for (final m in pattern.allMatches(line)) (m.start, m.end, color),
  ];
}

/// Marks the keywords in a terminal's newest lines as output arrives. Lines
/// already marked are left alone until their text changes, and the oldest
/// marks are released past a limit, so long output stays cheap.
class KeywordHighlighter {
  KeywordHighlighter(this.terminal, this.controller, KeywordRules rules) : _patterns = rules.patterns {
    terminal.addListener(_changed);
  }

  final Terminal terminal;
  final TerminalController controller;
  final List<(RegExp, Color)> _patterns;

  /// The text each marked line had, and its marks, oldest first.
  final _lines = LinkedHashMap<BufferLine, (String, List<TerminalHighlight>)>.identity();
  Timer? _timer;

  static const _maxLines = 2000;

  void _changed() {
    _timer ??= Timer(const Duration(milliseconds: 80), () {
      _timer = null;
      scan();
    });
  }

  /// Looks at the lines on the screen and a screen above it.
  void scan() {
    if (_patterns.isEmpty) return;
    final buffer = terminal.buffer;
    final lines = buffer.lines;
    final from = (lines.length - terminal.viewHeight * 2).clamp(0, lines.length);
    for (var y = from; y < lines.length; y++) {
      final line = lines[y];
      final text = line.getText();
      final known = _lines[line];
      if (known != null && known.$1 == text) continue;
      if (known != null) {
        for (final h in known.$2) {
          h.dispose();
        }
      }
      final marks = [
        for (final (start, end, color) in KeywordRules.find(text, _patterns))
          controller.highlight(
            p1: buffer.createAnchor(start, y),
            p2: buffer.createAnchor(end, y),
            color: color.withValues(alpha: 0.32),
          ),
      ];
      _lines.remove(line);
      _lines[line] = (text, marks);
    }
    while (_lines.length > _maxLines) {
      final oldest = _lines.keys.first;
      for (final h in _lines.remove(oldest)!.$2) {
        h.dispose();
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    terminal.removeListener(_changed);
    for (final (_, marks) in _lines.values) {
      for (final h in marks) {
        h.dispose();
      }
    }
    _lines.clear();
  }
}
