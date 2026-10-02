import 'dart:convert';

import 'package:sodium/sodium_sumo.dart' show SecureKey;

import 'models.dart';
import 'vault.dart';
import 'vault_crypto.dart';

/// An encrypted backup of the vault in one file, for keeping or moving
/// without a sync server. It holds the records as the vault stores them
/// (encrypted with the vault key) and the vault key wrapped under the
/// master password, as the vault file does; never this device's account,
/// its token, or biometric unlock.
const backupFormat = 'tildeck-backup';
const backupVersion = 1;

/// The file's text. The vault must be unlocked.
String exportBackup(Vault vault) => const JsonEncoder.withIndent(' ').convert({
  'format': backupFormat,
  'version': backupVersion,
  'vault_id': vault.vaultId,
  'kdf': vault.kdf.toJson(),
  'wrap_pw': vault.wrapPw.toJson(),
  'records': [
    for (final r in vault.storedRecords)
      if (!r.deleted && r.sealed != null) r.toJson(),
  ],
});

/// Why a backup could not be read.
enum BackupProblem { notABackup, newerVersion, wrongPassword }

class BackupException implements Exception {
  const BackupException(this.problem);
  final BackupProblem problem;
}

/// The entries in a backup, opened with the master password it was made
/// under. Records that do not open, or of a kind this version does not
/// know, are left out.
Future<List<VaultEntry>> readBackup(String text, String password, VaultCrypto crypto) async {
  final Map<String, dynamic> j;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> || decoded['format'] != backupFormat) {
      throw const BackupException(BackupProblem.notABackup);
    }
    j = decoded;
  } on FormatException {
    throw const BackupException(BackupProblem.notABackup);
  }
  if ((j['version'] as int? ?? 0) > backupVersion) throw const BackupException(BackupProblem.newerVersion);
  final vaultId = j['vault_id'] as String;
  final KdfParams kdf;
  try {
    kdf = KdfParams.fromJson(j['kdf'] as Map<String, dynamic>);
  } on UnsafeKdf {
    // Settings no vault of ours writes: not a backup to trust.
    throw const BackupException(BackupProblem.notABackup);
  }
  final keys = await crypto.deriveKeys(password, kdf);
  final SecureKey vaultKey;
  try {
    vaultKey = crypto.unwrapVaultKey(
      keys.keyEncryptionKey,
      Sealed.fromJson(j['wrap_pw'] as Map<String, dynamic>),
      vaultId,
    );
  } on DecryptionFailed {
    throw const BackupException(BackupProblem.wrongPassword);
  } finally {
    keys.dispose();
  }
  try {
    return [
      for (final r in (j['records'] as List).cast<Map<String, dynamic>>())
        ?_open(crypto, vaultKey, vaultId, StoredRecord.fromJson(r)),
    ];
  } finally {
    vaultKey.dispose();
  }
}

VaultEntry? _open(VaultCrypto crypto, SecureKey key, String vaultId, StoredRecord record) {
  final sealed = record.sealed;
  if (sealed == null) return null;
  try {
    final plain = crypto.decryptRecord(key, vaultId, record.id, record.version, sealed);
    final doc = jsonDecode(utf8.decode(plain));
    plain.fillRange(0, plain.length, 0);
    if (doc is! Map<String, dynamic>) return null;
    final type = doc['type'], data = doc['data'];
    if (type is! String || data is! Map<String, dynamic>) return null;
    return VaultEntry.fromJson(record.id, type, data);
  } on DecryptionFailed {
    return null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

/// Adds [entries] to the vault: those it does not have yet. What it has is
/// kept as it is, never overwritten by an older copy.
Future<({int added, int kept})> importBackup(Vault vault, List<VaultEntry> entries) async {
  var added = 0, kept = 0;
  for (final entry in entries) {
    if (vault.entry<VaultEntry>(entry.id) != null) {
      kept++;
      continue;
    }
    await vault.put(entry);
    added++;
  }
  return (added: added, kept: kept);
}

/// "tildeck-backup-2026-10-02.json"
String backupFileName(DateTime now) =>
    'tildeck-backup-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
