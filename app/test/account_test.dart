import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/sync/account_service.dart';
import 'package:tildeck/sync/sync_engine.dart';
import 'package:tildeck/sync/sync_server.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

import 'fake_sync_server.dart';

const address = 'https://sync.example.test';
const email = 'user@example.test';
const password = 'orange-kettle-winter-42';
const newPassword = 'lantern-river-autumn-77';

late Directory dir;
late FakeSyncServer server;
final devices = <Device>[];

/// One device: its vault, sync engine, and account service.
class Device {
  Device(this.name)
    : vault = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/$name.json')) {
    engine = SyncEngine(
      vault: vault,
      serverFor: (a) => SyncServer(a, client: server.client),
      changeDelay: const Duration(days: 1),
      interval: const Duration(days: 1),
    );
    accounts = AccountService(vault: vault, engine: engine);
    devices.add(this);
  }

  final String name;
  final Vault vault;
  late final SyncEngine engine;
  late final AccountService accounts;

  Future<Device> load() async {
    await vault.load();
    return this;
  }

  /// Locks and unlocks again: true when [secret] opens the vault on disk.
  Future<bool> opensWith(String secret) async {
    vault.lock();
    final reopened = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/$name.json'));
    await reopened.load();
    final ok = await reopened.unlock(secret);
    if (ok) await vault.unlock(secret);
    return ok;
  }
}

/// The first device: a vault with a host, registered. Returns the recovery key.
Future<(Device, String)> registered() async {
  final a = await Device('a').load();
  await a.vault.create(password);
  await a.vault.put(HostEntry(id: a.vault.newId(), name: 'Database', host: 'db.example.com', username: 'ops'));
  final rk = await a.accounts.register(
    address: address,
    email: email,
    password: password,
    locale: 'en',
    deviceName: 'Office PC',
  );
  await a.engine.sync();
  return (a, rk);
}

/// A second device that signed in and was approved.
Future<Device> secondDevice() async {
  final b = await Device('b').load();
  final pending = (await b.accounts.signIn(address: address, email: email, password: password, deviceName: 'Phone'))!;
  server.devices[pending.pending.deviceId]!['status'] = 'active';
  expect(await pending.collect(), isTrue);
  await b.engine.sync();
  return b;
}

void main() {
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tildeck-account');
    server = FakeSyncServer();
  });
  tearDown(() async {
    // Unlocking starts a sync; let every one finish before the files go.
    for (final d in devices) {
      await d.engine.sync();
      d.engine.dispose();
    }
    devices.clear();
    await dir.delete(recursive: true);
  });

  test('changing the master password re-wraps the same vault and signs out the other devices', () async {
    final (a, _) = await registered();
    final b = await secondDevice();

    await expectLater(
      a.accounts.changePassword(current: 'not-the-password', newPassword: newPassword),
      throwsA(isA<WrongMasterPassword>()),
    );
    expect(server.passwordChanges, 0);

    await a.accounts.changePassword(current: password, newPassword: newPassword);
    expect(server.passwordChanges, 1);
    expect(await a.opensWith(password), isFalse);
    expect(await a.opensWith(newPassword), isTrue);
    expect(a.vault.hosts.single.name, 'Database', reason: 'the records were not touched');

    await b.engine.sync();
    expect(b.engine.problem, SyncProblem.signedOut, reason: 'the other device was signed out');
  });

  test('a device signing in after a password change elsewhere takes the new password', () async {
    final (a, _) = await registered();
    final b = await secondDevice();
    await a.accounts.changePassword(current: password, newPassword: newPassword, signOutOtherDevices: false);

    // Still signed in, B signs in again with the new password: its own vault
    // file then opens with the new password, not the old one.
    expect(await b.accounts.signIn(address: address, email: email, password: newPassword, deviceName: 'Phone'), isNull);
    expect(await b.opensWith(password), isFalse);
    expect(await b.opensWith(newPassword), isTrue);
  });

  test('weak key derivation settings from a server are refused before anything is derived or sent', () async {
    await registered();
    final c = await Device('c').load();
    for (final weak in [
      {'alg': 'argon2id13', 'ops': 1, 'mem': 67108864, 'salt': 'AAAAAAAAAAAAAAAAAAAAAA=='},
      {'alg': 'argon2id13', 'ops': 3, 'mem': 8192, 'salt': 'AAAAAAAAAAAAAAAAAAAAAA=='},
      {'alg': 'argon2id13', 'ops': 3, 'mem': 67108864, 'salt': 'AAAA'},
    ]) {
      server
        ..preloginKdf = weak
        ..paths.clear();
      await expectLater(
        c.accounts.signIn(address: address, email: email, password: password, deviceName: 'Laptop'),
        throwsA(isA<UnsafeKdf>()),
      );
      expect(
        server.paths.where((p) => p != '/api/info' && p != '/api/health/ready'),
        ['/api/account/prelogin'],
        reason: 'no key proving the password went out',
      );
    }
  });

  test('the recovery key sets a new password and opens the vault on a new device', () async {
    final (a, rk) = await registered();
    final c = await Device('c').load();

    final typo = '${rk.substring(0, rk.length - 1)}${rk.endsWith('0') ? '1' : '0'}';
    await expectLater(
      c.accounts.recover(
        address: address,
        email: email,
        recoveryKey: typo,
        newPassword: newPassword,
        deviceName: 'New laptop',
      ),
      throwsA(isA<InvalidRecoveryKey>()),
    );

    await c.accounts.recover(
      address: address,
      email: email,
      recoveryKey: rk.toLowerCase(),
      newPassword: newPassword,
      deviceName: 'New laptop',
    );
    expect(c.vault.status, VaultStatus.unlocked);
    await c.engine.sync();
    expect(c.vault.hosts.single.name, 'Database');
    expect(await c.opensWith(newPassword), isTrue);

    await a.engine.sync();
    expect(a.engine.problem, SyncProblem.signedOut, reason: 'recovery signs out every other device');
  });

  test('recovery on the device with the forgotten password opens its own vault file', () async {
    final (a, rk) = await registered();
    a.vault.lock();
    await a.accounts.recover(
      address: address,
      email: email,
      recoveryKey: rk,
      newPassword: newPassword,
      deviceName: 'Office PC',
    );
    expect(a.vault.status, VaultStatus.unlocked);
    expect(a.vault.hosts.single.name, 'Database');
    expect(await a.opensWith(password), isFalse);
    expect(await a.opensWith(newPassword), isTrue);
  });

  test('a device whose vault locks while it waits for approval keeps its own vault', () async {
    await registered();
    final b = await Device('b').load();
    await b.vault.create('a-different-password-1');
    await b.vault.put(HostEntry(id: b.vault.newId(), name: 'Only here', host: 'lab.example.com', username: 'me'));
    final pending = (await b.accounts.signIn(address: address, email: email, password: password, deviceName: 'Phone'))!;
    server.devices[pending.pending.deviceId]!['status'] = 'active';

    // Locked, the approval is not collected: collecting would consume it
    // and, before, replaced the vault file with the account's empty vault.
    b.vault.lock();
    expect(await pending.collect(), isFalse);
    expect(b.vault.status, VaultStatus.locked);

    // Opened again, the approval is collected and the vaults compared.
    expect(await b.vault.unlock('a-different-password-1'), isTrue);
    await expectLater(pending.collect(), throwsA(isA<DifferentVault>()));
    expect(b.vault.hosts.single.name, 'Only here');
    expect(b.vault.account, isNull);
  });

  test('with two-factor sign-in on, signing in, a password change, and recovery need the code', () async {
    final (a, rk) = await registered();
    await a.accounts.startTwoFactor();
    await expectLater(a.accounts.confirmTwoFactor('000000'), throwsA(isA<SyncFailure>()));
    await a.accounts.confirmTwoFactor('123 456');
    expect(await a.accounts.twoFactorEnabled(), isTrue);

    final b = await Device('b').load();
    Future<PendingDevice?> signIn([String? code]) =>
        b.accounts.signIn(address: address, email: email, password: password, deviceName: 'Phone', totpCode: code);
    await expectLater(signIn(), throwsA(isA<TotpRequired>()));
    await expectLater(signIn('999999'), throwsA(isA<WrongMasterPassword>()));
    expect(await signIn('123456'), isNotNull, reason: 'pending approval, past both factors');

    await expectLater(
      a.accounts.changePassword(current: password, newPassword: newPassword),
      throwsA(isA<TotpRequired>()),
    );
    expect(await a.opensWith(password), isTrue, reason: 'nothing changed');
    await a.accounts.changePassword(current: password, newPassword: newPassword, totpCode: '123456');
    expect(server.passwordChanges, 1);

    final c = await Device('c').load();
    Future<void> recover([String? code]) => c.accounts.recover(
      address: address,
      email: email,
      recoveryKey: rk,
      newPassword: password,
      deviceName: 'Laptop',
      totpCode: code,
    );
    await expectLater(recover(), throwsA(isA<TotpRequired>()));
    expect(c.vault.status, VaultStatus.missing);
    await recover('123456');
    expect(c.vault.status, VaultStatus.unlocked);

    await c.accounts.disableTwoFactor('123456');
    expect(await c.accounts.twoFactorEnabled(), isFalse);
  });

  test('a device holding another vault is refused before anything changes on the server', () async {
    final (_, rk) = await registered();
    final other = await Device('other').load();
    await other.vault.create('a-different-password-1');
    final activeBefore = server.devices.values.where((d) => d['status'] == 'active').length;
    await expectLater(
      other.accounts.recover(
        address: address,
        email: email,
        recoveryKey: rk,
        newPassword: newPassword,
        deviceName: 'x',
      ),
      throwsA(isA<DifferentVault>()),
    );
    expect(server.devices.values.where((d) => d['status'] == 'active').length, activeBefore);
  });
}
