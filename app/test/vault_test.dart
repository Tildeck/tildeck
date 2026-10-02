import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/ssh/terminal_session.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/password_rules.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

const password = 'orange-kettle-winter-42';

late Directory dir;
File get vaultFile => File('${dir.path}/vault.json');

Vault openVault() => Vault(crypto: VaultCrypto.load(), resolveFile: () async => vaultFile);

Future<Vault> newVault() async {
  final vault = openVault();
  await vault.load();
  await vault.create(password);
  return vault;
}

Future<Vault> reopen() async {
  final vault = openVault();
  await vault.load();
  return vault;
}

const host = HostEntry(
  id: 'host-1',
  name: 'Production web',
  group: 'Production',
  host: 'prod-web-01.example.com',
  username: 'deploy',
  password: 'a-saved-ssh-password',
);

const key = KeyEntry(
  id: 'key-1',
  name: 'Laptop',
  privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nsecret-key-material\n-----END OPENSSH PRIVATE KEY-----',
);

Map<String, dynamic> readFile() => jsonDecode(vaultFile.readAsStringSync()) as Map<String, dynamic>;
void writeFile(Map<String, dynamic> j) => vaultFile.writeAsStringSync(jsonEncode(j));
Map<String, dynamic> recordOf(Map<String, dynamic> j, String id) =>
    (j['records'] as List).cast<Map<String, dynamic>>().firstWhere((r) => r['id'] == id);

/// The vault as if the server had accepted every change: reopened and
/// unlocked, with nothing dirty, so the next edit is the next version.
Future<Vault> synced() async {
  final j = readFile();
  for (final r in (j['records'] as List).cast<Map<String, dynamic>>()) {
    r['dirty'] = false;
  }
  writeFile(j);
  final vault = await reopen();
  await vault.unlock(password);
  return vault;
}

void main() {
  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-vault'));
  tearDown(() => dir.delete(recursive: true));

  test('a new vault opens with the master password and nothing else', () async {
    final vault = await newVault();
    expect(vault.status, VaultStatus.unlocked);
    await vault.put(host);
    await vault.put(key);
    vault.lock();
    expect(vault.hosts, isEmpty, reason: 'locking forgets every decrypted entry');

    final again = await reopen();
    expect(again.status, VaultStatus.locked);
    final sw = Stopwatch()..start();
    expect(await again.unlock('wrong-password-entirely'), isFalse);
    sw.stop();
    // ignore: avoid_print
    print('unlock attempt (Argon2id, ops 3, 64 MiB): ${sw.elapsedMilliseconds} ms');
    expect(again.status, VaultStatus.locked);
    expect(await again.unlock(password), isTrue);
    expect(again.hosts.single.host, host.host);
    expect(again.hosts.single.password, host.password);
    expect(again.keys.single.privateKey, key.privateKey);
  });

  test('adopting a synced vault never replaces a vault that is here', () async {
    final first = await newVault();
    await first.put(host);
    first.lock();
    final before = await vaultFile.readAsString();
    final crypto = await VaultCrypto.load();
    final keys = await crypto.deriveKeys(password, first.kdf);
    final vaultKey = crypto.unwrapVaultKey(keys.keyEncryptionKey, first.wrapPw, first.vaultId);
    keys.dispose();
    await expectLater(
      first.adopt(
        vaultId: VaultCrypto.newId(),
        kdf: first.kdf,
        wrapPw: first.wrapPw,
        vaultKey: vaultKey,
        account: const SyncAccount(
          server: 'https://s.example.test',
          email: 'e@example.test',
          deviceId: 'd',
          deviceName: 'n',
          token: 't',
        ),
      ),
      throwsStateError,
    );
    vaultKey.dispose();
    expect(await vaultFile.readAsString(), before);
    expect(first.status, VaultStatus.locked);
  });

  test('the vault file holds no plaintext', () async {
    final vault = await newVault();
    await vault.put(host);
    await vault.put(key);
    final stored = vaultFile.readAsStringSync();
    for (final secret in [
      password,
      host.name,
      host.group,
      host.host,
      host.username,
      host.password!,
      key.name,
      'secret-key-material',
      'BEGIN OPENSSH',
      'deploy',
    ]) {
      expect(stored.contains(secret), isFalse, reason: '"$secret" must not appear in the vault file');
    }
  });

  test('a changed ciphertext is detected and left untouched', () async {
    final vault = await newVault();
    await vault.put(host);
    final j = readFile();
    final ct = base64.decode(recordOf(j, host.id)['ct'] as String);
    ct[ct.length - 1] ^= 1;
    recordOf(j, host.id)['ct'] = base64.encode(ct);
    writeFile(j);

    final again = await reopen();
    expect(await again.unlock(password), isTrue);
    expect(again.hosts, isEmpty);
    expect(again.damaged, [host.id]);
  });

  test('a ciphertext moved to another record, or replayed as a newer version, is refused', () async {
    final first = await newVault();
    await first.put(host);
    await first.put(key);
    final oldVersion = Map<String, dynamic>.of(recordOf(readFile(), host.id));
    final vault = await synced();
    await vault.put(HostEntry(id: host.id, name: 'Renamed', host: host.host, username: host.username));

    // Swap the two records' ciphertexts.
    final j = readFile();
    final a = recordOf(j, host.id), b = recordOf(j, key.id);
    for (final field in ['nonce', 'ct']) {
      final t = a[field];
      a[field] = b[field];
      b[field] = t;
    }
    writeFile(j);
    var again = await reopen();
    expect(await again.unlock(password), isTrue);
    expect(again.damaged.toSet(), {host.id, key.id});

    // Put the old version's ciphertext back under the current version number.
    final k = readFile();
    final current = recordOf(k, host.id);
    expect(current['version'], oldVersion['version'] + 1);
    current['nonce'] = oldVersion['nonce'];
    current['ct'] = oldVersion['ct'];
    writeFile(k);
    again = await reopen();
    expect(await again.unlock(password), isTrue);
    expect(again.damaged, contains(host.id));
  });

  test('deleting keeps a tombstone with only its marker, at the next version', () async {
    final first = await newVault();
    await first.put(host);
    await first.put(key);
    // Never synced: the change stays the record's first version.
    await first.delete(key.id);
    expect(recordOf(readFile(), key.id)['version'], 1);

    final vault = await synced();
    await vault.delete(host.id);
    expect(vault.hosts, isEmpty);
    final record = recordOf(readFile(), host.id);
    expect(record['deleted'], isTrue);
    expect(record['version'], 2);
    expect(record['dirty'], isTrue);
    // The marker proves the deletion; it holds nothing of the host.
    final marker = base64.decode(record['ct'] as String);
    expect(marker.length, lessThan(64), reason: '{"deleted":true} and the AEAD tag');
    expect(vaultFile.readAsStringSync(), isNot(contains('prod-web-01')));
  });

  test("snippets and a host's startup snippet are kept in the vault", () async {
    final vault = await newVault();
    const snippet = SnippetEntry(id: 'snip-1', name: 'Restart web', command: 'sudo systemctl restart nginx');
    await vault.put(snippet);
    await vault.put(
      HostEntry(id: 'host-2', name: 'Web', host: 'web.example.com', username: 'ops', startupSnippetId: 'snip-1'),
    );
    expect(vaultFile.readAsStringSync().contains('systemctl'), isFalse, reason: 'snippets are encrypted too');
    final again = await reopen();
    expect(await again.unlock(password), isTrue);
    expect(again.snippets.single.command, snippet.command);
    expect(again.hosts.single.startupSnippetId, 'snip-1');
  });

  test('a record of a type from a newer version is kept, not shown, and not called damaged', () async {
    final vault = await newVault();
    await vault.put(host);
    final j = readFile();
    final crypto = await VaultCrypto.load();
    final kdf = KdfParams.fromJson(j['kdf'] as Map<String, dynamic>);
    final keys = await crypto.deriveKeys(password, kdf);
    final vaultKey = crypto.unwrapVaultKey(
      keys.keyEncryptionKey,
      Sealed.fromJson(j['wrap_pw'] as Map<String, dynamic>),
      j['vault_id'] as String,
    );
    keys.dispose();
    final plain = utf8.encode(
      jsonEncode({
        'v': 1,
        'type': 'a_type_from_the_future',
        'data': {'local': 8080},
      }),
    );
    final sealed = crypto.encryptRecord(vaultKey, j['vault_id'] as String, 'future-1', 1, Uint8List.fromList(plain));
    vaultKey.dispose();
    (j['records'] as List).add({'id': 'future-1', 'version': 1, 'deleted': false, ...sealed.toJson(), 'dirty': false});
    writeFile(j);

    final again = await reopen();
    expect(await again.unlock(password), isTrue);
    expect(again.damaged, isEmpty);
    expect(again.hosts.single.name, host.name);
    await again.put(HostEntry(id: 'host-3', name: 'Another', host: 'b.example.com', username: 'ops'));
    expect(recordOf(readFile(), 'future-1')['ct'], sealed.toJson()['ct'], reason: 'kept untouched');
  });

  test('host keys live in the vault; the old plain file is imported once', () async {
    final vault = await newVault();
    final known = VaultKnownHosts(vault);
    const keyA = KnownHost(type: 'ssh-ed25519', fingerprint: 'SHA256:aaaa');
    const keyB = KnownHost(type: 'ssh-ed25519', fingerprint: 'SHA256:bbbb');
    expect(await known.check('Example.com', 22, keyA), HostKeyStatus.unknown);
    await known.trust('example.com', 22, keyA);
    expect(await known.check('EXAMPLE.com', 22, keyA), HostKeyStatus.trusted);
    expect(await known.check('example.com', 22, keyB), HostKeyStatus.changed);
    expect(await known.check('example.com', 2222, keyA), HostKeyStatus.unknown);
    await known.trust('example.com', 22, keyB);
    expect(vault.knownHosts, hasLength(1), reason: 'replacing a key keeps one record per host');

    final legacy = File('${dir.path}/known_hosts.json')
      ..writeAsStringSync(
        jsonEncode({
          'old.example.com:2222': {'type': 'ssh-rsa', 'fingerprint': 'SHA256:cccc'},
        }),
      );
    expect(await known.importLegacyFile(legacy), 1);
    expect(legacy.existsSync(), isFalse);
    expect(
      await known.check('old.example.com', 2222, const KnownHost(type: 'ssh-rsa', fingerprint: 'SHA256:cccc')),
      HostKeyStatus.trusted,
    );
    expect(vaultFile.readAsStringSync().contains('old.example.com'), isFalse);
  });

  test('master passwords: at least 12 characters, and not a common one', () {
    final common = CommonPasswords(
      File(
        'assets/security/common-passwords.txt',
      ).readAsLinesSync().where((l) => l.isNotEmpty && !l.startsWith('#')).toSet(),
    );
    expect(checkMasterPassword('short-pass', common), PasswordProblem.tooShort);
    expect(checkMasterPassword('1q2w3e4r5t6y', common), PasswordProblem.common);
    expect(checkMasterPassword('Q1W2E3R4T5Y6', common), PasswordProblem.common, reason: 'case does not matter');
    expect(checkMasterPassword(password, common), isNull);
  });

  test('Ctrl from the key bar turns the next letter into its control code', () {
    final session = TerminalSession(const ConnectionTarget(host: 'h', username: 'u'));
    expect(session.applyCtrl('c'), 'c');
    session.toggleCtrl();
    expect(session.applyCtrl('c'), '\x03');
    expect(session.ctrlLatched, isFalse, reason: 'the latch applies to one character');
    session.toggleCtrl();
    expect(session.applyCtrl('D'), '\x04');
    session.toggleCtrl();
    expect(session.applyCtrl('1'), '1', reason: 'digits have no control code');
    session.dispose();
  });
}
