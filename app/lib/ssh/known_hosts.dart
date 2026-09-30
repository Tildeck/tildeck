import 'dart:convert';
import 'dart:io';

/// A host key the user has trusted, identified by host and port.
class KnownHost {
  const KnownHost({required this.type, required this.fingerprint});

  /// The key algorithm, for example `ssh-ed25519`.
  final String type;

  /// OpenSSH-style `SHA256:<base64>` fingerprint of the host key.
  final String fingerprint;

  Map<String, String> toJson() => {'type': type, 'fingerprint': fingerprint};

  static KnownHost fromJson(Map<String, dynamic> json) =>
      KnownHost(type: json['type'] as String, fingerprint: json['fingerprint'] as String);
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

/// The trusted host keys. Host keys are public, so they are stored as plain
/// JSON in the app's support directory until the vault (product step 3)
/// takes them over as synced records.
class KnownHostsStore {
  /// [resolveFile] finds the file on first use (the app support directory is
  /// only known asynchronously).
  KnownHostsStore(Future<File> Function() resolveFile) : _resolveFile = resolveFile;

  /// A store that lives only in memory, for tests.
  KnownHostsStore.memory() : _resolveFile = null;

  final Future<File> Function()? _resolveFile;
  File? _file;
  Map<String, KnownHost>? _hosts;

  static String keyFor(String host, int port) => '${host.toLowerCase()}:$port';

  Future<Map<String, KnownHost>> _load() async {
    if (_hosts != null) return _hosts!;
    final file = _file ??= await _resolveFile?.call();
    if (file == null || !await file.exists()) return _hosts = {};
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return _hosts = data.map((k, v) => MapEntry(k, KnownHost.fromJson(v as Map<String, dynamic>)));
  }

  Future<KnownHost?> lookup(String host, int port) async => (await _load())[keyFor(host, port)];

  Future<HostKeyStatus> check(String host, int port, KnownHost presented) async {
    final known = await lookup(host, port);
    if (known == null) return HostKeyStatus.unknown;
    return known.type == presented.type && known.fingerprint == presented.fingerprint
        ? HostKeyStatus.trusted
        : HostKeyStatus.changed;
  }

  /// Trust a key for a host, replacing whatever was trusted before.
  Future<void> trust(String host, int port, KnownHost key) async {
    final hosts = await _load();
    hosts[keyFor(host, port)] = key;
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(hosts.map((k, v) => MapEntry(k, v.toJson()))), flush: true);
    await tmp.rename(file.path);
  }
}
