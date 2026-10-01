import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/autocomplete.dart';

void main() {
  test('history comes from bash, zsh, and fish files, newest last, each command once', () {
    final history = parseHistory(
      [
        'ls -la',
        ': 1700000000:0;git status',
        '- cmd: docker ps',
        '  when: 1700000001',
        '#1700000002',
        'ls -la',
        '',
        'sudo systemctl restart nginx',
      ].join('\n'),
    );
    expect(history, ['git status', 'docker ps', 'ls -la', 'sudo systemctl restart nginx']);
  });

  test('suggestions: snippets first, then commands that start with the text, then ones that contain it', () {
    final history = ['git status', 'git log --oneline', 'tail -f /var/log/git.log', 'git status'];
    final s = suggest('git', history, snippets: {'git-pull-all': 'git pull --all'});
    expect(s.map((x) => x.command), ['git pull --all', 'git status', 'git log --oneline', 'tail -f /var/log/git.log']);
    expect(s.first.snippetName, 'git-pull-all');
    expect(suggest('g', history), isEmpty, reason: 'one character is too little');
    expect(suggest('git status', history).map((x) => x.command), isNot(contains('git status')));
  });

  test('the typed line is followed through typing, Backspace, Ctrl+U, and Enter', () {
    final line = LineTracker()..feed('sudo systemctl');
    expect(line.line, 'sudo systemctl');
    line.feed('\x7f\x7f');
    expect(line.line, 'sudo systemc');
    line.feed('\x15');
    expect(line.line, '');
    line.feed('ls\x1b[A');
    expect(line.line, isNull, reason: 'history recall changes the line unseen');
    line.feed('\r');
    expect(line.line, '');
    line.feed('cd /e\t');
    expect(line.line, isNull, reason: 'Tab completion changes the line unseen');
  });

  test('completing continues the typed text, or replaces it', () {
    expect(completionInput('git st', 'git status'), 'atus');
    expect(completionInput('log', 'tail -f /var/log/app.log'), '\x15tail -f /var/log/app.log');
  });

  test('password prompts are recognized, and other lines are not', () {
    for (final prompt in [
      '[sudo] password for ops: ',
      'Password:',
      "Enter passphrase for key '/home/ops/.ssh/id_ed25519': ",
      'root@db.example.com\'s password: ',
    ]) {
      expect(isPasswordPrompt(prompt), isTrue, reason: prompt);
    }
    for (final line in ['passwd: password updated successfully', r'ops@web:~$ ', 'Password changed.']) {
      expect(isPasswordPrompt(line), isFalse, reason: line);
    }
  });
}
