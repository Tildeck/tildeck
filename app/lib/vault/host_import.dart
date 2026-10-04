import '../ssh/keys.dart';
import '../ssh/ppk.dart';
import '../ssh/ssh_config.dart';
import '../ssh/ssh_connector.dart' show ConnectionProtocol;
import 'models.dart';
import 'vault.dart';

/// What an import added.
class HostImportResult {
  const HostImportResult({required this.hosts, required this.keys, required this.unreadableKeys});

  final int hosts;
  final int keys;

  /// Key files that could not be read, or need a passphrase: their hosts
  /// were saved to sign in with a password, and the keys can be added on
  /// the Keys page.
  final List<String> unreadableKeys;
}

/// The username ssh uses when the configuration names none: this
/// computer's user.
String sshDefaultUser(Map<String, String> environment) => environment['USER'] ?? environment['USERNAME'] ?? '';

/// Whether the vault already has [host]: the same address, port, and user.
bool alreadySaved(Vault vault, SshConfigHost host, String defaultUser) => vault.hosts.any(
  (h) =>
      h.host == host.address &&
      h.port == (host.port ?? (host.telnet ? 23 : 22)) &&
      h.username == (host.user ?? (host.telnet ? '' : defaultUser)),
);

/// Saves [chosen] as hosts. Their key files are read through [readFile]
/// (null when missing) and added as keys, unless the vault has the same key
/// already. A ProxyJump naming another imported host, or a saved one by
/// name, becomes the host's jump host.
Future<HostImportResult> importSshHosts(
  Vault vault,
  List<SshConfigHost> chosen, {
  required Future<String?> Function(String path) readFile,
  required String defaultUser,
}) async {
  final keyIds = <String, String?>{};
  final unreadable = <String>[];
  var keysAdded = 0;
  for (final host in chosen) {
    for (final path in host.identityFiles) {
      if (keyIds.containsKey(path)) continue;
      final name = path.split(RegExp(r'[\\/]')).last;
      final file = await readFile(path);
      // A PuTTY key (as PuTTY sessions name them) comes in as OpenSSH when it
      // has no passphrase; one with a passphrase is added on the Keys page.
      final text = file != null && looksLikePpk(file) ? _openPpk(file) : file;
      final info = text == null ? null : readKey(text, comment: name);
      if (text == null || info == null) {
        keyIds[path] = null;
        unreadable.add(path);
        continue;
      }
      final existing = vault.keys.where((k) => k.fingerprint == info.fingerprint).firstOrNull;
      if (existing != null) {
        keyIds[path] = existing.id;
        continue;
      }
      final id = vault.newId();
      await vault.put(
        KeyEntry(
          id: id,
          name: name,
          privateKey: text,
          keyType: info.type,
          fingerprint: info.fingerprint,
          publicKey: info.publicKey,
        ),
      );
      keyIds[path] = id;
      keysAdded++;
    }
  }

  final ids = {for (final host in chosen) host.alias: vault.newId()};
  String? jumpFor(SshConfigHost host) {
    final hop = host.proxyJump;
    if (hop == null) return null;
    // [user@]name[:port]: the name is an alias here, or a saved host's name.
    final name = hop.replaceFirst(RegExp(r'^[^@]*@'), '').replaceFirst(RegExp(r':\d+$'), '');
    return ids[name] ?? vault.hosts.where((h) => h.name == name || h.host == name).firstOrNull?.id;
  }

  for (final host in chosen) {
    final keyId = host.identityFiles.map((p) => keyIds[p]).nonNulls.firstOrNull;
    await vault.put(
      HostEntry(
        id: ids[host.alias]!,
        name: host.alias,
        host: host.address,
        port: host.port ?? (host.telnet ? 23 : 22),
        // Telnet signs in inside the terminal: no user unless one was given.
        username: host.user ?? (host.telnet ? '' : defaultUser),
        auth: keyId == null ? HostAuth.password : HostAuth.key,
        keyId: keyId,
        jumpHostId: jumpFor(host),
        group: host.group,
        tags: host.tags,
        protocol: host.telnet ? ConnectionProtocol.telnet : ConnectionProtocol.ssh,
      ),
    );
  }
  return HostImportResult(hosts: chosen.length, keys: keysAdded, unreadableKeys: unreadable);
}

String? _openPpk(String text) {
  try {
    return ppkToOpenSsh(text);
  } on PpkException {
    return null;
  }
}
