import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/local/local_names.dart';

void main() {
  test('a server name becomes one safe name here, never a path or a step up', () {
    // The attack: a Linux name that Windows reads as a path up and out.
    const escape = r'..\..\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\x.cmd';
    final name = localNameFor(escape);
    expect(name, isNot(contains(r'\')));
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains(':')));
    expect(localNameFor('a/b'), 'a_b');
    expect(localNameFor('C:evil'), 'C_evil', reason: 'a drive or a data stream');
    expect(localNameFor('report.txt:hidden'), 'report.txt_hidden');
    expect(localNameFor('tab\there'), 'tab_here');
    expect(localNameFor('..'), '__');
    expect(localNameFor('.'), '_');
    expect(localNameFor(''), '_');
    expect(localNameFor('notes. '), 'notes__', reason: 'Windows would drop the trailing dot and space');
    for (final device in ['CON', 'con', 'NUL.txt', 'com1', 'LPT9.log', 'aux.tar.gz']) {
      expect(localNameFor(device), '_$device', reason: device);
    }
    // Ordinary names are kept as they are.
    for (final ok in ['.bashrc', 'app-v1.4.2.tar.gz', 'דוח.pdf', 'Console.txt', 'COM10']) {
      expect(localNameFor(ok), ok);
    }
  });

  test('a path is checked to stay inside its folder', () {
    final root = Directory.systemTemp.path;
    final sep = Platform.pathSeparator;
    expect(isInside(root, '$root${sep}a${sep}b'), isTrue);
    expect(isInside(root, root), isTrue);
    expect(isInside(root, '$root$sep..${sep}x'), isFalse);
    expect(isInside(root, '${root}2${sep}x'), isFalse, reason: 'a sibling that starts the same');
    expect(isInside('$root${sep}a', '$root${sep}b'), isFalse);
  });
}
