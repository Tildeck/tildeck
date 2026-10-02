import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/sync/account_service.dart';
import 'package:tildeck/sync/sync_engine.dart';
import 'package:tildeck/sync/sync_server.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/account_page.dart';
import 'package:tildeck/ui/two_factor.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

import 'fake_sync_server.dart';

const password = 'orange-kettle-winter-42';

void main() {
  late Directory dir;
  late FakeSyncServer server;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tildeck-2fa');
    server = FakeSyncServer();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> waitFor(WidgetTester tester, bool Function() done, String what) async {
    for (var i = 0; i < 1000; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
      if (done()) return;
    }
    final error = find.byKey(const ValueKey('syncError'));
    fail('timed out waiting for $what${error.evaluate().isEmpty ? '' : ': ${tester.widget<Text>(error).data}'}');
  }

  bool shown(Finder f) => f.evaluate().isNotEmpty;

  /// A vault on this device, and the account on the server holding it.
  Future<Vault> accountVault(WidgetTester tester, String name) async => (await tester.runAsync(() async {
    final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/$name.json'));
    await v.load();
    await v.create(password);
    final keys = (await v.passwordKeys(password))!;
    server.account = {
      'email': 'user@example.test',
      'auth_key': base64.encode(keys.authKey.extractBytes()),
      'vault_id': v.vaultId,
      'kdf': {'alg': 'argon2id13', 'ops': v.kdf.opsLimit, 'mem': v.kdf.memLimit, 'salt': base64.encode(v.kdf.salt)},
      'wrap_pw': {'nonce': base64.encode(v.wrapPw.nonce), 'ct': base64.encode(v.wrapPw.ciphertext)},
    };
    keys.dispose();
    return v;
  }))!;

  testWidgets('signing in asks for the code when the account has two-factor sign-in', (tester) async {
    tester.view.physicalSize = const Size(860, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await accountVault(tester, 'a');
    server.totpEnabled = true;

    final b = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/b.json'));
      await v.load();
      return v;
    }))!;
    await tester.pumpWidget(
      TildeckApp(
        vault: b,
        commonPasswords: CommonPasswords({}),
        checker: ServerChecker(client: server.client),
        syncClient: server.client,
        connector: SshConnector(knownHosts: MemoryKnownHosts()),
        showKeyBar: false,
        initialLocale: const Locale('en'),
      ),
    );
    await waitFor(tester, () => shown(find.byKey(const ValueKey('haveAccount'))), 'the create screen');
    await tester.tap(find.byKey(const ValueKey('haveAccount')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('syncAddress')), 'https://sync.example.test');
    await tester.enterText(find.byKey(const ValueKey('syncEmail')), 'user@example.test');
    await tester.enterText(find.byKey(const ValueKey('syncPassword')), password);
    await tester.enterText(find.byKey(const ValueKey('syncDeviceName')), 'Phone');
    await tester.tap(find.byKey(const ValueKey('syncSignIn')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpCode'))), 'the code question');

    // A wrong code is refused like a wrong password.
    await tester.enterText(find.byKey(const ValueKey('totpCode')), '999999');
    await tester.tap(find.byKey(const ValueKey('totpCodeContinue')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('syncError'))), 'the error');

    await tester.tap(find.byKey(const ValueKey('syncSignIn')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpCode'))), 'the code question again');
    await tester.enterText(find.byKey(const ValueKey('totpCode')), '123 456');
    await tester.tap(find.byKey(const ValueKey('totpCodeContinue')));
    await waitFor(tester, () => shown(find.text('Approve this device')), 'the approval screen');
  });

  testWidgets('two-factor sign-in is turned on with a code from the scanned secret, and off with one', (tester) async {
    final vault = await accountVault(tester, 'a');
    final engine = SyncEngine(
      vault: vault,
      serverFor: (address) => SyncServer(address, client: server.client),
      changeDelay: const Duration(days: 1),
      interval: const Duration(days: 1),
    );
    addTearDown(engine.dispose);
    final services = SyncServices(
      vault: vault,
      engine: engine,
      accounts: AccountService(vault: vault, engine: engine),
      checker: ServerChecker(client: server.client),
      commonPasswords: CommonPasswords({}),
    );
    await tester.runAsync(
      () => vault.setAccount(
        const SyncAccount(
          server: 'https://sync.example.test',
          email: 'user@example.test',
          deviceId: 'device-a',
          deviceName: 'Laptop',
          token: 'token-a',
        ),
      ),
    );
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
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: TwoFactorSettings(services: services),
          ),
        ),
      ),
    );
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpTurnOn'))), 'the switch');
    expect(find.byKey(const ValueKey('totpOn')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('totpTurnOn')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpQr'))), 'the QR code');
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('totpCode')), '000000');
    await tester.tap(find.byKey(const ValueKey('totpConfirm')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpSetupError'))), 'the wrong code');
    expect(server.totpEnabled, isFalse);
    await tester.enterText(find.byKey(const ValueKey('totpCode')), '123456');
    await tester.tap(find.byKey(const ValueKey('totpConfirm')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpOn'))), 'on');
    expect(server.totpEnabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('totpTurnOff')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('totpCode')), '123456');
    await tester.tap(find.byKey(const ValueKey('totpCodeContinue')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('totpTurnOn'))), 'off');
    expect(server.totpEnabled, isFalse);
  });
}
