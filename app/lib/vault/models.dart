/// What the vault stores. Each entry is one encrypted record; the record type
/// is inside the ciphertext, so storage (and later the sync server) cannot
/// tell hosts from keys.
sealed class VaultEntry {
  const VaultEntry({required this.id});

  final String id;

  String get type;
  Map<String, Object?> dataJson();

  /// Null for a type this version does not know: a record from a newer
  /// version of the app. It stays in the vault untouched, and is not shown.
  static VaultEntry? fromJson(String id, String type, Map<String, dynamic> data) => switch (type) {
    HostEntry.recordType => HostEntry.fromJson(id, data),
    KeyEntry.recordType => KeyEntry.fromJson(id, data),
    KnownHostEntry.recordType => KnownHostEntry.fromJson(id, data),
    SnippetEntry.recordType => SnippetEntry.fromJson(id, data),
    GroupEntry.recordType => GroupEntry.fromJson(id, data),
    PreferencesEntry.recordType => PreferencesEntry.fromJson(id, data),
    _ => null,
  };
}

enum HostAuth { password, key }

/// A saved server. Its group is a name; hosts with the same group name are
/// listed together.
class HostEntry extends VaultEntry {
  const HostEntry({
    required super.id,
    required this.name,
    this.group = '',
    required this.host,
    this.port = 22,
    required this.username,
    this.auth = HostAuth.password,
    this.password,
    this.keyId,
    this.startupSnippetId,
    this.tags = const [],
    this.env = const {},
  });

  static const recordType = 'host';

  final String name;
  final String group;
  final String host;
  final int port;
  final String username;
  final HostAuth auth;

  /// Saved only when the user chooses to; otherwise asked at connect time.
  final String? password;

  /// A [KeyEntry] id, for key authentication.
  final String? keyId;

  /// A [SnippetEntry] id, run in the shell as soon as the session opens.
  final String? startupSnippetId;

  /// Free labels for finding hosts.
  final List<String> tags;

  /// Environment variables sent when the session opens (the server accepts
  /// only those its AcceptEnv allows).
  final Map<String, String> env;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'name': name,
    'group': group,
    'host': host,
    'port': port,
    'username': username,
    'auth': auth.name,
    'password': password,
    'key_id': keyId,
    'startup_snippet_id': startupSnippetId,
    'tags': tags,
    'env': env,
  };

  static HostEntry fromJson(String id, Map<String, dynamic> d) => HostEntry(
    id: id,
    name: d['name'] as String,
    group: d['group'] as String? ?? '',
    host: d['host'] as String,
    port: d['port'] as int? ?? 22,
    username: d['username'] as String,
    auth: HostAuth.values.byName(d['auth'] as String? ?? 'password'),
    password: d['password'] as String?,
    keyId: d['key_id'] as String?,
    startupSnippetId: d['startup_snippet_id'] as String?,
    tags: [...?(d['tags'] as List?)?.cast<String>()],
    env: {...?(d['env'] as Map?)?.cast<String, String>()},
  );

  String get label => port == 22 ? '$username@$host' : '$username@$host:$port';
}

/// A private key, stored only inside the vault.
class KeyEntry extends VaultEntry {
  const KeyEntry({required super.id, required this.name, required this.privateKey, this.passphrase});

  static const recordType = 'key';

  final String name;
  final String privateKey;
  final String? passphrase;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {'name': name, 'private_key': privateKey, 'passphrase': passphrase};

  static KeyEntry fromJson(String id, Map<String, dynamic> d) => KeyEntry(
    id: id,
    name: d['name'] as String,
    privateKey: d['private_key'] as String,
    passphrase: d['passphrase'] as String?,
  );
}

/// A server key the user trusted, for one host and port.
class KnownHostEntry extends VaultEntry {
  const KnownHostEntry({
    required super.id,
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  static const recordType = 'known_host';

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {'host': host, 'port': port, 'key_type': keyType, 'fingerprint': fingerprint};

  static KnownHostEntry fromJson(String id, Map<String, dynamic> d) => KnownHostEntry(
    id: id,
    host: d['host'] as String,
    port: d['port'] as int,
    keyType: d['key_type'] as String,
    fingerprint: d['fingerprint'] as String,
  );
}

/// A saved command or script: run in an open session, on several hosts at
/// once, or when a host's session starts.
class SnippetEntry extends VaultEntry {
  const SnippetEntry({required super.id, required this.name, required this.command});

  static const recordType = 'snippet';

  final String name;

  /// One or more lines, sent to the shell as typed, each followed by Enter.
  final String command;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {'name': name, 'command': command};

  static SnippetEntry fromJson(String id, Map<String, dynamic> d) =>
      SnippetEntry(id: id, name: d['name'] as String, command: d['command'] as String);
}

/// Settings shared by every host in a group (hosts name their group). A
/// host's own value wins; an empty one takes the group's.
class GroupEntry extends VaultEntry {
  const GroupEntry({
    required super.id,
    required this.name,
    this.username,
    this.keyId,
    this.startupSnippetId,
    this.env = const {},
  });

  static const recordType = 'group';

  final String name;
  final String? username;

  /// A [KeyEntry] id for hosts that sign in with a key and choose none.
  final String? keyId;
  final String? startupSnippetId;
  final Map<String, String> env;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'name': name,
    'username': username,
    'key_id': keyId,
    'startup_snippet_id': startupSnippetId,
    'env': env,
  };

  static GroupEntry fromJson(String id, Map<String, dynamic> d) => GroupEntry(
    id: id,
    name: d['name'] as String,
    username: d['username'] as String?,
    keyId: d['key_id'] as String?,
    startupSnippetId: d['startup_snippet_id'] as String?,
    env: {...?(d['env'] as Map?)?.cast<String, String>()},
  );
}

/// Environment variables written one per line as NAME=value. Null when a
/// line is not one; blank lines are skipped.
Map<String, String>? parseEnv(String text) {
  final result = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) return null;
    final name = line.substring(0, eq).trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) return null;
    result[name] = line.substring(eq + 1);
  }
  return result;
}

String formatEnv(Map<String, String> env) => [for (final e in env.entries) '${e.key}=${e.value}'].join('\n');

/// The user's preferences, one record with a fixed id on every device, so
/// they sync and a change on one device reaches the others.
class PreferencesEntry extends VaultEntry {
  const PreferencesEntry({this.terminalTheme, this.fontSize}) : super(id: fixedId);

  static const recordType = 'preferences';
  static const fixedId = '00000000-0000-4000-8000-000000000001';

  /// A theme id from lib/terminal/terminal_themes.dart; null is the default.
  final String? terminalTheme;
  final double? fontSize;

  PreferencesEntry copyWith({String? terminalTheme, double? fontSize}) =>
      PreferencesEntry(terminalTheme: terminalTheme ?? this.terminalTheme, fontSize: fontSize ?? this.fontSize);

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {'terminal_theme': terminalTheme, 'font_size': fontSize};

  static PreferencesEntry fromJson(String id, Map<String, dynamic> d) =>
      PreferencesEntry(terminalTheme: d['terminal_theme'] as String?, fontSize: (d['font_size'] as num?)?.toDouble());
}
