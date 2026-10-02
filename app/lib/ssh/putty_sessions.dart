import 'dart:io';

import 'ssh_config.dart';

/// PuTTY's saved sessions, from the Windows registry
/// (HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions), read with
/// `reg query`, which every Windows has.
const puttySessionsKey = r'HKCU\Software\SimonTatham\PuTTY\Sessions';

/// The output of `reg query <key> /s`, or null where there is none.
Future<String?> readPuttyRegistry() async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run('reg', ['query', puttySessionsKey, '/s']);
    return result.exitCode == 0 ? result.stdout as String : null;
  } on ProcessException {
    return null;
  }
}

/// The SSH and Telnet sessions in `reg query` output. PuTTY's own
/// "Default Settings" and sessions without a host are left out.
List<SshConfigHost> parsePuttyRegistry(String output) {
  final sessions = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    final key = RegExp(r'\\Sessions\\(.+)$', caseSensitive: false).firstMatch(line);
    if (key != null && !line.startsWith(' ')) {
      current = sessions[Uri.decodeComponent(key[1]!)] = {};
      continue;
    }
    final value = RegExp(r'^\s+(\S+)\s+REG_(?:SZ|DWORD|EXPAND_SZ)\s*(.*)$').firstMatch(line);
    if (value != null && current != null) current[value[1]!] = value[2]!.trim();
  }
  int? number(String? text) {
    if (text == null) return null;
    return text.startsWith('0x') ? int.tryParse(text.substring(2), radix: 16) : int.tryParse(text);
  }

  return [
    for (final MapEntry(key: name, value: v) in sessions.entries)
      if (name != 'Default Settings' &&
          (v['HostName'] ?? '').isNotEmpty &&
          (v['Protocol'] == null || v['Protocol'] == 'ssh' || v['Protocol'] == 'telnet'))
        () {
          // PuTTY keeps "user@host" in HostName when the user typed it so.
          final hostName = v['HostName']!;
          final at = hostName.lastIndexOf('@');
          final user = (v['UserName'] ?? '').isNotEmpty ? v['UserName'] : (at > 0 ? hostName.substring(0, at) : null);
          return SshConfigHost(
            alias: name,
            hostName: at > 0 ? hostName.substring(at + 1) : hostName,
            user: user,
            port: number(v['PortNumber']),
            identityFiles: [if ((v['PublicKeyFile'] ?? '').isNotEmpty) v['PublicKeyFile']!],
            telnet: v['Protocol'] == 'telnet',
          );
        }(),
  ];
}
