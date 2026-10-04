import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/keys_page.dart';
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
  testWidgets('a PuTTY key is pasted, asks for its passphrase, and is saved as OpenSSH', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-ppk')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      return v;
    }))!;
    final ppk = File('test/fixtures/ppk/rsa-v3-argon2i.ppk').readAsStringSync();
    final fingerprint = File('test/fixtures/ppk/rsa-v3-argon2i.fp').readAsStringSync().trim().split(' ').last;
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showKeyEditor(context, vault), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('keyName')), 'Work (PuTTY)');
    await tester.enterText(find.byKey(const ValueKey('keyPem')), ppk);
    await tester.tap(find.byKey(const ValueKey('saveKey')));
    await tester.pumpAndSettle();
    expect(find.text('This PuTTY key is protected: enter its passphrase.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('keyPassphrase')), 'wrong');
    await tester.tap(find.byKey(const ValueKey('saveKey')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
    expect(find.text('The passphrase does not open this PuTTY key.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('keyPassphrase')), 'tildeck-test');
    await tester.tap(find.byKey(const ValueKey('saveKey')));
    await waitFor(tester, () => vault.keys.isNotEmpty);
    final key = vault.keys.single;
    expect(key.fingerprint, fingerprint);
    expect(key.privateKey, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
    expect(key.passphrase, isNull, reason: 'the vault keeps it; it needs none of its own there');
  });
}
