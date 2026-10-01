import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import 'models.dart';
import 'vault_crypto.dart';

enum VaultStatus { loading, missing, locked, unlocked }

/// One record as stored: everything but the ciphertext is visible metadata.
class StoredRecord {
  const StoredRecord({required this.id, required this.version, this.deleted = false, this.sealed, this.dirty = false});

  final String id;

  /// A record changed on this device is one version above the last version
  /// the server accepted, and stays there, however often it is edited,
  /// until the server accepts it: the server takes only the next version.
  final int version;

  /// A tombstone: the record was deleted and keeps no content, so the
  /// deletion reaches other devices.
  final bool deleted;
  final Sealed? sealed;

  /// Changed on this device and not yet accepted by the sync server.
  final bool dirty;

  StoredRecord copyWith({bool? dirty}) =>
      StoredRecord(id: id, version: version, deleted: deleted, sealed: sealed, dirty: dirty ?? this.dirty);

  /// The same stored content: the same version and the same ciphertext.
  bool sameAs(StoredRecord other) =>
      version == other.version &&
      deleted == other.deleted &&
      listEquals(sealed?.nonce, other.sealed?.nonce) &&
      listEquals(sealed?.ciphertext, other.sealed?.ciphertext);

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'deleted': deleted,
    ...?sealed?.toJson(),
    'dirty': dirty,
  };

  static StoredRecord fromJson(Map<String, dynamic> j, {bool dirtyByDefault = false}) => StoredRecord(
    id: j['id'] as String,
    version: j['version'] as int,
    deleted: j['deleted'] as bool? ?? false,
    sealed: j['ct'] == null ? null : Sealed.fromJson(j),
    dirty: j['dirty'] as bool? ?? dirtyByDefault,
  );
}

/// This device's sync account: kept in the vault file, sealed under the
/// vault key, and never synced.
class SyncAccount {
  const SyncAccount({
    required this.server,
    required this.email,
    required this.deviceId,
    required this.deviceName,
    required this.token,
  });

  /// The server's base address.
  final String server;
  final String email;
  final String deviceId;
  final String deviceName;

  /// The device token: the bearer for every request.
  final String token;

  Map<String, Object> toJson() => {
    'server': server,
    'email': email,
    'device_id': deviceId,
    'device_name': deviceName,
    'token': token,
  };

  static SyncAccount fromJson(Map<String, dynamic> j) => SyncAccount(
    server: j['server'] as String,
    email: j['email'] as String,
    deviceId: j['device_id'] as String,
    deviceName: j['device_name'] as String,
    token: j['token'] as String,
  );
}

/// The local vault (docs/security-model.md, "The vault on a device"). It
/// stores only the wrapped vault key and encrypted records; the vault key
/// exists in memory only while the vault is unlocked.
class Vault extends ChangeNotifier {
  /// [crypto] resolves once, the first time the vault needs it: loading
  /// libsodium is asynchronous.
  Vault({required Future<VaultCrypto> crypto, required this.resolveFile, DateTime Function()? clock})
    : _cryptoFuture = crypto,
      _clock = clock ?? DateTime.now;

  final Future<VaultCrypto> _cryptoFuture;
  VaultCrypto? _crypto;

  /// Available once the vault is created or unlocked.
  VaultCrypto get crypto => _crypto!;

  /// Finds the vault file on first use.
  final Future<File> Function() resolveFile;
  final DateTime Function() _clock;

  /// 2 added sync state: the dirty flag per record, the pull cursor, and
  /// the sealed account. A format 1 file loads as never synced.
  static const formatVersion = 2;

  VaultStatus status = VaultStatus.loading;

  File? _file;
  String? _vaultId;
  KdfParams? _kdf;
  Sealed? _wrapPw;
  final _records = <String, StoredRecord>{};
  int _cursor = 0;
  Sealed? _sealedAccount;
  SyncAccount? _account;

  SecureKey? _vaultKey;
  final _entries = <String, VaultEntry>{};

  /// Records that failed to decrypt at unlock or when pulled: changed on
  /// disk, damaged, or not from this vault. They are kept untouched and
  /// reported, never silently dropped.
  final damaged = <String>[];

  Future<void> _writes = Future.value();

  Future<File> get _vaultFile async => _file ??= await resolveFile();

  Future<void> load() async {
    final file = await _vaultFile;
    if (!await file.exists()) {
      status = VaultStatus.missing;
    } else {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final format = j['format'];
      if (format != 1 && format != formatVersion) throw const FormatException('unsupported vault format');
      _vaultId = j['vault_id'] as String;
      _kdf = KdfParams.fromJson(j['kdf'] as Map<String, dynamic>);
      _wrapPw = Sealed.fromJson(j['wrap_pw'] as Map<String, dynamic>);
      _cursor = j['cursor'] as int? ?? 0;
      final account = j['account'] as Map<String, dynamic>?;
      _sealedAccount = account == null ? null : Sealed.fromJson(account);
      _records
        ..clear()
        ..addEntries(
          (j['records'] as List).map((r) {
            final record = StoredRecord.fromJson(r as Map<String, dynamic>, dirtyByDefault: format == 1);
            return MapEntry(record.id, record);
          }),
        );
      status = VaultStatus.locked;
    }
    notifyListeners();
  }

  /// Creates a new, empty vault protected by [password], and unlocks it.
  Future<void> create(String password) async {
    assert(status == VaultStatus.missing);
    final crypto = _crypto ??= await _cryptoFuture;
    final kdf = crypto.newKdfParams();
    final vaultId = VaultCrypto.newId();
    final keys = await crypto.deriveKeys(password, kdf);
    final vaultKey = crypto.newVaultKey();
    try {
      _wrapPw = crypto.wrapVaultKey(keys.keyEncryptionKey, vaultKey, vaultId);
    } finally {
      keys.dispose();
    }
    _vaultId = vaultId;
    _kdf = kdf;
    _records.clear();
    _entries.clear();
    _cursor = 0;
    _sealedAccount = null;
    _account = null;
    _vaultKey = vaultKey;
    await _save();
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// Creates this device's vault from an existing synced vault, whose key
  /// the caller unwrapped with the master password, and unlocks it. The
  /// records arrive with the first pull.
  Future<void> adopt({
    required String vaultId,
    required KdfParams kdf,
    required Sealed wrapPw,
    required SecureKey vaultKey,
    required SyncAccount account,
  }) async {
    assert(status == VaultStatus.missing);
    _crypto ??= await _cryptoFuture;
    _vaultId = vaultId;
    _kdf = kdf;
    _wrapPw = wrapPw;
    _records.clear();
    _entries.clear();
    damaged.clear();
    _cursor = 0;
    _vaultKey = vaultKey;
    _setAccount(account);
    await _save();
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// False for a wrong password; nothing else distinguishes it.
  Future<bool> unlock(String password) async {
    assert(status == VaultStatus.locked);
    final crypto = _crypto ??= await _cryptoFuture;
    final keys = await crypto.deriveKeys(password, _kdf!);
    final SecureKey vaultKey;
    try {
      vaultKey = crypto.unwrapVaultKey(keys.keyEncryptionKey, _wrapPw!, _vaultId!);
    } on DecryptionFailed {
      return false;
    } finally {
      keys.dispose();
    }
    _openWith(vaultKey);
    return true;
  }

  /// Decrypts every entry and this device's account with [vaultKey], and
  /// marks the vault unlocked.
  void _openWith(SecureKey vaultKey) {
    _entries.clear();
    damaged.clear();
    for (final record in _records.values) {
      if (record.deleted || record.sealed == null) continue;
      final doc = _decrypt(record, vaultKey);
      try {
        if (doc == null) throw const FormatException('not decryptable');
        _entries[record.id] = _entryOf(record.id, doc);
      } on FormatException {
        damaged.add(record.id);
      }
    }
    _account = null;
    if (_sealedAccount != null) {
      try {
        final plain = crypto.decryptLocal(vaultKey, _vaultId!, _sealedAccount!);
        _account = SyncAccount.fromJson(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
        plain.fillRange(0, plain.length, 0);
      } on DecryptionFailed {
        // A changed account section costs this device only its sign-in.
        _sealedAccount = null;
      } on FormatException {
        _sealedAccount = null;
      }
    }
    _vaultKey = vaultKey;
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// Opens the vault after recovery: the vault key came from the recovery
  /// key, and [kdf] and [wrapPw] belong to the new master password. A vault
  /// already on this device must be the same vault; with none, it is
  /// created from the account, as at sign-in.
  Future<void> recover({
    required String vaultId,
    required KdfParams kdf,
    required Sealed wrapPw,
    required SecureKey vaultKey,
    required SyncAccount account,
  }) async {
    if (status == VaultStatus.missing) {
      return adopt(vaultId: vaultId, kdf: kdf, wrapPw: wrapPw, vaultKey: vaultKey, account: account);
    }
    if (vaultId != _vaultId) throw StateError('a different vault');
    _crypto ??= await _cryptoFuture;
    if (status == VaultStatus.unlocked) {
      _vaultKey?.dispose();
      _vaultKey = null;
    }
    _kdf = kdf;
    _wrapPw = wrapPw;
    _openWith(vaultKey);
    _setAccount(account);
    await _save();
    notifyListeners();
  }

  /// The vault key sealed under another key-encryption key: the `wrap_pw`
  /// of a new master password.
  Sealed wrapWith(SecureKey keyEncryptionKey) => crypto.wrapVaultKey(keyEncryptionKey, _requireUnlocked(), _vaultId!);

  /// Replaces the master password's parameters and wrapped key, after the
  /// caller checked that [wrapPw] holds this vault's key: a password change
  /// here or on another device.
  Future<void> replaceWrap({required KdfParams kdf, required Sealed wrapPw}) async {
    _requireUnlocked();
    _kdf = kdf;
    _wrapPw = wrapPw;
    notifyListeners();
    await _save();
  }

  /// Forgets the vault key and every decrypted entry.
  void lock() {
    if (status != VaultStatus.unlocked) return;
    _vaultKey?.dispose();
    _vaultKey = null;
    _entries.clear();
    _account = null;
    status = VaultStatus.locked;
    notifyListeners();
  }

  String newId() => VaultCrypto.newId();

  Iterable<T> _of<T extends VaultEntry>() => _entries.values.whereType<T>();
  List<HostEntry> get hosts =>
      _of<HostEntry>().toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<KeyEntry> get keys =>
      _of<KeyEntry>().toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<KnownHostEntry> get knownHosts => _of<KnownHostEntry>().toList();
  T? entry<T extends VaultEntry>(String? id) => id == null ? null : _entries[id] as T?;

  /// Adds or replaces an entry as a change for the server.
  Future<void> put(VaultEntry entry) async {
    final key = _requireUnlocked();
    final version = _nextVersion(_records[entry.id]);
    final plain = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'type': entry.type,
          'modified_at': _clock().toUtc().toIso8601String(),
          'data': entry.dataJson(),
        }),
      ),
    );
    final sealed = crypto.encryptRecord(key, _vaultId!, entry.id, version, plain);
    plain.fillRange(0, plain.length, 0);
    _records[entry.id] = StoredRecord(id: entry.id, version: version, sealed: sealed, dirty: true);
    _entries[entry.id] = entry;
    notifyListeners();
    await _save();
  }

  /// Deletes an entry, keeping a tombstone for its record.
  Future<void> delete(String id) async {
    _requireUnlocked();
    final current = _records[id];
    if (current == null || current.deleted) return;
    _records[id] = StoredRecord(id: id, version: _nextVersion(current), deleted: true, dirty: true);
    _entries.remove(id);
    notifyListeners();
    await _save();
  }

  /// A clean record's change is its next version; a dirty one's stays at
  /// the version the server has not accepted yet.
  static int _nextVersion(StoredRecord? current) =>
      current == null ? 1 : (current.dirty ? current.version : current.version + 1);

  // Sync state, used by lib/sync/.

  /// Not secret: the server holds the same values.
  String get vaultId => _vaultId!;
  KdfParams get kdf => _kdf!;
  Sealed get wrapPw => _wrapPw!;

  /// The server revision this device has pulled up to.
  int get cursor => _cursor;

  /// This device's sync account; known only while unlocked.
  SyncAccount? get account => _account;

  void _setAccount(SyncAccount? account) {
    _account = account;
    if (account == null) {
      _sealedAccount = null;
      return;
    }
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(account.toJson())));
    _sealedAccount = crypto.encryptLocal(_vaultKey!, _vaultId!, plain);
    plain.fillRange(0, plain.length, 0);
  }

  /// Signs this device in to [account], or out with null. Signing out
  /// forgets the cursor and marks every record as changed, so whatever
  /// account comes next receives the whole vault.
  Future<void> setAccount(SyncAccount? account) async {
    _requireUnlocked();
    _setAccount(account);
    if (account == null) {
      _cursor = 0;
      for (final id in _records.keys.toList()) {
        _records[id] = _records[id]!.copyWith(dirty: true);
      }
    }
    notifyListeners();
    await _save();
  }

  /// The keys of [password] when it is this vault's master password, for
  /// the account requests that prove it; null when it is not. The caller
  /// disposes them.
  Future<PasswordKeys?> passwordKeys(String password) async {
    _requireUnlocked();
    final keys = await crypto.deriveKeys(password, _kdf!);
    try {
      crypto.unwrapVaultKey(keys.keyEncryptionKey, _wrapPw!, _vaultId!).dispose();
    } on DecryptionFailed {
      keys.dispose();
      return null;
    }
    return keys;
  }

  /// `wrap_rk` for this vault under a recovery wrapping key.
  Sealed wrapForRecovery(SecureKey recoveryWrapKey) =>
      crypto.wrapVaultKeyForRecovery(recoveryWrapKey, _requireUnlocked(), _vaultId!);

  /// Every record changed here and not yet accepted by the server.
  List<StoredRecord> get dirtyRecords => [
    for (final r in _records.values)
      if (r.dirty) r,
  ];

  /// Applies one page of pulled records and moves the cursor past it.
  Future<void> applyPulled(Iterable<StoredRecord> remote, int cursor) async {
    _requireUnlocked();
    for (final r in remote) {
      _merge(r);
    }
    _cursor = cursor;
    notifyListeners();
    await _save();
  }

  /// Applies a push result. An accepted change stops being dirty only if
  /// the record was not edited again while it was on its way. A conflict
  /// is resolved against the server's current record.
  Future<void> applyPushed({
    required Iterable<StoredRecord> accepted,
    required Iterable<(String, StoredRecord?)> conflicts,
  }) async {
    _requireUnlocked();
    for (final sent in accepted) {
      final local = _records[sent.id];
      if (local != null && local.dirty && local.sameAs(sent)) _records[sent.id] = local.copyWith(dirty: false);
    }
    for (final (id, current) in conflicts) {
      final local = _records[id];
      if (local == null || !local.dirty) continue;
      if (current == null) {
        // The server has never had this record: it starts at version 1
        // there, whatever its local history, and is re-encrypted for it.
        if (local.version != 1) _records[id] = _reencrypt(local, 1);
      } else if (current.version + 1 < local.version) {
        // The server is behind this device (restored from a backup): the
        // local change becomes the server's next version.
        _records[id] = _reencrypt(local, current.version + 1);
      } else {
        _merge(current);
      }
    }
    notifyListeners();
    await _save();
  }

  /// Brings one server record into the vault (docs/security-model.md,
  /// "Sync"). A version at or below what this device has is ignored, so a
  /// stored version never goes down. Against a local change, the newer edit
  /// wins by the `modified_at` time inside the two plaintexts, and an edit
  /// wins against a deletion, so no concurrent edit is lost. A server record
  /// that does not decrypt is reported as damaged and never replaces
  /// anything.
  void _merge(StoredRecord remote) {
    final local = _records[remote.id];
    if (local != null && !local.dirty && remote.version <= local.version) return;
    if (local != null && local.dirty && remote.version < local.version) return;

    Map<String, dynamic>? remoteDoc;
    if (!remote.deleted) {
      remoteDoc = _decrypt(remote);
      if (remoteDoc == null) {
        if (!damaged.contains(remote.id)) damaged.add(remote.id);
        return;
      }
    }

    if (local != null && local.dirty && _localWins(local, remoteDoc)) {
      _records[remote.id] = _reencrypt(local, remote.version + 1);
      return;
    }

    _records[remote.id] = remote.copyWith(dirty: false);
    damaged.remove(remote.id);
    if (remoteDoc == null) {
      _entries.remove(remote.id);
      return;
    }
    try {
      _entries[remote.id] = _entryOf(remote.id, remoteDoc);
    } on FormatException {
      _entries.remove(remote.id);
      damaged.add(remote.id);
    }
  }

  bool _localWins(StoredRecord local, Map<String, dynamic>? remoteDoc) {
    if (remoteDoc == null) return !local.deleted;
    if (local.deleted) return false;
    final localDoc = _decrypt(local);
    if (localDoc == null) return false;
    final localTime = DateTime.tryParse(localDoc['modified_at'] as String? ?? '');
    final remoteTime = DateTime.tryParse(remoteDoc['modified_at'] as String? ?? '');
    if (localTime == null) return false;
    if (remoteTime == null) return true;
    return localTime.isAfter(remoteTime);
  }

  /// A dirty record moved to [version]: re-encrypted, since the version is
  /// bound into the ciphertext. Its content and `modified_at` are unchanged.
  StoredRecord _reencrypt(StoredRecord local, int version) {
    if (local.deleted || local.sealed == null) {
      return StoredRecord(id: local.id, version: version, deleted: true, dirty: true);
    }
    final key = _requireUnlocked();
    final plain = crypto.decryptRecord(key, _vaultId!, local.id, local.version, local.sealed!);
    final sealed = crypto.encryptRecord(key, _vaultId!, local.id, version, plain);
    plain.fillRange(0, plain.length, 0);
    return StoredRecord(id: local.id, version: version, sealed: sealed, dirty: true);
  }

  Map<String, dynamic>? _decrypt(StoredRecord record, [SecureKey? key]) {
    if (record.sealed == null) return null;
    try {
      final plain = crypto.decryptRecord(
        key ?? _requireUnlocked(),
        _vaultId!,
        record.id,
        record.version,
        record.sealed!,
      );
      final doc = jsonDecode(utf8.decode(plain));
      plain.fillRange(0, plain.length, 0);
      return doc is Map<String, dynamic> ? doc : null;
    } on DecryptionFailed {
      return null;
    } on FormatException {
      return null;
    }
  }

  static VaultEntry _entryOf(String id, Map<String, dynamic> doc) {
    final type = doc['type'], data = doc['data'];
    if (type is! String || data is! Map<String, dynamic>) throw const FormatException('not a vault entry');
    return VaultEntry.fromJson(id, type, data);
  }

  SecureKey _requireUnlocked() {
    final key = _vaultKey;
    if (status != VaultStatus.unlocked || key == null) throw StateError('the vault is locked');
    return key;
  }

  /// Writes are serialized, and each one replaces the file atomically.
  Future<void> _save() {
    final snapshot = jsonEncode({
      'format': formatVersion,
      'vault_id': _vaultId,
      'kdf': _kdf!.toJson(),
      'wrap_pw': _wrapPw!.toJson(),
      'cursor': _cursor,
      if (_sealedAccount != null) 'account': _sealedAccount!.toJson(),
      'records': [for (final r in _records.values) r.toJson()],
    });
    // A failed write (a full disk, a permission problem) fails this save for
    // its caller, but must not poison the queue for every later write.
    final write = _writes.catchError((Object _) {}).then((_) async {
      final file = await _vaultFile;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename(file.path);
    });
    _writes = write;
    return write;
  }

  @override
  void dispose() {
    lock();
    super.dispose();
  }
}
