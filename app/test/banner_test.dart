import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

void main() {
  test('a banner keeps its text and lines, and loses what would drive the terminal', () {
    expect(
      bannerText('Authorized use only\r\n\x1b[2J\x1b]0;owned\x07Be nice\tto it\n\n'),
      'Authorized use only\r\n[2J]0;ownedBe nice\tto it\r\n',
    );
    expect(bannerText('Café \u009b31m'), 'Café 31m\r\n', reason: 'C1 controls go too; other text stays');
    expect(bannerText('\n \n'), '', reason: 'nothing to show');
  });
}
