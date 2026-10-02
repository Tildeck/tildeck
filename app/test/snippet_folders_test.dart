import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/snippets_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  test('a snippet keeps its folder; one from before folders has none', () {
    const s = SnippetEntry(id: 's', name: 'Restart', command: 'x', folder: 'Nginx');
    expect(SnippetEntry.fromJson('s', s.dataJson()).folder, 'Nginx');
    expect(SnippetEntry.fromJson('s', {'name': 'Old', 'command': 'x'}).folder, '');
  });

  testWidgets('snippets are listed by folder, and the editor saves a folder', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-snippets')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const SnippetEntry(id: 's1', name: 'Restart', command: 'systemctl restart nginx', folder: 'Nginx'));
      await v.put(const SnippetEntry(id: 's2', name: 'Uptime', command: 'uptime'));
      return v;
    }))!;
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
        home: SnippetsPage(vault: vault),
      ),
    );
    await tester.pumpAndSettle();
    final nginx = tester.getTopLeft(find.byKey(const ValueKey('snippetFolder-Nginx'))).dy;
    final none = tester.getTopLeft(find.byKey(const ValueKey('snippetFolder-'))).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('snippet-Restart'))).dy, greaterThan(nginx));
    expect(tester.getTopLeft(find.byKey(const ValueKey('snippet-Uptime'))).dy, greaterThan(none));
    expect(none, greaterThan(nginx), reason: 'the snippets in no folder last');

    await tester.tap(find.byKey(const ValueKey('snippet-Uptime')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('snippetFolder')), 'System');
    await tester.tap(find.byKey(const ValueKey('saveSnippet')));
    for (var i = 0; i < 300 && find.byKey(const ValueKey('saveSnippet')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(vault.entry<SnippetEntry>('s2')!.folder, 'System');
    expect(find.byKey(const ValueKey('snippetFolder-System')), findsOneWidget);
    expect(find.byKey(const ValueKey('snippetFolder-')), findsNothing, reason: 'no snippet left without a folder');
  });
}
