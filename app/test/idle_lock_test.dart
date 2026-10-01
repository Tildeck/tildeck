import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/activity.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/vault_gate.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  testWidgets('typing into a terminal keeps the vault open; idling locks it', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-idle')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
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
        home: VaultGate(
          vault: vault,
          commonPasswords: CommonPasswords({}),
          unlocked: (_) => const Scaffold(body: Text('open')),
        ),
      ),
    );
    // The gate starts its timer when the vault changes; a touch starts it here.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    // Soft keyboard typing reaches a terminal without key events or touches.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(minutes: 10));
      userActivity.ping();
    }
    await tester.pump();
    expect(vault.status, VaultStatus.unlocked, reason: '30 minutes of typing, never 15 idle');

    await tester.pump(const Duration(minutes: 15, seconds: 1));
    expect(vault.status, VaultStatus.locked);
  });
}
