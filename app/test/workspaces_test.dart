import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

/// Real file work finishes outside the fake clock.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  test('a workspace keeps its hosts in order', () {
    const w = WorkspaceEntry(id: 'w', name: 'Morning', hostIds: ['b', 'a']);
    final back = VaultEntry.fromJson('w', w.type, w.dataJson())! as WorkspaceEntry;
    expect(back.name, 'Morning');
    expect(back.hostIds, ['b', 'a']);
  });

  testWidgets('a workspace opens its hosts in order, skipping deleted ones; removing it can be undone', (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-ws')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const HostEntry(id: 'a', name: 'Web', host: 'web.example.com', username: 'ops', password: 'pw'));
      await v.put(const HostEntry(id: 'b', name: 'Db', host: 'db.example.com', username: 'ops', password: 'pw'));
      await v.put(const WorkspaceEntry(id: 'w', name: 'Morning', hostIds: ['b', 'gone', 'a']));
      return v;
    }))!;
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: HostsPage(vault: vault, onConnect: (ConnectionTarget t) => opened.add(t.host)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning · 3'), findsOneWidget);
    await tester.tap(find.text('Morning · 3'));
    await waitFor(tester, () => opened.length == 2);
    expect(opened, ['db.example.com', 'web.example.com']);

    await tester.tap(find.byTooltip('Remove workspace'));
    await waitFor(tester, () => find.text('Undo').evaluate().isNotEmpty);
    expect(vault.workspaces, isEmpty);
    expect(find.text('Morning · 3'), findsNothing);
    await tester.tap(find.text('Undo'));
    await waitFor(tester, () => vault.workspaces.isNotEmpty);
    expect(vault.workspaces.single.hostIds, ['b', 'gone', 'a']);
  });
}
