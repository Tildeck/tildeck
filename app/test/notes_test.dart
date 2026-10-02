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

void main() {
  test('notes are kept, searched, and empty on a host from before', () {
    const host = HostEntry(id: 'h', name: 'Db', host: 'db', username: 'ops', notes: 'Ask Dana before restarting');
    expect(HostEntry.fromJson('h', host.dataJson()).notes, 'Ask Dana before restarting');
    expect(HostEntry.fromJson('h', {'name': 'Old', 'host': 'x', 'username': 'u'}).notes, '');
    expect(hostMatches(host, 'dana'), isTrue);
  });

  testWidgets('a folder opens all its hosts, the ones in folders inside it too', (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-notes')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/v.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      for (final (id, group) in [('a', 'Prod'), ('b', 'Prod/Web'), ('c', 'Dev')]) {
        await v.put(HostEntry(id: id, name: id, group: group, host: '$id.example.com', username: 'ops', password: 'x'));
      }
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
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: HostsPage(vault: vault, onConnect: (ConnectionTarget target) => opened.add(target.host)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('openFolder-Prod')));
    await tester.pumpAndSettle();
    expect(opened.toSet(), {'a.example.com', 'b.example.com'});
  });
}
