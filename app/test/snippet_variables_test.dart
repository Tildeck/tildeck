import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/snippet_variables.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/snippets_page.dart';
import 'package:tildeck/vault/models.dart';

void main() {
  test('variables are found once each, in order, and filled in', () {
    const command = 'sudo systemctl restart {{service}} && journalctl -u {{ service }} -n {{lines}} # {{not a var}}';
    expect(variablesIn(command), ['service', 'lines']);
    expect(
      fillVariables(command, {'service': 'nginx', 'lines': '50'}),
      'sudo systemctl restart nginx && journalctl -u nginx -n 50 # {{not a var}}',
    );
    expect(fillVariables('echo {{x}}', {}), 'echo {{x}}', reason: 'no value: as written');
    expect(variablesIn('uptime'), isEmpty);
  });

  testWidgets('running a snippet asks for its variables, and offers the last values', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    const snippet = SnippetEntry(id: 's1', name: 'Restart', command: 'systemctl restart {{service}}');
    var result = snippetCommandToRun(context, snippet);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('variable-service')), 'nginx');
    await tester.tap(find.byKey(const ValueKey('runWithVariables')));
    await tester.pumpAndSettle();
    expect(await result, 'systemctl restart nginx');

    result = snippetCommandToRun(context, snippet);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('variable-service'))).controller!.text, 'nginx');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull, reason: 'cancelled: nothing runs');

    expect(await snippetCommandToRun(context, const SnippetEntry(id: 's2', name: 'Up', command: 'uptime')), 'uptime');
  });
}
