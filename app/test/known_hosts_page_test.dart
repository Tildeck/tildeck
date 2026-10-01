import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/known_hosts_page.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('trusted keys are listed; one removed asks again on the next connection, and comes back on undo', (
    tester,
  ) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-known')))!;
    addTearDown(() => dir.delete(recursive: true));
    const key = KnownHost(type: 'ssh-ed25519', fingerprint: 'SHA256:3kDbQ0yq8pZs1m8o5kqf2m5bN7r0A9dEo6wQz1cX4sY');
    final (vault, known) = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      final known = VaultKnownHosts(v);
      await known.trust('db.example.com', 2222, key);
      await known.trust('web.example.com', 22, key);
      return (v, known);
    }))!;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: KnownHostsPage(vault: vault),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('knownHost-db.example.com:2222')), findsOneWidget);
    expect(find.byKey(const ValueKey('knownHost-web.example.com')), findsOneWidget, reason: 'port 22 is not written');
    expect(find.textContaining(key.fingerprint), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('forget-web.example.com')));
    await waitFor(tester, () => find.text('Undo').evaluate().isNotEmpty);
    expect(vault.knownHosts, hasLength(1));
    expect(find.byKey(const ValueKey('knownHost-web.example.com')), findsNothing);
    expect((await tester.runAsync(() => known.check('web.example.com', 22, key)))!, HostKeyStatus.unknown);

    await tester.tap(find.text('Undo'));
    await waitFor(tester, () => vault.knownHosts.length == 2);
    expect((await tester.runAsync(() => known.check('web.example.com', 22, key)))!, HostKeyStatus.trusted);
  });
}
