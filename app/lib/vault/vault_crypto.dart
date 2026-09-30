import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

/// The cryptography of docs/security-model.md, and nothing else: libsodium
/// primitives with the exact contexts and associated data the model defines.
/// A change here is a change to the security model and needs its approval.

/// Argon2id parameters, stored with the vault so they can be raised later.
class KdfParams {
  const KdfParams({required this.salt, this.opsLimit = 3, this.memLimit = 64 * 1024 * 1024});

  final Uint8List salt;
  final int opsLimit;
  final int memLimit;

  Map<String, Object> toJson() => {'alg': 'argon2id13', 'ops': opsLimit, 'mem': memLimit, 'salt': base64.encode(salt)};

  static KdfParams fromJson(Map<String, dynamic> json) {
    if (json['alg'] != 'argon2id13') throw const FormatException('unsupported key derivation');
    return KdfParams(
      salt: base64.decode(json['salt'] as String),
      opsLimit: json['ops'] as int,
      memLimit: json['mem'] as int,
    );
  }
}

/// A nonce and the ciphertext it sealed.
class Sealed {
  const Sealed(this.nonce, this.ciphertext);

  final Uint8List nonce;
  final Uint8List ciphertext;

  Map<String, String> toJson() => {'nonce': base64.encode(nonce), 'ct': base64.encode(ciphertext)};

  static Sealed fromJson(Map<String, dynamic> json) =>
      Sealed(base64.decode(json['nonce'] as String), base64.decode(json['ct'] as String));
}

/// The keys derived from the master password at unlock.
class PasswordKeys {
  PasswordKeys(this.authKey, this.keyEncryptionKey);

  /// `AK`: proves the password to the sync server (product step 4).
  final SecureKey authKey;

  /// `KEK`: wraps the vault key.
  final SecureKey keyEncryptionKey;

  void dispose() {
    authKey.dispose();
    keyEncryptionKey.dispose();
  }
}

/// The keys derived from the recovery key.
class RecoveryKeys {
  RecoveryKeys(this.authKey, this.wrapKey);

  /// `RAK`: proves the recovery key to the sync server.
  final SecureKey authKey;

  /// `RWK`: wraps the vault key.
  final SecureKey wrapKey;

  void dispose() {
    authKey.dispose();
    wrapKey.dispose();
  }
}

/// Wrong master password, or a vault key or record that was tampered with:
/// the AEAD check failed. Deliberately says nothing more.
class DecryptionFailed implements Exception {
  const DecryptionFailed();
}

class VaultCrypto {
  VaultCrypto(this.sodium);

  /// Loads the bundled libsodium.
  static Future<VaultCrypto> load() async => VaultCrypto(await SodiumSumoInit.init());

  final SodiumSumo sodium;

  static const _authContext = 'tdauth01';
  static const _wrapContext = 'tdwrap01';
  static const _recoveryContext = 'tdrecv01';

  Aead get _aead => sodium.crypto.aeadXChaCha20Poly1305IETF;

  KdfParams newKdfParams() => KdfParams(salt: sodium.randombytes.buf(sodium.crypto.pwhash.saltBytes));

  /// Argon2id from the master password, then the authentication key and the
  /// key-encryption key through the BLAKE2b KDF. The Argon2id step runs in a
  /// background isolate so the interface stays responsive.
  Future<PasswordKeys> deriveKeys(String password, KdfParams params) async {
    final (auth, wrap) = await Isolate.run(() => _derive(password, params));
    try {
      return PasswordKeys(SecureKey.fromList(sodium, auth), SecureKey.fromList(sodium, wrap));
    } finally {
      auth.fillRange(0, auth.length, 0);
      wrap.fillRange(0, wrap.length, 0);
    }
  }

  static Future<(Uint8List, Uint8List)> _derive(String password, KdfParams params) async {
    final sodium = await SodiumSumoInit.init();
    final passwordBytes = Int8List.fromList(utf8.encode(password));
    final passwordKey = sodium.crypto.pwhash(
      outLen: 32,
      password: passwordBytes,
      salt: params.salt,
      opsLimit: params.opsLimit,
      memLimit: params.memLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
    passwordBytes.fillRange(0, passwordBytes.length, 0);
    try {
      SecureKey sub(String context, int id) => sodium.crypto.kdf.deriveFromKey(
        masterKey: passwordKey,
        context: context,
        subkeyId: BigInt.from(id),
        subkeyLen: 32,
      );
      final auth = sub(_authContext, 1);
      final wrap = sub(_wrapContext, 2);
      try {
        return (auth.extractBytes(), wrap.extractBytes());
      } finally {
        auth.dispose();
        wrap.dispose();
      }
    } finally {
      passwordKey.dispose();
    }
  }

  /// A new random vault key `VK`.
  SecureKey newVaultKey() => _aead.keygen();

  /// A new random UUID v4: record ids and the vault id. Not secret; it binds
  /// ciphertexts to their place, so it only has to be unique.
  static String newId() {
    final random = Random.secure();
    final b = Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Uint8List _wrapAd(String vaultId) => Uint8List.fromList(utf8.encode('tildeck:wrap:password:v1|$vaultId'));

  static Uint8List _recoveryWrapAd(String vaultId) =>
      Uint8List.fromList(utf8.encode('tildeck:wrap:recovery:v1|$vaultId'));

  static Uint8List _localAd(String vaultId) => Uint8List.fromList(utf8.encode('tildeck:local:v1|$vaultId'));

  static Uint8List _recordAd(String vaultId, String recordId, int version) =>
      Uint8List.fromList(utf8.encode('tildeck:record:v1|$vaultId|$recordId|$version'));

  Sealed _seal(SecureKey key, Uint8List message, Uint8List ad) {
    final nonce = sodium.randombytes.buf(_aead.nonceBytes);
    return Sealed(nonce, _aead.encrypt(message: message, nonce: nonce, key: key, additionalData: ad));
  }

  Uint8List _open(SecureKey key, Sealed sealed, Uint8List ad) {
    try {
      return _aead.decrypt(cipherText: sealed.ciphertext, nonce: sealed.nonce, key: key, additionalData: ad);
    } on SodiumException {
      throw const DecryptionFailed();
    }
  }

  /// `wrap_pw`: the vault key sealed under the key-encryption key.
  Sealed wrapVaultKey(SecureKey kek, SecureKey vaultKey, String vaultId) => vaultKey.runUnlockedSync((bytes) {
    final copy = Uint8List.fromList(bytes);
    try {
      return _seal(kek, copy, _wrapAd(vaultId));
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  });

  /// Throws [DecryptionFailed] for a wrong master password.
  SecureKey unwrapVaultKey(SecureKey kek, Sealed wrapped, String vaultId) {
    final bytes = _open(kek, wrapped, _wrapAd(vaultId));
    try {
      return SecureKey.fromList(sodium, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// A new random recovery key `RK`: 32 bytes, shown to the user once.
  Uint8List newRecoveryKey() => sodium.randombytes.buf(32);

  /// `RAK` and `RWK` from the recovery key.
  RecoveryKeys recoveryKeys(Uint8List recoveryKey) {
    final master = SecureKey.fromList(sodium, recoveryKey);
    try {
      SecureKey sub(int id) => sodium.crypto.kdf.deriveFromKey(
        masterKey: master,
        context: _recoveryContext,
        subkeyId: BigInt.from(id),
        subkeyLen: 32,
      );
      return RecoveryKeys(sub(1), sub(2));
    } finally {
      master.dispose();
    }
  }

  /// `wrap_rk`: the vault key sealed under the recovery wrapping key.
  Sealed wrapVaultKeyForRecovery(SecureKey rwk, SecureKey vaultKey, String vaultId) =>
      vaultKey.runUnlockedSync((bytes) {
        final copy = Uint8List.fromList(bytes);
        try {
          return _seal(rwk, copy, _recoveryWrapAd(vaultId));
        } finally {
          copy.fillRange(0, copy.length, 0);
        }
      });

  /// Throws [DecryptionFailed] for a wrong recovery key.
  SecureKey unwrapVaultKeyForRecovery(SecureKey rwk, Sealed wrapped, String vaultId) {
    final bytes = _open(rwk, wrapped, _recoveryWrapAd(vaultId));
    try {
      return SecureKey.fromList(sodium, bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// This device's own state (its sync account and device token), sealed
  /// under the vault key in the local vault file. It never syncs.
  Sealed encryptLocal(SecureKey vaultKey, String vaultId, Uint8List plaintext) =>
      _seal(vaultKey, plaintext, _localAd(vaultId));

  Uint8List decryptLocal(SecureKey vaultKey, String vaultId, Sealed sealed) =>
      _open(vaultKey, sealed, _localAd(vaultId));

  /// The 2-byte checksum written after a recovery key: the first two bytes
  /// of its BLAKE2b hash (libsodium's shortest output is 16 bytes).
  Uint8List recoveryChecksum(Uint8List recoveryKey) =>
      Uint8List.sublistView(sodium.crypto.genericHash(message: recoveryKey, outLen: 16), 0, 2);

  Sealed encryptRecord(SecureKey vaultKey, String vaultId, String recordId, int version, Uint8List plaintext) =>
      _seal(vaultKey, plaintext, _recordAd(vaultId, recordId, version));

  /// Throws [DecryptionFailed] if the ciphertext was changed or does not
  /// belong to this vault, record, and version.
  Uint8List decryptRecord(SecureKey vaultKey, String vaultId, String recordId, int version, Sealed sealed) =>
      _open(vaultKey, sealed, _recordAd(vaultId, recordId, version));
}
