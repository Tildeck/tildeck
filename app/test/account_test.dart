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
  tearDown(() => dir.delete(recursive: true));

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
