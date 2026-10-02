import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/platform/biometric.dart';
import 'package:tildeck/vault/biometric_unlock.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

const password = 'orange-kettle-winter-42';
const text = BiometricPromptText(title: 'Unlock', subtitle: 'Tildeck', cancel: 'Use the master password');

/// The operating system, in memory. Android-like: keeps `BK` encrypted by a
/// key only it has. Windows-like: signs deterministically with a key only it
/// has.
class FakeBiometrics implements BiometricPlatform {
  FakeBiometrics({required this.keepsKey, this.seed = 0});

  /// Another system (or another Hello key) has another seed.
  final int seed;

  @override
  final bool keepsKey;
  bool enrolled = true;

  /// What the user does at the next prompt.
  BiometricFailure? next;
  final _secrets = <String, Uint8List>{};

  Uint8List _xor(Uint8List data, Uint8List key) =>
      Uint8List.fromList([for (var i = 0; i < data.length; i++) data[i] ^ key[i % key.length]]);

  void _check() {
    final failure = next;
    next = null;
    if (failure != null) throw BiometricException(failure);
  }

  @override
  Future<bool> available() async => enrolled;

  @override
  Future<(Uint8List, Uint8List)> protect(String vaultId, Uint8List key, BiometricPromptText text) async {
    _check();
    final secret = _secrets[vaultId] = Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3 + seed) % 256));
    return (Uint8List(12), _xor(key, secret));
  }

  @override
  Future<Uint8List> release(String vaultId, Uint8List nonce, Uint8List ciphertext, BiometricPromptText text) async {
    _check();
    final secret = _secrets[vaultId];
    if (secret == null) throw const BiometricException(BiometricFailure.invalidated);
    return _xor(ciphertext, secret);
  }

  @override
  Future<Uint8List> enrollSigner(String vaultId, Uint8List challenge) async {
    _check();
    _secrets[vaultId] = Uint8List.fromList(List.generate(32, (i) => (255 - i + seed) % 256));
    return sign(vaultId, challenge);
  }

  @override
  Future<Uint8List> sign(String vaultId, Uint8List challenge) async {
    _check();
    final secret = _secrets[vaultId];
    if (secret == null) throw const BiometricException(BiometricFailure.invalidated);
    return _xor(challenge, secret);
  }

  @override
  Future<void> remove(String vaultId) async => _secrets.remove(vaultId);

  /// A new fingerprint, or a deleted Hello key.
  void invalidate() => _secrets.clear();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tildeck-bio'));
  tearDown(() => dir.delete(recursive: true));

  File file() => File('${dir.path}/vault.json');
  Future<Vault> open() async {
    final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => file());
    await v.load();
    return v;
  }

  for (final keepsKey in [true, false]) {
    final system = keepsKey ? 'Android' : 'Windows';

    test('$system: turned on with the master password, it unlocks the vault, and survives a restart', () async {
      final vault = await open();
      await vault.create(password);
      await vault.put(const HostEntry(id: 'h1', name: 'Database', host: 'db.example.com', username: 'ops'));
      final platform = FakeBiometrics(keepsKey: keepsKey);
      final bio = BiometricUnlock(vault, platform);
      expect(await bio.enable('not-the-password-123', text), isFalse);
      expect(vault.biometricEnabled, isFalse);
      expect(await bio.enable(password, text), isTrue);
      expect(vault.biometricEnabled, isTrue);

      // Nothing on disk opens the vault without the system's key.
      final saved = jsonDecode(await file().readAsString()) as Map<String, dynamic>;
      expect(saved['biometric'], isNotNull);
      expect((saved['biometric'] as Map).containsKey('protected_key'), keepsKey);

      vault.lock();
      final again = await open();
      final bioAgain = BiometricUnlock(again, platform);
      expect(await bioAgain.offered(), isTrue);
      expect(await bioAgain.unlock(text), isTrue);
      expect(again.status, VaultStatus.unlocked);
      expect(again.hosts.single.name, 'Database');
    });

    test('$system: a cancel keeps the vault locked; a lost system key turns it off', () async {
      final vault = await open();
      await vault.create(password);
      final platform = FakeBiometrics(keepsKey: keepsKey);
      final bio = BiometricUnlock(vault, platform);
      await bio.enable(password, text);
      vault.lock();

      platform.next = BiometricFailure.cancelled;
      expect(await bio.unlock(text), isFalse);
      expect(vault.status, VaultStatus.locked);
      expect(vault.biometricEnabled, isTrue, reason: 'a cancel changes nothing');

      platform.invalidate();
      await expectLater(bio.unlock(text), throwsA(isA<BiometricException>()));
      expect(vault.biometricEnabled, isFalse);
      expect(await vault.unlock(password), isTrue, reason: 'the master password always works');
    });
  }

  test('a key that does not open wrap_bio is refused, and the master password still works', () async {
    final vault = await open();
    await vault.create(password);
    await BiometricUnlock(vault, FakeBiometrics(keepsKey: false)).enable(password, text);
    vault.lock();
    // A different system key (another Hello key with the same name, say).
    final other = FakeBiometrics(keepsKey: false, seed: 1);
    await other.enrollSigner(vault.vaultId, Uint8List(0));
    expect(await BiometricUnlock(vault, other).unlock(text), isFalse);
    expect(vault.status, VaultStatus.locked);
    expect(await vault.unlock(password), isTrue);
  });

  test('a new master password or the recovery key removes it; turning it off deletes the system key', () async {
    final vault = await open();
    await vault.create(password);
    final platform = FakeBiometrics(keepsKey: true);
    final bio = BiometricUnlock(vault, platform);
    await bio.enable(password, text);
    await vault.replaceWrap(kdf: vault.kdf, wrapPw: vault.wrapPw);
    expect(vault.biometricEnabled, isFalse);

    await bio.enable(password, text);
    await bio.disable();
    expect(vault.biometricEnabled, isFalse);
    await expectLater(
      platform.release(vault.vaultId, Uint8List(12), Uint8List(32), text),
      throwsA(isA<BiometricException>()),
    );
  });
}
