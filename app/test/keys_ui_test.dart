import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/keys.dart';
import 'package:tildeck/ssh/local_files.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/keys_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

/// Files in a temporary folder, and one file to pick for import.
class TempFiles implements LocalFiles {
  TempFiles(this.dir, {this.toPick});
  final Directory dir;
  final (String, String)? toPick;

  @override
  Future<List<PickedFile>> pickToUpload() async => [
    if (toPick case (final name, final text)) PickedFile(name, text.length, () => Stream.value(utf8.encode(text))),
  ];

  @override
  Future<File> downloadTarget(String name) async => File('${dir.path}/$name');

  @override
  Future<String?> keep(File downloaded, String name) async => downloaded.path;
}

Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a key is generated, its public key copied, exported with a passphrase, and one imported from a file', (
    tester,
  ) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-keys')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      return v;
    }))!;
    final other = generateEd25519(vault.crypto.sodium, 'other');
    final protectedOther = exportKey(other, newPassphrase: 'pp');
    final files = TempFiles(dir, toPick: ('id_ed25519_work', protectedOther));

    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: KeysPage(vault: vault, files: files),
      ),
    );
    await tester.pumpAndSettle();

    // Generate.
    await tester.tap(find.byKey(const ValueKey('addKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generateKey')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('keyName')), 'Laptop');
    await tester.tap(find.byKey(const ValueKey('generate')));
    await waitFor(tester, () => find.byKey(const ValueKey('generate')).evaluate().isEmpty);
    final key = vault.keys.single;
    expect(key.keyType, 'ssh-ed25519');
    expect(key.publicKey, startsWith('ssh-ed25519 '));
    expect(find.textContaining(key.fingerprint!), findsOneWidget);

    // Copy the public key.
    await tester.tap(find.byKey(const ValueKey('keyMenu-Laptop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('installKey')), findsNothing, reason: 'no way to connect here');
    await tester.tap(find.byKey(const ValueKey('copyPublicKey')));
    await tester.pumpAndSettle();
    expect(clipboard, key.publicKey);

    // Export with a passphrase.
    await tester.tap(find.byKey(const ValueKey('keyMenu-Laptop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('exportKey')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('exportPassphrase')), 'file-secret');
    await tester.tap(find.byKey(const ValueKey('saveExport')));
    final exported = File('${dir.path}/id_ed25519_laptop');
    await waitFor(tester, () => find.textContaining('Saved to').evaluate().isNotEmpty);
    final text = (await tester.runAsync(exported.readAsString))!;
    expect(readKey(text), isNull, reason: 'protected');
    expect(readKey(text, passphrase: 'file-secret')!.fingerprint, key.fingerprint);

    // Import from a file: refused without its passphrase, taken with it.
    await tester.tap(find.byKey(const ValueKey('addKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('importKey')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('keyFromFile')));
    await waitFor(tester, () => find.text('id_ed25519_work').evaluate().isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('saveKey')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('keyProblem')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('keyPassphrase')), 'pp');
    await tester.tap(find.byKey(const ValueKey('saveKey')));
    await waitFor(tester, () => find.byKey(const ValueKey('saveKey')).evaluate().isEmpty);
    final imported = vault.entry<KeyEntry>(vault.keys.firstWhere((k) => k.name == 'id_ed25519_work').id)!;
    expect(imported.fingerprint, readKey(other)!.fingerprint);
    expect(imported.passphrase, 'pp');
  });
}
