import 'dart:io';

import '../vault/vault.dart';
import '../vault/vault_crypto.dart';
import 'recovery_key.dart';
import 'sync_engine.dart';
import 'sync_server.dart';

/// The typed master password is not this vault's.
class WrongMasterPassword implements Exception {
  const WrongMasterPassword();
}

/// The account holds a different vault than the one on this device.
class DifferentVault implements Exception {
  const DifferentVault();
}

/// A new device signed in and waits for approval from another device or
/// by email. It holds the keys of the typed master password until the
/// approval is collected or the wait is abandoned.
class PendingDevice {
  PendingDevice._(this._service, this._server, this._address, this._email, this._deviceName, this._keys, this.pending);

  final AccountService _service;
  final SyncServer _server;
  final String _address;
  final String _email;
  final String _deviceName;
  PasswordKeys? _keys;
  final SigninPending pending;

  String get deviceName => _deviceName;

  /// True once approved and the vault is open on this device; false while
  /// the approval is still missing. Throws [SyncFailure] for anything else
  /// (a revoked request, for one).
  Future<bool> collect() async {
    final keys = _keys;
    if (keys == null) throw StateError('abandoned');
    final SignedIn signedIn;
    try {
      signedIn = await _server.claim(pending.deviceId, pending.claimToken);
    } on SyncFailure catch (e) {
      if (e.code == 'device_pending') return false;
      rethrow;
    }
    await _service._open(signedIn, keys, _address, _email, pending.deviceId, _deviceName);
    abandon();
    return true;
  }

  /// Forgets the keys; a later sign-in starts a new request.
  void abandon() {
    _keys?.dispose();
    _keys = null;
  }
}

/// Registration and sign-in (docs/security-model.md, "Accounts and
/// devices"), connecting the vault on this device to a sync account.
class AccountService {
  AccountService({required this.vault, required this.engine});

  final Vault vault;
  final SyncEngine engine;

  /// A readable default for this device's name in the account's devices list.
  static String defaultDeviceName() {
    if (Platform.isAndroid) return 'Android';
    final host = Platform.localHostname;
    return host.isEmpty || host == 'localhost' ? Platform.operatingSystem : host;
  }

  /// Registers the vault on this device as a new account and signs this
  /// device in. Returns the recovery key, written for the user; it is not
  /// kept anywhere. Throws [WrongMasterPassword] or [SyncFailure].
  Future<String> register({
    required String address,
    required String email,
    required String password,
    required String locale,
    required String deviceName,
  }) async {
    final keys = await vault.passwordKeys(password);
    if (keys == null) throw const WrongMasterPassword();
    final crypto = vault.crypto;
    final recoveryKey = crypto.newRecoveryKey();
    final recovery = crypto.recoveryKeys(recoveryKey);
    try {
      final deviceId = VaultCrypto.newId();
      final signedIn = await engine
          .serverFor(address)
          .register(
            email: email,
            locale: locale,
            vaultId: vault.vaultId,
            kdf: vault.kdf,
            authKey: keys.authKey.extractBytes(),
            recoveryAuthKey: recovery.authKey.extractBytes(),
            wrapPw: vault.wrapPw,
            wrapRk: vault.wrapForRecovery(recovery.wrapKey),
            deviceId: deviceId,
            deviceName: deviceName,
          );
      await vault.setAccount(
        SyncAccount(server: address, email: email, deviceId: deviceId, deviceName: deviceName, token: signedIn.token),
      );
      return RecoveryKeyCodec(crypto).encode(recoveryKey);
    } finally {
      keys.dispose();
      recovery.dispose();
      recoveryKey.fillRange(0, recoveryKey.length, 0);
    }
  }

  /// Signs this device in to an existing account. With no vault on this
  /// device yet, it opens the account's vault; with one, the account must
  /// hold that same vault (a device signing in again after its token
  /// expired or it was removed). Returns null when signed in, or the
  /// pending device when another device must approve it first. Throws
  /// [WrongMasterPassword], [DifferentVault], or [SyncFailure].
  Future<PendingDevice?> signIn({
    required String address,
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final server = engine.serverFor(address);
    final kdf = await server.prelogin(email);
    final crypto = vault.status == VaultStatus.unlocked ? vault.crypto : await VaultCrypto.load();
    final keys = await crypto.deriveKeys(password, kdf);
    var keep = false;
    try {
      // A device signing in again keeps its id, so it needs no new approval.
      var deviceId = vault.account?.deviceId ?? VaultCrypto.newId();
      Future<SigninOutcome> signin() =>
          server.signin(email: email, authKey: keys.authKey.extractBytes(), deviceId: deviceId, deviceName: deviceName);
      SigninOutcome outcome;
      try {
        outcome = await signin();
      } on SyncFailure catch (e) {
        // A removed device comes back as a new one, and waits for approval.
        if (e.code != 'device_revoked' || vault.account == null) rethrow;
        deviceId = VaultCrypto.newId();
        outcome = await signin();
      }
      switch (outcome) {
        case SigninActive(:final signedIn):
          await _open(signedIn, keys, address, email, deviceId, deviceName);
          return null;
        case SigninPending():
          keep = true;
          return PendingDevice._(this, server, address, email, deviceName, keys, outcome);
      }
    } on SyncFailure catch (e) {
      if (e.code == 'invalid_credentials') throw const WrongMasterPassword();
      rethrow;
    } finally {
      if (!keep) keys.dispose();
    }
  }

  Future<void> _open(
    SignedIn signedIn,
    PasswordKeys keys,
    String address,
    String email,
    String deviceId,
    String deviceName,
  ) async {
    final account = SyncAccount(
      server: address,
      email: email,
      deviceId: deviceId,
      deviceName: deviceName,
      token: signedIn.token,
    );
    if (vault.status == VaultStatus.unlocked) {
      if (signedIn.vaultId != vault.vaultId) throw const DifferentVault();
      await vault.setAccount(account);
      return;
    }
    final crypto = await VaultCrypto.load();
    final vaultKey = crypto.unwrapVaultKey(keys.keyEncryptionKey, signedIn.wrapPw, signedIn.vaultId);
    await vault.adopt(
      vaultId: signedIn.vaultId,
      kdf: signedIn.kdf,
      wrapPw: signedIn.wrapPw,
      vaultKey: vaultKey,
      account: account,
    );
  }

  /// Removes this device from the account and forgets the account here.
  /// The vault stays on the device.
  Future<void> signOut() async {
    final account = vault.account;
    if (account == null) return;
    try {
      await engine.serverFor(account.server).revoke(account.token, account.deviceId);
    } on SyncFailure {
      // Already removed, or the server is away: forget it here either way.
    }
    await vault.setAccount(null);
  }
}
