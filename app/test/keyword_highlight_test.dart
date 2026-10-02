import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/terminal/keyword_highlighter.dart';
import 'package:tildeck/terminal/terminal_options.dart';
import 'package:tildeck/vault/models.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('keywords match whole words in any case, each group in its color', () {
    final patterns = const KeywordRules().patterns;
    final hits = KeywordRules.find('ERROR: build failed, 2 warnings; tests passed. errorlog no-ok', patterns);
    expect(
      [
        for (final (s, e, c) in hits)
          (('ERROR: build failed, 2 warnings; tests passed. errorlog no-ok').substring(s, e), c),
      ],
      [
        ('ERROR', KeywordRules.errorColor),
        ('failed', KeywordRules.errorColor),
        ('warnings', KeywordRules.warningColor),
        ('passed', KeywordRules.successColor),
      ],
      reason: '"errorlog" and "no-ok" are not the words',
    );
    expect(
      KeywordRules.find('a.b+c (x)', const KeywordRules(errors: ['a.b+c'], warnings: [], success: []).patterns),
      hasLength(1),
      reason: 'words are matched as written, not as patterns',
    );
  });

  test('the preferences choose the words, or turn highlighting off', () {
    expect(TerminalOptions.of(const PreferencesEntry()).keywords!.errors, KeywordRules.defaultErrors);
    expect(TerminalOptions.of(const PreferencesEntry(highlight: false)).keywords, isNull);
    final custom = TerminalOptions.of(
      const PreferencesEntry(highlightErrors: ['boom'], highlightSuccess: []),
    ).keywords!;
    expect(custom.errors, ['boom']);
    expect(custom.patterns, hasLength(2), reason: 'a group without words is left out');
  });

  test('new output is marked, a changed line is marked again, an unchanged one is not', () async {
    final terminal = Terminal(maxLines: 100);
    final controller = TerminalController();
    final highlighter = KeywordHighlighter(terminal, controller, const KeywordRules());
    addTearDown(highlighter.dispose);
    terminal.write('build ok\r\nerror: disk full\r\n');
    highlighter.scan();
    expect(controller.highlights, hasLength(2));
    highlighter.scan();
    expect(controller.highlights, hasLength(2), reason: 'nothing new, nothing added');
    terminal.write('warning: low memory');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(controller.highlights, hasLength(3), reason: 'scanned on its own after output');
    highlighter.dispose();
    expect(controller.highlights, isEmpty);
  });
}
