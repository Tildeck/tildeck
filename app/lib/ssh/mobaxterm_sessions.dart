import 'ssh_config.dart';

/// A MobaXterm session line: `name=#icon#type%host%port%user%...`.
final _session = RegExp(r'^([^=]+)=\s*#\d+#(\d+)%(.*)$');

/// Whether [text] is MobaXterm's sessions: its exported .mxtsessions file,
/// or MobaXterm.ini, both with [Bookmarks] sections.
bool looksLikeMobaXterm(String text) =>
    RegExp(r'^\[Bookmarks(_\d+)?\]\s*$', multiLine: true).hasMatch(text) &&
    text.split(RegExp(r'\r?\n')).any((l) => _session.hasMatch(l.trim()));

/// The SSH and Telnet sessions in MobaXterm's sessions, with their folders
/// (SubRep). Other kinds (RDP, VNC, FTP, serial and so on) are left out, as
/// are key files: MobaXterm's paths point into its own profile.
List<SshConfigHost> parseMobaXterm(String text) {
  final hosts = <SshConfigHost>[];
  final names = <String>{};
  var folder = '';
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      folder = '';
      continue;
    }
    if (line.startsWith('SubRep=')) {
      folder = line.substring(7).split(r'\').where((p) => p.trim().isNotEmpty).join('/');
      continue;
    }
    final m = _session.firstMatch(line);
    if (m == null) continue;
    // The session type: 0 is SSH, 1 is Telnet.
    final type = m[2];
    if (type != '0' && type != '1') continue;
    final fields = m[3]!.split('%');
    final host = fields.isNotEmpty ? fields[0].trim() : '';
    if (host.isEmpty) continue;
    final user = fields.length > 2 ? fields[2].trim() : '';
    final base = m[1]!.trim();
    var name = base;
    // Names identify hosts in the import: the same one twice gets a number.
    for (var n = 2; !names.add(name); n++) {
      name = '$base ($n)';
    }
    hosts.add(
      SshConfigHost(
        alias: name,
        hostName: host,
        user: user.isEmpty ? null : user,
        port: fields.length > 1 ? int.tryParse(fields[1].trim()) : null,
        group: folder,
        telnet: type == '1',
      ),
    );
  }
  return hosts;
}
