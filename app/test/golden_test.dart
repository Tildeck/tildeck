// Golden images of the app shell in English LTR and Hebrew RTL, light and
// dark, rendered with the bundled Heebo font. They are the reviewable
// screenshots of the shell: test/goldens/*.png.
//
// Regenerate after an intended visual change, inside the Flutter toolchain
// container: flutter test --update-goldens test/golden_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';

Future<void> loadFonts() async {
  final heebo = FontLoader('Heebo');
  for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
    heebo.addFont(File('assets/fonts/Heebo-$weight.ttf').readAsBytes().then(ByteData.sublistView));
  }
  await heebo.load();

  // Material icons ship with the SDK; tests otherwise draw them as boxes.
  final sdk =
      Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
  }
}

final readyServer = MockClient((request) async {
  final body = request.url.path == '/api/info'
      ? {'name': 'tildeck', 'version': '0.1.0', 'protocol_version': kProtocolVersion}
      : {'status': 'ok', 'database': 'ok', 'error': null};
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
});

void main() {
  setUpAll(loadFonts);

  for (final locale in ['en', 'he']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('home $locale ${mode.name}', (tester) async {
        // A common Android phone: 412x915 logical pixels.
        tester.view.physicalSize = const Size(412 * 2, 915 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          TildeckApp(
            checker: ServerChecker(client: readyServer),
            initialLocale: Locale(locale),
            initialThemeMode: mode,
          ),
        );
        await tester.pumpAndSettle();

        // Show the shell after a successful check, the state with the most
        // on screen.
        await tester.enterText(find.byType(TextField), 'https://sync.example.com');
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();

        final dir = tester.widget<Directionality>(find.byType(Directionality).first).textDirection;
        expect(dir, locale == 'he' ? TextDirection.rtl : TextDirection.ltr);
        // The address stays LTR in both languages.
        expect(tester.widget<TextField>(find.byType(TextField)).textDirection, TextDirection.ltr);

        await expectLater(find.byType(TildeckApp), matchesGoldenFile('goldens/home_${locale}_${mode.name}.png'));
      });
    }
  }
}
