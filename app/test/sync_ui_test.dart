import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/app.dart';
import 'package:tildeck/server_check.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/sync/recovery_key.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

import 'fake_sync_server.dart';

const password = 'orange-kettle-winter-42';

void main() {
  late Directory dir;
  late FakeSyncServer server;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tildeck-sync-ui');
    server = FakeSyncServer();
  });
  tearDown(() => dir.delete(recursive: true));

  Widget app(Vault vault) => TildeckApp(
    key: ObjectKey(vault),
    vault: vault,
    commonPasswords: CommonPasswords({'1q2w3e4r5t6y'}),
    checker: ServerChecker(client: server.client),
    syncClient: server.client,
    connector: SshConnector(knownHosts: MemoryKnownHosts()),
    showKeyBar: false,
    initialLocale: const Locale('en'),
  );

  /// Real work (Argon2id in an isolate, file writes) completes outside the
  /// test's fake clock; let it run between frames until [done].
  Future<void> waitFor(WidgetTester tester, bool Function() done, String what) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (done()) return;
    }
    final error = find.byKey(const ValueKey('syncError'));
    fail('timed out waiting for $what${error.evaluate().isEmpty ? '' : ': ${tester.widget<Text>(error).data}'}');
  }

  bool shown(Finder f) => f.evaluate().isNotEmpty;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(key)));
  }

  Future<void> fillAccountForm(WidgetTester tester, {required String device}) async {
    await tester.enterText(find.byKey(const ValueKey('syncAddress')), 'https://sync.example.test');
    await tester.enterText(find.byKey(const ValueKey('syncEmail')), 'user@example.test');
    await tester.enterText(find.byKey(const ValueKey('syncPassword')), password);
    await tester.enterText(find.byKey(const ValueKey('syncDeviceName')), device);
  }

  testWidgets('register on one device, sign in on another, and the vault arrives once approved', (tester) async {
    // Tall enough that every screen of the flow is built whole.
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The first device has a vault with a host, and no account yet.
    final a = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/a.json'));
      await v.load();
      await v.create(password);
      await v.put(HostEntry(id: v.newId(), name: 'Database', host: 'db.example.com', username: 'ops'));
      return v;
    }))!;
    await tester.pumpWidget(app(a));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('openSync'))), 'the main screen');
    await tester.tap(find.byKey(const ValueKey('openSync')));
    await tester.pumpAndSettle();

    // A wrong master password is caught on the device, before any account exists.
    await fillAccountForm(tester, device: 'Office PC');
    await tester.enterText(find.byKey(const ValueKey('syncPassword')), 'not-the-master-password');
    await tap(tester, 'syncRegister');
    await waitFor(tester, () => shown(find.byKey(const ValueKey('syncError'))), 'the error');
    expect(find.text("That is not this vault's master password."), findsOneWidget);
    expect(server.account, isNull);

    await tester.enterText(find.byKey(const ValueKey('syncPassword')), password);
    await tap(tester, 'syncRegister');
    await waitFor(tester, () => shown(find.byKey(const ValueKey('recoveryKey'))), 'the recovery key');

    // The recovery key is shown once, is a valid key, and must be confirmed.
    final written = tester.widget<SelectableText>(find.byKey(const ValueKey('recoveryKey'))).data!;
    expect(RecoveryKeyCodec(await tester.runAsync(VaultCrypto.load) as VaultCrypto).decode(written), isNotNull);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('recoveryContinue'))).onPressed, isNull);
    await tap(tester, 'recoverySaved');
    await tester.pump();
    await tap(tester, 'recoveryContinue');
    await waitFor(tester, () => server.records.isNotEmpty && a.dirtyRecords.isEmpty, 'the first upload');
    await tester.pump();
    expect(find.text('Signed in as user@example.test'), findsOneWidget);
    expect(server.account!['auth_key'], isNot(contains(password)));

    // The second device has no vault: it signs in and waits for approval.
    final b = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/b.json'));
      await v.load();
      return v;
    }))!;
    await tester.pumpWidget(app(b));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('haveAccount'))), 'the create screen');
    await tap(tester, 'haveAccount');
    await tester.pumpAndSettle();
    await fillAccountForm(tester, device: 'Phone');
    await tap(tester, 'syncSignIn');
    await waitFor(tester, () => shown(find.text('Approve this device')), 'the approval screen');
    expect(b.status, VaultStatus.missing, reason: 'a pending device gets no vault');

    // Still waiting after a check; then approved from the first device.
    await tester.pump(const Duration(seconds: 5));
    await waitFor(tester, () => true, 'a check');
    expect(b.status, VaultStatus.missing);
    server.devices.values.firstWhere((d) => d['name'] == 'Phone')['status'] = 'active';
    await tester.pump(const Duration(seconds: 5));
    await waitFor(tester, () => b.status == VaultStatus.unlocked && b.hosts.isNotEmpty, 'the vault');
    await waitFor(tester, () => shown(find.text('Database')), 'the hosts list');
    expect(b.vaultId, a.vaultId);
  });

  testWidgets('a removed device signs in again as a new one and syncs once approved', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/a.json'));
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
      await v.setAccount(
        const SyncAccount(
          server: 'https://sync.example.test',
          email: 'user@example.test',
          deviceId: 'old-id',
          deviceName: 'Office PC',
          token: 'token-old',
        ),
      );
      return v;
    }))!;
    server.devices['old-id'] = {'id': 'old-id', 'name': 'Office PC', 'status': 'revoked', 'token': 'token-old'};

    await tester.pumpWidget(app(vault));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('openSync'))), 'the main screen');
    await tester.tap(find.byKey(const ValueKey('openSync')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('syncNow'))), 'the sync screen');
    await tap(tester, 'syncNow');
    await waitFor(tester, () => shown(find.byKey(const ValueKey('signInAgain'))), 'the signed-out state');
    expect(find.text('This device was signed out of the account. Sign in again to keep syncing.'), findsOneWidget);

    await tap(tester, 'signInAgain');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('signInAgainPassword')), password);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(tester, () => shown(find.text('Approve this device')), 'the approval screen');
    final waiting = server.devices.values.where((d) => d['status'] == 'pending').toList();
    expect(waiting, hasLength(1), reason: '${server.devices}');
    final fresh = waiting.single;
    expect(fresh['id'], isNot('old-id'), reason: 'a removed device comes back as a new one');

    fresh['status'] = 'active';
    await tester.pump(const Duration(seconds: 5));
    await waitFor(
      tester,
      () => vault.account?.deviceId == fresh['id'] && shown(find.byKey(const ValueKey('syncNow'))),
      'the new sign-in',
    );
    await tap(tester, 'syncNow');
    await waitFor(tester, () => shown(find.textContaining('Last synced')), 'a sync');
  });

  testWidgets('a signed-in device approves a waiting one', (tester) async {
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/a.json'));
      await v.load();
      await v.create(password);
      return v;
    }))!;
    server.account = {'email': 'user@example.test'};
    final me = server.devices['me'] = {'id': 'me', 'name': 'Office PC', 'status': 'active', 'token': 'token-a'};
    server.devices['phone'] = {'id': 'phone', 'name': 'Phone', 'status': 'pending', 'token': 'token-p'};
    await tester.runAsync(
      () => vault.setAccount(
        SyncAccount(
          server: 'https://sync.example.test',
          email: 'user@example.test',
          deviceId: me['id']!,
          deviceName: 'Office PC',
          token: 'token-a',
        ),
      ),
    );
    await tester.pumpWidget(app(vault));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('openSync'))), 'the main screen');
    await tester.tap(find.byKey(const ValueKey('openSync')));
    await waitFor(tester, () => shown(find.byKey(const ValueKey('approve-phone'))), 'the waiting device');
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('approve-phone')));
    await waitFor(tester, () => !shown(find.byKey(const ValueKey('approve-phone'))), 'the approval');
    expect(server.devices['phone']!['status'], 'active');
  });
}
