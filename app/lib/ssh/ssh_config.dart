/// Hosts from an OpenSSH client configuration (~/.ssh/config), for
/// importing: the named hosts, with the options Tildeck keeps.
///
/// As ssh_config(5) says, for each option the first value found wins, from
/// the `Host` blocks whose patterns match the host's name, in file order; so
/// a `Host *` block at the end gives defaults. `Match` blocks and `Include`
/// are not followed. A pattern with a wildcard or a negation names no host
/// of its own.
class SshConfigHost {
  SshConfigHost({
    required this.alias,
    this.hostName,
    this.user,
    this.port,
    this.identityFiles = const [],
    this.proxyJump,
  });

  /// The name after `Host`.
  final String alias;
  final String? hostName;
  final String? user;
  final int? port;

  /// Paths as written (they may start with ~).
  final List<String> identityFiles;

  /// The first hop of ProxyJump: an alias or [user@]host[:port].
  final String? proxyJump;

  String get address => hostName ?? alias;
}

class _Block {
  _Block(this.patterns);

  final List<String> patterns;
  final options = <String, List<String>>{};

  bool matches(String name) {
    var matched = false;
    for (final pattern in patterns) {
      final negated = pattern.startsWith('!');
      if (_glob(negated ? pattern.substring(1) : pattern).hasMatch(name)) {
        if (negated) return false;
        matched = true;
      }
    }
    return matched;
  }

  static RegExp _glob(String pattern) {
    final escaped = pattern.split('').map((ch) {
      if (ch == '*') return '.*';
      if (ch == '?') return '.';
      return RegExp.escape(ch);
    }).join();
    return RegExp('^$escaped\$', caseSensitive: false);
  }
}

List<SshConfigHost> parseSshConfig(String text) {
  final blocks = <_Block>[];
  // Options before any Host line apply to every host.
  var current = _Block(['*']);
  blocks.add(current);
  var inMatch = false;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = RegExp(r'^(\S+?)(?:\s*=\s*|\s+)(.*)$').firstMatch(line);
    if (match == null) continue;
    final keyword = match[1]!.toLowerCase();
    final value = match[2]!.trim();
    if (keyword == 'host') {
      inMatch = false;
      current = _Block(_words(value));
      blocks.add(current);
      continue;
    }
    if (keyword == 'match') {
      inMatch = true;
      continue;
    }
    if (inMatch) continue;
    current.options.putIfAbsent(keyword, () => []).add(_unquote(value));
  }

  final aliases = <String>[];
  for (final block in blocks.skip(1)) {
    for (final pattern in block.patterns) {
      if (pattern.contains(RegExp(r'[*?!]')) || aliases.contains(pattern)) continue;
      aliases.add(pattern);
    }
  }
  return [
    for (final alias in aliases)
      () {
        String? first(String option) {
          for (final block in blocks) {
            final values = block.options[option];
            if (values != null && values.isNotEmpty && block.matches(alias)) return values.first;
          }
          return null;
        }

        // IdentityFile is the one option that adds up across blocks.
        final identities = [
          for (final block in blocks)
            if (block.matches(alias)) ...?block.options['identityfile'],
        ];
        final proxyJump = first('proxyjump');
        return SshConfigHost(
          alias: alias,
          // %h is the name being connected to, %% a percent sign.
          hostName: first('hostname')?.replaceAllMapped(RegExp('%([h%])'), (m) => m[1] == 'h' ? alias : '%'),
          user: first('user'),
          port: int.tryParse(first('port') ?? ''),
          identityFiles: identities,
          proxyJump: proxyJump == null || proxyJump.toLowerCase() == 'none' ? null : proxyJump.split(',').first.trim(),
        );
      }(),
  ];
}

List<String> _words(String value) => [for (final m in RegExp(r'"([^"]*)"|(\S+)').allMatches(value)) m[1] ?? m[2]!];

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;
