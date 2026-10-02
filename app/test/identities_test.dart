import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/ui/identities_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

Widget app(Widget home) => MaterialApp(
  theme: buildTheme(Brightness.light),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-identities'));
  tearDown(() => dir.delete(recursive: true));

  Future<Vault> openVault(WidgetTester tester) async => (await tester.runAsync(() async {
    final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
    await v.load();
    await v.create('orange-kettle-winter-42');
    await v.put(const KeyEntry(id: 'k1', name: 'Deploy key', privateKey: 'KEY-MATERIAL'));
    await v.put(const IdentityEntry(id: 'i-key', name: 'Deploy', username: 'deploy', keyId: 'k1'));
    await v.put(const IdentityEntry(id: 'i-pw', name: 'Admin', username: 'admin', password: 'admin-secret'));
    await v.put(const GroupEntry(id: 'g1', name: 'Production', identityId: 'i-key', username: 'ops'));
    return v;
  }))!;

  testWidgets("an identity decides who signs in: the host's, else the group's", (tester) async {
    final vault = await openVault(tester);
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

    // No identity of its own: the group's, over the group's username.
    const inGroup = HostEntry(id: 'h1', name: 'Web', group: 'Production', host: 'web.example.com', username: 'root');
    var target = (await connectionTargetFor(context, vault, inGroup))!;
    expect((target.username, target.privateKey, target.password), ('deploy', 'KEY-MATERIAL', null));

    // Its own identity wins over the group's.
    final own = HostEntry.fromJson('h2', {...inGroup.dataJson(), 'identity_id': 'i-pw'});
    target = (await connectionTargetFor(context, vault, own))!;
    expect((target.username, target.privateKey, target.password), ('admin', null, 'admin-secret'));

    // Changing the identity changes every host that uses it.
    await tester.runAsync(
      () => vault.put(const IdentityEntry(id: 'i-pw', name: 'Admin', username: 'root', password: 'new-secret')),
    );
    target = (await connectionTargetFor(context, vault, own))!;
    expect((target.username, target.password), ('root', 'new-secret'));

    // A deleted identity leaves the host's own fields.
    await tester.runAsync(() async {
      await vault.delete('i-pw');
      await vault.put(const GroupEntry(id: 'g1', name: 'Production'));
    });
    const plain = HostEntry(
      id: 'h3',
      name: 'Plain',
      group: 'Production',
      host: 'p.example.com',
      username: 'me',
      password: 'mine',
      identityId: 'i-pw',
    );
    target = (await connectionTargetFor(context, vault, plain))!;
    expect((target.username, target.password), ('me', 'mine'));
  });

  testWidgets('identities are added in their page, and one in use is not deleted', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = await openVault(tester);
    await tester.pumpWidget(app(IdentitiesPage(vault: vault)));
    await tester.pumpAndSettle();
    expect(find.text('deploy, key Deploy key · no hosts'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('addIdentity')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('identityName')), 'Backup');
    await tester.enterText(find.byKey(const ValueKey('identityUsername')), 'backup');
    await tester.tap(find.byKey(const ValueKey('saveIdentity')));
    // Saving encrypts off the test clock.
    for (var i = 0; i < 500 && find.byKey(const ValueKey('saveIdentity')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(vault.identities.map((x) => x.name), ['Admin', 'Backup', 'Deploy']);
    expect(find.text('backup, password asked each time · no hosts'), findsOneWidget);

    // Deploy is the group's identity: it stays.
    await tester.tap(find.byKey(const ValueKey('deleteIdentity-Deploy')));
    await tester.pumpAndSettle();
    expect(find.text('Hosts or groups use this identity. Choose another for them first.'), findsOneWidget);
    expect(vault.identities.length, 3);
  });

  testWidgets('a host that chooses an identity hides its own credentials and saves the choice', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = await openVault(tester);
    await tester.pumpWidget(app(HostEditorPage(vault: vault)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('username')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('hostName')), 'Box');
    await tester.enterText(find.byKey(const ValueKey('host')), 'box.example.com');
    await tester.tap(find.byKey(const ValueKey('hostIdentity')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('username')), findsNothing);
    expect(find.text('admin, saved password'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('saveHost')));
    for (var i = 0; i < 500 && find.byKey(const ValueKey('saveHost')).evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(vault.hosts.single.identityId, 'i-pw');
  });
}
