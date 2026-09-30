import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/sync/recovery_key.dart';
import 'package:tildeck/sync/sync_engine.dart';
import 'package:tildeck/sync/sync_server.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

import 'fake_sync_server.dart';

const password = 'orange-kettle-winter-42';
const address = 'https://sync.example.test';

late Directory dir;
late FakeSyncServer server;

/// A controllable clock per device, so conflicts have a known newer side.
class Clock {
  DateTime now = DateTime.utc(2026, 9, 30, 12);
  DateTime call() => now;
  void tick([Duration by = const Duration(minutes: 1)]) => now = now.add(by);
}

class Device {
  Device(this.name, this.vault, this.clock, this.engine);

  final String name;
  final Vault vault;
  final Clock clock;
  final SyncEngine engine;

  File get file => File('${dir.path}/$name.json');
  Map<String, dynamic> readFile() => jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  Future<void> sync() => engine.sync();
}

SyncEngine engineFor(Vault vault) => SyncEngine(
  vault: vault,
  serverFor: (a) => SyncServer(a, client: server.client),
  // Only explicit syncs in these tests.
  changeDelay: const Duration(days: 1),
  interval: const Duration(days: 1),
);

Vault vaultAt(String name, Clock clock) =>
    Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/$name.json'), clock: clock.call);

SyncAccount accountFor(String token) => SyncAccount(
  server: address,
  email: 'user@example.test',
  deviceId: VaultCrypto.newId(),
  deviceName: token,
  token: token,
);

/// The first device: a new vault, signed in.
Future<Device> firstDevice() async {
  final clock = Clock();
  final vault = vaultAt('a', clock);
  await vault.load();
  await vault.create(password);
  await vault.setAccount(accountFor('token-a'));
  return Device('a', vault, clock, engineFor(vault));
}

/// Another device of the same account: the vault from the server's keys,
/// opened with the master password, as after sign-in.
Future<Device> secondDevice(Device first) async {
  final clock = Clock();
  final vault = vaultAt('b', clock);
  await vault.load();
  final crypto = await VaultCrypto.load();
  final keys = await crypto.deriveKeys(password, first.vault.kdf);
  final vaultKey = crypto.unwrapVaultKey(keys.keyEncryptionKey, first.vault.wrapPw, first.vault.vaultId);
  keys.dispose();
  await vault.adopt(
    vaultId: first.vault.vaultId,
    kdf: first.vault.kdf,
    wrapPw: first.vault.wrapPw,
    vaultKey: vaultKey,
    account: accountFor('token-b'),
  );
  return Device('b', vault, clock, engineFor(vault));
}

HostEntry host(String id, String name) => HostEntry(id: id, name: name, host: 'db.example.com', username: 'ops');

void main() {
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tildeck-sync');
    server = FakeSyncServer();
  });
  tearDown(() => dir.delete(recursive: true));

  test('two devices converge: additions, edits, and deletions reach each other', () async {
    final a = await firstDevice();
    final hostId = a.vault.newId(), keyId = a.vault.newId();
    await a.vault.put(host(hostId, 'Database'));
    await a.vault.put(KeyEntry(id: keyId, name: 'Laptop', privateKey: 'secret'));
    await a.sync();
    expect(a.vault.dirtyRecords, isEmpty);
    expect(a.engine.problem, isNull);

    final b = await secondDevice(a);
    await b.sync();
    expect(b.vault.hosts.single.name, 'Database');
    expect(b.vault.keys.single.privateKey, 'secret');

    await b.vault.put(host(hostId, 'Primary database'));
    await b.vault.delete(keyId);
    await b.sync();
    await a.sync();
    expect(a.vault.hosts.single.name, 'Primary database');
    expect(a.vault.keys, isEmpty);
    expect(server.records[keyId]!['deleted'], isTrue, reason: 'a deletion is kept as a tombstone');
    expect(server.records[keyId]!['ct'], isNull);
  });

  test('the server never receives plaintext', () async {
    final a = await firstDevice();
    await a.vault.put(host(a.vault.newId(), 'Very secret name'));
    String? sent;
    server.duringPush = () async => sent = jsonEncode(server.records);
    await a.sync();
    final stored = jsonEncode(server.records);
    for (final text in [stored, sent ?? '']) {
      expect(text.contains('Very secret name'), isFalse);
      expect(text.contains('db.example.com'), isFalse);
    }
  });

  test('a conflict goes to the newer edit, on both devices', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    await a.vault.put(host(id, 'Original'));
    await a.sync();
    final b = await secondDevice(a);
    await b.sync();

    // B edits later than A, but A reaches the server first.
    await a.vault.put(host(id, 'Edit from A'));
    b.clock.tick(const Duration(hours: 1));
    await b.vault.put(host(id, 'Edit from B'));
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.vault.hosts.single.name, 'Edit from B');
    expect(b.vault.hosts.single.name, 'Edit from B');

    // Now the device that pushes last holds the older edit: it gives way.
    a.clock.tick(const Duration(hours: 2));
    await a.vault.put(host(id, 'Newer from A'));
    await a.sync();
    await b.vault.put(host(id, 'Older from B'));
    await b.sync();
    await a.sync();
    expect(b.vault.hosts.single.name, 'Newer from A');
    expect(a.vault.hosts.single.name, 'Newer from A');
    expect([a.vault.dirtyRecords, b.vault.dirtyRecords], [isEmpty, isEmpty]);
  });

  test('an edit wins against a concurrent deletion, so no edit is lost', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    await a.vault.put(host(id, 'Original'));
    await a.sync();
    final b = await secondDevice(a);
    await b.sync();

    await a.vault.delete(id);
    await b.vault.put(host(id, 'Still needed'));
    await a.sync();
    await b.sync();
    await a.sync();
    expect(a.vault.hosts.single.name, 'Still needed');
    expect(b.vault.hosts.single.name, 'Still needed');
  });

  test('an edit made while its earlier version is on the way is not lost', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    await a.vault.put(host(id, 'First'));
    server.duringPush = () async {
      server.duringPush = null;
      a.clock.tick();
      await a.vault.put(host(id, 'Second'));
    };
    await a.sync();
    // The first push stored "First"; the second edit went in a later round
    // of the same sync, as the next version.
    expect(server.pushes, greaterThan(1));
    expect(server.records[id]!['version'], 2);
    expect(a.vault.dirtyRecords, isEmpty);

    final b = await secondDevice(a);
    await b.sync();
    expect(b.vault.hosts.single.name, 'Second');
  });

  test('a vault used before it had an account uploads whole, from any local version', () async {
    final a = await firstDevice();
    await a.vault.setAccount(null);
    final id = a.vault.newId();
    await a.vault.put(host(id, 'v1'));
    // Local versions go up while nothing is accepted: simulate an old vault
    // file whose records were at higher versions.
    final j = a.readFile();
    (j['records'] as List).cast<Map<String, dynamic>>().single
      ..['version'] = 1
      ..['dirty'] = false;
    a.file.writeAsStringSync(jsonEncode(j));
    final reopened = vaultAt('a', a.clock);
    await reopened.load();
    await reopened.unlock(password);
    await reopened.put(host(id, 'v2'));
    await reopened.setAccount(accountFor('token-a'));
    expect(reopened.dirtyRecords.single.version, 2);

    await engineFor(reopened).sync();
    expect(server.records[id]!['version'], 1, reason: 'a record new to the server starts at version 1');
    expect(reopened.dirtyRecords, isEmpty);
    final b = await secondDevice(Device('a', reopened, a.clock, a.engine));
    await b.sync();
    expect(b.vault.hosts.single.name, 'v2');
  });

  test('a format 1 vault file loads as never synced', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    await a.vault.put(host(id, 'Old'));
    final j = a.readFile()
      ..['format'] = 1
      ..remove('cursor')
      ..remove('account');
    for (final r in (j['records'] as List).cast<Map<String, dynamic>>()) {
      r.remove('dirty');
    }
    a.file.writeAsStringSync(jsonEncode(j));
    final old = vaultAt('a', a.clock);
    await old.load();
    expect(await old.unlock(password), isTrue);
    expect(old.cursor, 0);
    expect(old.account, isNull);
    expect(old.dirtyRecords.map((r) => r.id), [id]);
    expect(old.hosts.single.name, 'Old');
  });

  test('a server record that does not decrypt is reported and replaces nothing', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    await a.vault.put(host(id, 'Good'));
    await a.sync();
    final b = await secondDevice(a);
    await b.sync();

    // The server (or someone in its place) changes the ciphertext.
    final ct = base64.decode(server.records[id]!['ct'] as String);
    ct[0] ^= 1;
    server.records[id]!
      ..['ct'] = base64.encode(ct)
      ..['version'] = 2
      ..['revision'] = ++server.revision;
    await b.sync();
    expect(b.vault.hosts.single.name, 'Good');
    expect(b.vault.damaged, [id]);
  });

  test('a stored version never goes down', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    await a.vault.put(host(id, 'v1'));
    await a.sync();
    await a.vault.put(host(id, 'v2'));
    await a.sync();
    final v1 = Map<String, dynamic>.of(server.records[id]!);

    // Replay version 1 with a newer revision, as a server rolled back might.
    final b = await secondDevice(a);
    await b.sync();
    server.records[id] = {...v1, 'revision': ++server.revision};
    await b.sync();
    expect(b.vault.hosts.single.name, 'v2');
  });

  test('a server restored from a backup still takes the next change', () async {
    final a = await firstDevice();
    final id = a.vault.newId();
    for (final name in ['v1', 'v2', 'v3']) {
      a.clock.tick();
      await a.vault.put(host(id, name));
      await a.sync();
    }
    final older = {...server.records[id]!, 'version': 1};
    // The restored server knows only version 1, from before the backup.
    server.records[id] = older;
    a.clock.tick();
    await a.vault.put(host(id, 'after restore'));
    await a.sync();
    expect(a.vault.dirtyRecords, isEmpty);
    expect(server.records[id]!['version'], 2);
    final b = await secondDevice(a);
    await b.sync();
    expect(b.vault.hosts.single.name, 'after restore');
  });

  test('a large vault pulls in pages', () async {
    final a = await firstDevice();
    for (var i = 0; i < 7; i++) {
      await a.vault.put(host(a.vault.newId(), 'Host $i'));
    }
    await a.sync();
    server.pullLimit = 3;
    final b = await secondDevice(a);
    await b.sync();
    expect(b.vault.hosts, hasLength(7));
    expect(b.vault.cursor, server.revision);
  });

  test('sync reports what stops it', () async {
    final a = await firstDevice();
    await a.vault.put(host(a.vault.newId(), 'x'));
    server.refuse = 'email_not_verified';
    await a.sync();
    expect(a.engine.problem, SyncProblem.emailNotConfirmed);
    expect(a.vault.dirtyRecords, hasLength(1));

    server.refuse = null;
    server.tokens.remove('token-a');
    await a.sync();
    expect(a.engine.problem, SyncProblem.signedOut);

    server.tokens.add('token-a');
    await a.sync();
    expect(a.engine.problem, isNull);
    expect(a.vault.dirtyRecords, isEmpty);
  });

  test('the device token is sealed in the vault file and returns on unlock', () async {
    final a = await firstDevice();
    expect(a.file.readAsStringSync().contains('token-a'), isFalse);
    expect(a.file.readAsStringSync().contains('user@example.test'), isFalse);
    a.vault.lock();
    expect(a.vault.account, isNull);
    await a.vault.unlock(password);
    expect(a.vault.account!.token, 'token-a');
  });

  test('recovery keys: written with a checksum, forgiving of case and look-alike letters', () async {
    final crypto = await VaultCrypto.load();
    final codec = RecoveryKeyCodec(crypto);
    final key = crypto.newRecoveryKey();
    final written = codec.encode(key);
    expect(written.replaceAll('-', ''), hasLength(RecoveryKeyCodec.length));
    expect(written.split('-').first, hasLength(4));
    expect(codec.decode(written), key);
    expect(codec.decode(written.toLowerCase().replaceAll('-', ' ')), key);
    expect(codec.decode(written.replaceAll('0', 'O').replaceAll('1', 'I')), key);

    // One wrong character is caught before any network request.
    final chars = written.split('');
    final i = chars.indexWhere((c) => c != '-');
    chars[i] = chars[i] == 'A' ? 'B' : 'A';
    expect(codec.decode(chars.join()), isNull);
    expect(codec.decode(written.substring(0, written.length - 1)), isNull);
    expect(codec.decode('${written}U'), isNull);

    final keys = crypto.recoveryKeys(Uint8List.fromList(key));
    final again = crypto.recoveryKeys(codec.decode(written)!);
    expect(keys.authKey.extractBytes(), again.authKey.extractBytes());
    expect(keys.authKey.extractBytes(), isNot(keys.wrapKey.extractBytes()));
  });
}
