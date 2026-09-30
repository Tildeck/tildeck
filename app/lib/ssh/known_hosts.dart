import 'dart:convert';
import 'dart:io';

import '../vault/models.dart';
import '../vault/vault.dart';

/// A host key the user has trusted, identified by host and port.
class KnownHost {
  const KnownHost({required this.type, required this.fingerprint});

  /// The key algorithm, for example `ssh-ed25519`.
  final String type;

  /// OpenSSH-style `SHA256:<base64>` fingerprint of the host key.
  final String fingerprint;
}

/// What the stored keys say about the key a server just presented.
enum HostKeyStatus {
  /// Never connected to this host and port before.
  unknown,

  /// The same key as last time.
  trusted,

  /// A different key than the one trusted before: possibly an attacker in
  /// the middle, possibly a reinstalled server. Never accepted silently.
  changed,
}

/// The trusted host keys.
abstract class KnownHosts {
  Future<KnownHost?> lookup(String host, int port);

  /// Trust a key for a host, replacing whatever was trusted before.
  Future<void> trust(String host, int port, KnownHost key);

  Future<HostKeyStatus> check(String host, int port, KnownHost presented) async {
    final known = await lookup(host, port);
    if (known == null) return HostKeyStatus.unknown;
    return known.type == presented.type && known.fingerprint == presented.fingerprint
        ? HostKeyStatus.trusted
        : HostKeyStatus.changed;
  }

  static String keyFor(String host, int port) => '${host.toLowerCase()}:$port';
}

/// Trusted keys kept in memory only, for tests.
class MemoryKnownHosts extends KnownHosts {
  final _hosts = <String, KnownHost>{};

  @override
  Future<KnownHost?> lookup(String host, int port) async => _hosts[KnownHosts.keyFor(host, port)];

  @override
  Future<void> trust(String host, int port, KnownHost key) async => _hosts[KnownHosts.keyFor(host, port)] = key;
}

/// Trusted keys as encrypted records in the vault, so they sync with it.
class VaultKnownHosts extends KnownHosts {
  VaultKnownHosts(this.vault);

  final Vault vault;

  KnownHostEntry? _find(String host, int port) {
    final key = KnownHosts.keyFor(host, port);
    for (final e in vault.knownHosts) {
      if (KnownHosts.keyFor(e.host, e.port) == key) return e;
    }
    return null;
  }

  @override
  Future<KnownHost?> lookup(String host, int port) async {
    final e = _find(host, port);
    return e == null ? null : KnownHost(type: e.keyType, fingerprint: e.fingerprint);
  }

  @override
  Future<void> trust(String host, int port, KnownHost key) => vault.put(
    KnownHostEntry(
      id: _find(host, port)?.id ?? vault.newId(),
      host: host,
      port: port,
      keyType: key.type,
      fingerprint: key.fingerprint,
    ),
  );

  /// Moves keys trusted before the vault existed (a plain JSON file of public
  /// fingerprints) into the vault, then removes the file.
  Future<int> importLegacyFile(File file) async {
    if (!await file.exists()) return 0;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    var imported = 0;
    for (final MapEntry(:key, :value) in data.entries) {
      final split = key.lastIndexOf(':');
      final port = int.tryParse(key.substring(split + 1));
      final v = value as Map<String, dynamic>;
      if (split < 1 || port == null || await lookup(key.substring(0, split), port) != null) continue;
      await trust(
        key.substring(0, split),
        port,
        KnownHost(type: v['type'] as String, fingerprint: v['fingerprint'] as String),
      );
      imported++;
    }
    await file.delete();
    return imported;
  }
}
