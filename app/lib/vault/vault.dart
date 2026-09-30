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
  const StoredRecord({required this.id, required this.version, this.deleted = false, this.sealed});

  final String id;
  final int version;

  /// A tombstone: the record was deleted and keeps no content, so the
  /// deletion can reach other devices once sync exists.
  final bool deleted;
  final Sealed? sealed;

  Map<String, Object?> toJson() => {'id': id, 'version': version, 'deleted': deleted, ...?sealed?.toJson()};

  static StoredRecord fromJson(Map<String, dynamic> j) => StoredRecord(
    id: j['id'] as String,
    version: j['version'] as int,
    deleted: j['deleted'] as bool? ?? false,
    sealed: j['ct'] == null ? null : Sealed.fromJson(j),
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

  static const formatVersion = 1;

  VaultStatus status = VaultStatus.loading;

  File? _file;
  String? _vaultId;
  KdfParams? _kdf;
  Sealed? _wrapPw;
  final _records = <String, StoredRecord>{};

  SecureKey? _vaultKey;
  final _entries = <String, VaultEntry>{};

  /// Records that failed to decrypt at unlock: changed on disk, or damaged.
  /// They are kept untouched and reported, never silently dropped.
  final damaged = <String>[];

  Future<void> _writes = Future.value();

  Future<File> get _vaultFile async => _file ??= await resolveFile();

  Future<void> load() async {
    final file = await _vaultFile;
    if (!await file.exists()) {
      status = VaultStatus.missing;
    } else {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (j['format'] != formatVersion) throw const FormatException('unsupported vault format');
      _vaultId = j['vault_id'] as String;
      _kdf = KdfParams.fromJson(j['kdf'] as Map<String, dynamic>);
      _wrapPw = Sealed.fromJson(j['wrap_pw'] as Map<String, dynamic>);
      _records
        ..clear()
        ..addEntries(
          (j['records'] as List).map((r) {
            final record = StoredRecord.fromJson(r as Map<String, dynamic>);
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
    _vaultKey = vaultKey;
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
    _entries.clear();
    damaged.clear();
    for (final record in _records.values) {
      if (record.deleted || record.sealed == null) continue;
      try {
        final plain = crypto.decryptRecord(vaultKey, _vaultId!, record.id, record.version, record.sealed!);
        final doc = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        _entries[record.id] = VaultEntry.fromJson(
          record.id,
          doc['type'] as String,
          doc['data'] as Map<String, dynamic>,
        );
      } on DecryptionFailed {
        damaged.add(record.id);
      } on FormatException {
        damaged.add(record.id);
      }
    }
    _vaultKey = vaultKey;
    status = VaultStatus.unlocked;
    notifyListeners();
    return true;
  }

  /// Forgets the vault key and every decrypted entry.
  void lock() {
    if (status != VaultStatus.unlocked) return;
    _vaultKey?.dispose();
    _vaultKey = null;
    _entries.clear();
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

  /// Adds or replaces an entry as the next version of its record.
  Future<void> put(VaultEntry entry) async {
    final key = _requireUnlocked();
    final version = (_records[entry.id]?.version ?? 0) + 1;
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
    _records[entry.id] = StoredRecord(id: entry.id, version: version, sealed: sealed);
    _entries[entry.id] = entry;
    notifyListeners();
    await _save();
  }

  /// Deletes an entry, keeping a tombstone for its record.
  Future<void> delete(String id) async {
    _requireUnlocked();
    final current = _records[id];
    if (current == null || current.deleted) return;
    _records[id] = StoredRecord(id: id, version: current.version + 1, deleted: true);
    _entries.remove(id);
    notifyListeners();
    await _save();
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
      'records': [for (final r in _records.values) r.toJson()],
    });
    return _writes = _writes.then((_) async {
      final file = await _vaultFile;
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename(file.path);
    });
  }

  @override
  void dispose() {
    lock();
    super.dispose();
  }
}
