import '../ssh/proxy.dart';
import '../ssh/ssh_connector.dart' show ConnectionProtocol, defaultBaudRate;

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
    ConnectionLogEntry.recordType => ConnectionLogEntry.fromJson(id, data),
    PortForwardEntry.recordType => PortForwardEntry.fromJson(id, data),
    ProxyEntry.recordType => ProxyEntry.fromJson(id, data),
    IdentityEntry.recordType => IdentityEntry.fromJson(id, data),
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
    this.jumpHostId,
    this.agentForwarding = false,
    this.proxyId,
    this.protocol = ConnectionProtocol.ssh,
    this.identityId,
    this.notes = '',
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

  /// Another saved host to connect through (like ssh -J). That host may
  /// have its own, which makes a chain.
  final String? jumpHostId;

  /// Lets the server use the vault's keys while connected (like ssh -A),
  /// for signing in from it onward. The keys never leave this device.
  final bool agentForwarding;

  /// A [ProxyEntry] id: the proxy this host is reached through when it
  /// connects directly (not through a jump host).
  final String? proxyId;

  /// SSH, or Telnet for devices that have nothing else.
  final ConnectionProtocol protocol;

  /// The [IdentityEntry] to sign in as; then the host's own username and
  /// credentials are not used.
  final String? identityId;

  /// Free text: what the server is for, who to ask, how to reach it.
  final String notes;

  bool get isTelnet => protocol == ConnectionProtocol.telnet;
  bool get isSerial => protocol == ConnectionProtocol.serial;

  /// Sign-in, keys, jump hosts, forwarding and files are SSH's alone.
  bool get isSsh => protocol == ConnectionProtocol.ssh;

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
    'jump_host_id': jumpHostId,
    'agent_forwarding': agentForwarding,
    'proxy_id': proxyId,
    'protocol': protocol.name,
    'identity_id': identityId,
    'notes': notes,
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
    jumpHostId: d['jump_host_id'] as String?,
    agentForwarding: d['agent_forwarding'] as bool? ?? false,
    proxyId: d['proxy_id'] as String?,
    protocol: ConnectionProtocol.values.byName(d['protocol'] as String? ?? 'ssh'),
    identityId: d['identity_id'] as String?,
    notes: d['notes'] as String? ?? '',
  );

  String get label {
    if (isSerial) return port == defaultBaudRate ? host : '$host $port';
    final address = port == (isTelnet ? 23 : 22) ? host : '$host:$port';
    return username.isEmpty ? address : '$username@$address';
  }
}

/// A private key, stored only inside the vault.
class KeyEntry extends VaultEntry {
  const KeyEntry({
    required super.id,
    required this.name,
    required this.privateKey,
    this.passphrase,
    this.keyType,
    this.fingerprint,
    this.publicKey,
    this.certificate,
  });

  static const recordType = 'key';

  final String name;
  final String privateKey;
  final String? passphrase;

  /// Read from the private key when it is saved, so the list need not
  /// decrypt it again; null for a key saved before they were kept.
  final String? keyType;
  final String? fingerprint;

  /// The line for authorized_keys.
  final String? publicKey;

  /// An OpenSSH certificate for this key (the -cert.pub line), signed by a
  /// certificate authority the servers trust; offered before the bare key.
  final String? certificate;

  KeyEntry withCertificate(String? certificate) => KeyEntry(
    id: id,
    name: name,
    privateKey: privateKey,
    passphrase: passphrase,
    keyType: keyType,
    fingerprint: fingerprint,
    publicKey: publicKey,
    certificate: certificate,
  );

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'name': name,
    'private_key': privateKey,
    'passphrase': passphrase,
    'key_type': keyType,
    'fingerprint': fingerprint,
    'public_key': publicKey,
    'certificate': certificate,
  };

  static KeyEntry fromJson(String id, Map<String, dynamic> d) => KeyEntry(
    id: id,
    name: d['name'] as String,
    privateKey: d['private_key'] as String,
    passphrase: d['passphrase'] as String?,
    keyType: d['key_type'] as String?,
    fingerprint: d['fingerprint'] as String?,
    publicKey: d['public_key'] as String?,
    certificate: d['certificate'] as String?,
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
  const SnippetEntry({required super.id, required this.name, required this.command, this.folder = ''});

  static const recordType = 'snippet';

  final String name;

  /// A folder to list it in; empty is none.
  final String folder;

  /// One or more lines, sent to the shell as typed, each followed by Enter.
  final String command;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {'name': name, 'command': command, 'folder': folder};

  static SnippetEntry fromJson(String id, Map<String, dynamic> d) => SnippetEntry(
    id: id,
    name: d['name'] as String,
    command: d['command'] as String,
    folder: (d['folder'] as String? ?? '').trim(),
  );
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
    this.jumpHostId,
    this.proxyId,
    this.identityId,
  });

  static const recordType = 'group';

  final String name;
  final String? username;

  /// A [KeyEntry] id for hosts that sign in with a key and choose none.
  final String? keyId;
  final String? startupSnippetId;
  final Map<String, String> env;

  /// The host the group's hosts connect through, unless they choose one.
  final String? jumpHostId;

  /// The proxy for the group's hosts, unless they choose one.
  final String? proxyId;

  /// The [IdentityEntry] the group's hosts sign in as, unless they choose
  /// their own.
  final String? identityId;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'name': name,
    'username': username,
    'key_id': keyId,
    'startup_snippet_id': startupSnippetId,
    'env': env,
    'jump_host_id': jumpHostId,
    'proxy_id': proxyId,
    'identity_id': identityId,
  };

  static GroupEntry fromJson(String id, Map<String, dynamic> d) => GroupEntry(
    id: id,
    name: d['name'] as String,
    username: d['username'] as String?,
    keyId: d['key_id'] as String?,
    startupSnippetId: d['startup_snippet_id'] as String?,
    env: {...?(d['env'] as Map?)?.cast<String, String>()},
    jumpHostId: d['jump_host_id'] as String?,
    proxyId: d['proxy_id'] as String?,
    identityId: d['identity_id'] as String?,
  );
}

/// Who to sign in as, saved once and chosen by any number of hosts and
/// groups: a username with a key, a saved password, or neither (the
/// password is asked at each connection). Changing it changes every host
/// that uses it.
class IdentityEntry extends VaultEntry {
  const IdentityEntry({required super.id, required this.name, required this.username, this.password, this.keyId});

  static const recordType = 'identity';

  final String name;
  final String username;
  final String? password;

  /// A [KeyEntry] id; with one, the identity signs in with the key.
  final String? keyId;

  HostAuth get auth => keyId != null ? HostAuth.key : HostAuth.password;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {'name': name, 'username': username, 'password': password, 'key_id': keyId};

  static IdentityEntry fromJson(String id, Map<String, dynamic> d) => IdentityEntry(
    id: id,
    name: d['name'] as String,
    username: d['username'] as String,
    password: d['password'] as String?,
    keyId: d['key_id'] as String?,
  );
}

/// A SOCKS5 or HTTP proxy that hosts may be reached through.
class ProxyEntry extends VaultEntry {
  const ProxyEntry({
    required super.id,
    required this.name,
    this.kind = ProxyKind.socks5,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  static const recordType = 'proxy';

  final String name;
  final ProxyKind kind;
  final String host;
  final int port;
  final String? username;
  final String? password;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'name': name,
    'kind': kind.name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
  };

  static ProxyEntry fromJson(String id, Map<String, dynamic> d) => ProxyEntry(
    id: id,
    name: d['name'] as String,
    kind: ProxyKind.values.byName(d['kind'] as String? ?? 'socks5'),
    host: d['host'] as String,
    port: d['port'] as int,
    username: d['username'] as String?,
    password: d['password'] as String?,
  );

  ProxyConfig get config => ProxyConfig(kind: kind, host: host, port: port, username: username, password: password);
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
  const PreferencesEntry({
    this.terminalTheme,
    this.fontSize,
    this.autocomplete,
    this.autoLockMinutes,
    this.fontFamily,
    this.lineHeight,
    this.cursorStyle,
    this.bell,
    this.scrollback,
    this.copyOnSelect,
    this.autoReconnect,
    this.highlight,
    this.highlightErrors,
    this.highlightWarnings,
    this.highlightSuccess,
  }) : super(id: fixedId);

  static const recordType = 'preferences';
  static const fixedId = '00000000-0000-4000-8000-000000000001';

  /// A theme id from lib/terminal/terminal_themes.dart; null is the default.
  final String? terminalTheme;
  final double? fontSize;

  /// Suggestions from the server's history and from snippets; null is on.
  final bool? autocomplete;

  /// Minutes without activity before the vault locks; null is
  /// [defaultAutoLockMinutes].
  final int? autoLockMinutes;

  static const defaultAutoLockMinutes = 15;
  static const autoLockChoices = [1, 5, 15, 30, 60];

  Duration get autoLock => Duration(minutes: autoLockMinutes ?? defaultAutoLockMinutes);

  // The terminal's look and behavior (lib/terminal/terminal_options.dart
  // reads them, with their defaults). Null is the default.
  final String? fontFamily;
  final double? lineHeight;

  /// block, underline, or bar.
  final String? cursorStyle;

  /// none, visual, or sound.
  final String? bell;

  /// Lines kept above the screen, for new sessions.
  final int? scrollback;
  final bool? copyOnSelect;
  final bool? autoReconnect;

  /// Keywords that stand out in the terminal; null lists are the defaults.
  final bool? highlight;
  final List<String>? highlightErrors;
  final List<String>? highlightWarnings;
  final List<String>? highlightSuccess;

  PreferencesEntry copyWith({
    String? terminalTheme,
    double? fontSize,
    bool? autocomplete,
    int? autoLockMinutes,
    String? fontFamily,
    double? lineHeight,
    String? cursorStyle,
    String? bell,
    int? scrollback,
    bool? copyOnSelect,
    bool? autoReconnect,
    bool? highlight,
    List<String>? highlightErrors,
    List<String>? highlightWarnings,
    List<String>? highlightSuccess,
  }) => PreferencesEntry(
    terminalTheme: terminalTheme ?? this.terminalTheme,
    fontSize: fontSize ?? this.fontSize,
    autocomplete: autocomplete ?? this.autocomplete,
    autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
    fontFamily: fontFamily ?? this.fontFamily,
    lineHeight: lineHeight ?? this.lineHeight,
    cursorStyle: cursorStyle ?? this.cursorStyle,
    bell: bell ?? this.bell,
    scrollback: scrollback ?? this.scrollback,
    copyOnSelect: copyOnSelect ?? this.copyOnSelect,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    highlight: highlight ?? this.highlight,
    highlightErrors: highlightErrors ?? this.highlightErrors,
    highlightWarnings: highlightWarnings ?? this.highlightWarnings,
    highlightSuccess: highlightSuccess ?? this.highlightSuccess,
  );

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'terminal_theme': terminalTheme,
    'font_size': fontSize,
    'autocomplete': autocomplete,
    'auto_lock_minutes': autoLockMinutes,
    'font_family': fontFamily,
    'line_height': lineHeight,
    'cursor_style': cursorStyle,
    'bell': bell,
    'scrollback': scrollback,
    'copy_on_select': copyOnSelect,
    'auto_reconnect': autoReconnect,
    'highlight': highlight,
    'highlight_errors': highlightErrors,
    'highlight_warnings': highlightWarnings,
    'highlight_success': highlightSuccess,
  };

  static PreferencesEntry fromJson(String id, Map<String, dynamic> d) => PreferencesEntry(
    terminalTheme: d['terminal_theme'] as String?,
    fontSize: (d['font_size'] as num?)?.toDouble(),
    autocomplete: d['autocomplete'] as bool?,
    // Only a listed choice: a synced value cannot make the lock wait for
    // hours, or never come.
    autoLockMinutes: autoLockChoices.contains(d['auto_lock_minutes']) ? d['auto_lock_minutes'] as int : null,
    fontFamily: d['font_family'] as String?,
    lineHeight: (d['line_height'] as num?)?.toDouble(),
    cursorStyle: d['cursor_style'] as String?,
    bell: d['bell'] as String?,
    scrollback: d['scrollback'] as int?,
    copyOnSelect: d['copy_on_select'] as bool?,
    autoReconnect: d['auto_reconnect'] as bool?,
    highlight: d['highlight'] as bool?,
    highlightErrors: (d['highlight_errors'] as List?)?.cast<String>(),
    highlightWarnings: (d['highlight_warnings'] as List?)?.cast<String>(),
    highlightSuccess: (d['highlight_success'] as List?)?.cast<String>(),
  );
}

/// One connection, for the history: where, when, from which device, and
/// how it ended. Encrypted and synced like every record.
class ConnectionLogEntry extends VaultEntry {
  const ConnectionLogEntry({
    required super.id,
    required this.label,
    required this.startedAt,
    this.hostId,
    this.endedAt,
    this.device,
    this.failed = false,
  });

  static const recordType = 'connection';

  /// The saved host, when the connection came from one.
  final String? hostId;

  /// user@host:port at the time.
  final String label;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// The device name, when this device has a sync account.
  final String? device;

  /// The connection did not open, or it ended with an error.
  final bool failed;

  ConnectionLogEntry ended(DateTime at, {required bool failed}) => ConnectionLogEntry(
    id: id,
    label: label,
    startedAt: startedAt,
    hostId: hostId,
    endedAt: at,
    device: device,
    failed: failed,
  );

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'host_id': hostId,
    'label': label,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'device': device,
    'failed': failed,
  };

  static ConnectionLogEntry fromJson(String id, Map<String, dynamic> d) => ConnectionLogEntry(
    id: id,
    hostId: d['host_id'] as String?,
    label: d['label'] as String,
    startedAt: DateTime.parse(d['started_at'] as String),
    endedAt: d['ended_at'] == null ? null : DateTime.parse(d['ended_at'] as String),
    device: d['device'] as String?,
    failed: d['failed'] as bool? ?? false,
  );
}

enum ForwardKind { local, remote, dynamic }

/// A port forwarding rule through a saved host. Local: listen here on the
/// bind address and connect from the server to the destination. Remote:
/// listen on the server and connect from here to the destination. Dynamic:
/// a SOCKS5 proxy here whose connections leave from the server.
class PortForwardEntry extends VaultEntry {
  const PortForwardEntry({
    required super.id,
    required this.name,
    required this.hostId,
    this.kind = ForwardKind.local,
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    this.destHost = '',
    this.destPort = 0,
  });

  static const recordType = 'port_forward';

  final String name;
  final String hostId;
  final ForwardKind kind;
  final String bindHost;
  final int bindPort;

  /// Unused for dynamic forwarding.
  final String destHost;
  final int destPort;

  @override
  String get type => recordType;

  @override
  Map<String, Object?> dataJson() => {
    'name': name,
    'host_id': hostId,
    'kind': kind.name,
    'bind_host': bindHost,
    'bind_port': bindPort,
    'dest_host': destHost,
    'dest_port': destPort,
  };

  static PortForwardEntry fromJson(String id, Map<String, dynamic> d) => PortForwardEntry(
    id: id,
    name: d['name'] as String,
    hostId: d['host_id'] as String,
    kind: ForwardKind.values.byName(d['kind'] as String? ?? 'local'),
    bindHost: d['bind_host'] as String? ?? '127.0.0.1',
    bindPort: d['bind_port'] as int,
    destHost: d['dest_host'] as String? ?? '',
    destPort: d['dest_port'] as int? ?? 0,
  );

  /// How the rule reads, as in ssh: -L 8080:db:5432, -R, or -D.
  String get summary => switch (kind) {
    ForwardKind.local => '$bindPort \u2192 $destHost:$destPort',
    ForwardKind.remote => 'server:$bindPort \u2192 $destHost:$destPort',
    ForwardKind.dynamic => 'SOCKS5 $bindHost:$bindPort',
  };
}
