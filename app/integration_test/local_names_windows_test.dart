// Names from a server on Windows itself, where "\" and ":" are separators:
// run with `scripts\windows.ps1 test`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tildeck/local/local_browser.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a hostile name from a server is written inside the folder, on Windows', (tester) async {
    final root = await Directory.systemTemp.createTemp('tildeck-names');
    addTearDown(() => root.delete(recursive: true));
    final inner = await Directory('${root.path}\\target').create();
    final local = LocalBrowser(home: inner.path);
    await local.start();

    for (final name in [r'..\escape.cmd', r'..\..\escape.cmd', 'C:escape.cmd', 'CON', 'notes. ']) {
      final path = local.unusedPath(name);
      await File(path).writeAsString('x');
      expect(File(path).parent.absolute.path.toLowerCase(), inner.absolute.path.toLowerCase(), reason: name);
    }
    // Nothing reached the folder above.
    expect(root.listSync().map((e) => e.path), [inner.path]);
    expect(inner.listSync(), hasLength(5));
  }, skip: !Platform.isWindows);
}
