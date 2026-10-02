import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/host_folders.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  test('folders are paths, shown parents first with the folders above them', () {
    expect(canonicalGroup(' Production / Web '), 'Production/Web');
    expect(canonicalGroup('a//b/'), 'a/b');
    expect(ancestorsOf('A/B/C'), ['A', 'A/B']);
    expect((depthOf('A/B/C'), leafOf('A/B/C')), (2, 'C'));
    expect(folderOrder(['Prod/Web', '', 'Dev', 'Prod/Db/Main', 'prod2']), [
      'Dev',
      'Prod',
      'Prod/Db',
      'Prod/Db/Main',
      'Prod/Web',
      'prod2',
      '',
    ]);
    final collapsed = {'Prod'};
    expect(headerHidden('Prod', collapsed), isFalse, reason: 'a folded folder still shows its name');
    expect(hostsHidden('Prod', collapsed), isTrue);
    expect(headerHidden('Prod/Web', collapsed), isTrue);
    final byFolder = {
      'Prod/Web': [1, 2],
      'Prod': [3],
      'Production': [4],
      '': [5],
    };
    expect(hostCountUnder('Prod', byFolder), 3, reason: 'not Production');
    expect(hostCountUnder('', byFolder), 1);
  });

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-folders'));
  tearDown(() => dir.delete(recursive: true));

  Future<Vault> openVault(WidgetTester tester) async => (await tester.runAsync(() async {
    final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
    await v.load();
    await v.create('orange-kettle-winter-42');
    await v.put(const KeyEntry(id: 'k1', name: 'Prod key', privateKey: 'KEY'));
    await v.put(const GroupEntry(id: 'g1', name: 'Prod', username: 'ops', keyId: 'k1', env: {'A': '1', 'B': '1'}));
    await v.put(const GroupEntry(id: 'g2', name: 'Prod/Web', username: 'web', env: {'B': '2'}));
    await v.put(
      const HostEntry(
        id: 'h1',
        name: 'Web 01',
        group: 'Prod/Web',
        host: 'web-01.example.com',
        username: '',
        auth: HostAuth.key,
        tags: ['nginx'],
      ),
    );
    await v.put(const HostEntry(id: 'h2', name: 'Db', group: 'Prod', host: 'db.example.com', username: 'root'));
    return v;
  }))!;

  testWidgets('a host takes its folder settings, then those of the folders above', (tester) async {
    final vault = await openVault(tester);
    final merged = vault.effectiveGroup('Prod/Web')!;
    expect((merged.username, merged.keyId), ('web', 'k1'));
    expect(merged.env, {'A': '1', 'B': '2'}, reason: 'variables add up, the nearest winning');
    expect(vault.effectiveGroup('Prod / Web / Deeper')!.username, 'web', reason: 'a folder without settings');
    expect(vault.effectiveGroup('Elsewhere'), isNull);

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final target = (await connectionTargetFor(context, vault, vault.entry<HostEntry>('h1')!))!;
    expect((target.username, target.privateKey), ('web', 'KEY'));
    expect(target.environment, {'A': '1', 'B': '2'});
  });

  Widget app(Vault vault) => MaterialApp(
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
      body: HostsPage(vault: vault, onConnect: (ConnectionTarget _) {}),
    ),
  );

  testWidgets('folders nest and fold; a host is duplicated with everything but its name', (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = await openVault(tester);
    await tester.pumpWidget(app(vault));
    await tester.pumpAndSettle();
    expect(find.text('Web  1'), findsOneWidget, reason: 'the folder by its own name, with its hosts');
    expect(find.text('Prod  2'), findsOneWidget, reason: 'counting the folders inside');
    expect(find.byKey(const ValueKey('host-h1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('folderToggle-Prod')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('host-h1')), findsNothing, reason: 'inside the folded folder');
    expect(find.byKey(const ValueKey('host-h2')), findsNothing);
    expect(find.byKey(const ValueKey('folderToggle-Prod/Web')), findsNothing);

    // A search shows matches in folded folders.
    await tester.enterText(find.byKey(const ValueKey('hostSearch')), 'nginx');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('host-h1')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('hostSearch')), '');
    await tester.tap(find.byKey(const ValueKey('folderToggle-Prod')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('hostMenu-h1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hostDuplicate')));
    for (var i = 0; i < 300 && find.byKey(const ValueKey('hostName')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final copy = vault.hosts.firstWhere((h) => h.name == 'Web 01 (copy)');
    expect((copy.group, copy.host, copy.auth), ('Prod/Web', 'web-01.example.com', HostAuth.key));
    expect(copy.tags, ['nginx']);
    expect(copy.id, isNot('h1'));
    expect(find.byKey(const ValueKey('hostName')), findsOneWidget, reason: 'the copy opens for editing');
  });
}
