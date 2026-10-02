import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart' show SecureKey;

import '../platform/biometric.dart';
import 'vault.dart';
import 'vault_crypto.dart';

/// Biometric unlock for a vault on this device (docs/security-model.md,
/// "Biometric unlock"): turning it on with the master password, unlocking
/// with it, and turning it off.
class BiometricUnlock {
  BiometricUnlock(this.vault, this.platform);

  final Vault vault;

  /// Null where the system offers nothing.
  final BiometricPlatform? platform;

  Future<bool> available() async => await platform?.available() ?? false;

  /// Whether the unlock screen offers it now.
  Future<bool> offered() async => vault.biometricEnabled && await available();

  /// Turns it on: [password] must be the master password. False when it
  /// is not. Throws [BiometricException] when the system refuses.
  Future<bool> enable(String password, BiometricPromptText text) async {
    final p = platform;
    if (p == null) throw const BiometricException(BiometricFailure.unavailable);
    final keys = await vault.passwordKeys(password);
    if (keys == null) return false;
    keys.dispose();
    final vaultId = vault.vaultId;
    final crypto = vault.crypto;
    if (p.keepsKey) {
      final raw = crypto.newBiometricKey();
      try {
        final (nonce, ciphertext) = await p.protect(vaultId, raw, text);
        final bk = crypto.biometricKey(raw);
        try {
          await vault.enableBiometric(bk, protectedKey: Sealed(nonce, ciphertext));
        } finally {
          bk.dispose();
        }
      } finally {
        raw.fillRange(0, raw.length, 0);
      }
    } else {
      final signature = await p.enrollSigner(vaultId, VaultCrypto.biometricChallenge(vaultId));
      final bk = crypto.biometricKeyFromSignature(signature);
      signature.fillRange(0, signature.length, 0);
      try {
        await vault.enableBiometric(bk);
      } finally {
        bk.dispose();
      }
    }
    return true;
  }

  /// Unlocks the vault. False when the user cancelled or the key no longer
  /// opens it; then the master password is needed. When the system says
  /// the key is gone, biometric unlock is turned off here.
  Future<bool> unlock(BiometricPromptText text) async {
    final p = platform;
    if (p == null || !vault.biometricEnabled) return false;
    final vaultId = vault.vaultId;
    final crypto = await VaultCrypto.load();
    SecureKey? bk;
    try {
      if (p.keepsKey) {
        final protectedKey = vault.biometricProtectedKey;
        if (protectedKey == null) {
          await vault.disableBiometric();
          return false;
        }
        final Uint8List raw = await p.release(vaultId, protectedKey.nonce, protectedKey.ciphertext, text);
        bk = crypto.biometricKey(raw);
        raw.fillRange(0, raw.length, 0);
      } else {
        final signature = await p.sign(vaultId, VaultCrypto.biometricChallenge(vaultId));
        bk = crypto.biometricKeyFromSignature(signature);
        signature.fillRange(0, signature.length, 0);
      }
      return await vault.unlockWithBiometric(bk);
    } on BiometricException catch (e) {
      if (e.failure == BiometricFailure.invalidated) await vault.disableBiometric();
      if (e.failure == BiometricFailure.cancelled) return false;
      rethrow;
    } finally {
      bk?.dispose();
    }
  }

  /// Turns it off here: forgets `wrap_bio` and deletes the system's key.
  Future<void> disable() async {
    final vaultId = vault.vaultId;
    await vault.disableBiometric();
    try {
      await platform?.remove(vaultId);
    } on BiometricException {
      // Nothing left to delete, or the system refused: wrap_bio is gone
      // either way, and a leftover key opens nothing.
    }
  }
}
