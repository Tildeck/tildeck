import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

void main() {
  test('a banner keeps its text and lines, and loses what would drive the terminal', () {
    expect(
      bannerText('Authorized use only\r\n\x1b[2J\x1b]0;owned\x07Be \x1b[1;31mnice\x1b[0m\tto it\x1b(B\n\n'),
      'Authorized use only\r\nBe nice\tto it\r\n',
    );
    expect(bannerText('Café \u009b31mok\x07'), 'Café ok\r\n', reason: 'C1 sequences and BEL go too');
    expect(bannerText('\n \n'), '', reason: 'nothing to show');
  });
}
