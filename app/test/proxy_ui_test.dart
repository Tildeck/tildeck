import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/proxy.dart';
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
  testWidgets('a proxy is added from the host editor, chosen, and used to connect', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-proxy')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const HostEntry(id: 'h1', name: 'Web', host: 'web.example.com', username: 'ops', password: 'pw'));
      return v;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: HostEditorPage(vault: vault, host: vault.entry<HostEntry>('h1')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('addProxy')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('proxyName')), 'Office');
    await tester.tap(find.text('HTTP'));
    await tester.enterText(find.byKey(const ValueKey('proxyHost')), 'proxy.example.com');
    await tester.enterText(find.byKey(const ValueKey('proxyPort')), '3128');
    await tester.tap(find.byKey(const ValueKey('saveProxy')));
    await waitFor(tester, () => find.byKey(const ValueKey('saveProxy')).evaluate().isEmpty);

    final proxy = vault.proxies.single;
    expect(proxy.kind, ProxyKind.http);
    expect(proxy.username, isNull, reason: 'no credentials unless given');
    // The new proxy is chosen for the host, which can now be saved with it.
    expect(find.byKey(const ValueKey('editProxy')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('saveHost')));
    await tester.tap(find.byKey(const ValueKey('saveHost')));
    await waitFor(tester, () => vault.entry<HostEntry>('h1')!.proxyId != null);
    expect(vault.entry<HostEntry>('h1')!.proxyId, proxy.id);

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
    expect(target.proxy?.host, 'proxy.example.com');
    expect(target.proxy?.port, 3128);
  });
}
