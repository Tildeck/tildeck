import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('the cursor position is reported counting from 1', () {
    final terminal = Terminal();
    final sent = <String>[];
    terminal.onOutput = sent.add;
    terminal.write('\x1b[6n');
    terminal.write('ab\r\ncd\x1b[6n');
    expect(sent, ['\x1b[1;1R', '\x1b[2;3R']);
  });
}
