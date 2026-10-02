import '../ssh/ssh_config.dart';
import 'models.dart';

/// Hosts as CSV, for moving them in and out of other tools: Termius's
/// export, a spreadsheet. No passwords or keys go out.
const _columns = ['name', 'host', 'port', 'username', 'group', 'tags', 'protocol'];

/// The header names other tools use, mapped to ours.
const _aliases = {
  'name': 'name',
  'label': 'name',
  'alias': 'name',
  'title': 'name',
  'host': 'host',
  'hostname': 'host',
  'hostname/ip': 'host',
  'address': 'host',
  'ip': 'host',
  'port': 'port',
  'username': 'username',
  'user': 'username',
  'login': 'username',
  'group': 'group',
  'groups': 'group',
  'folder': 'group',
  'tags': 'tags',
  'tag': 'tags',
  'protocol': 'protocol',
};

/// Rows of [text]: commas between fields, double quotes around a field that
/// holds commas, quotes ("" for one), or line breaks.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Whether [text] looks like a hosts CSV: a header with a host column.
bool looksLikeHostsCsv(String text) {
  final first = text.split('\n').first.toLowerCase();
  return first.contains(',') && first.split(',').any((h) => _aliases[h.trim().replaceAll('"', '')] == 'host');
}

/// The hosts in a CSV with a header row. Rows without a host are skipped.
/// Tags are separated by semicolons (or by commas inside the field).
List<SshConfigHost> parseHostsCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return const [];
  final header = [for (final h in rows.first) _aliases[h.trim().toLowerCase()]];
  String? get(List<String> row, String column) {
    final i = header.indexOf(column);
    if (i < 0 || i >= row.length) return null;
    final value = row[i].trim();
    return value.isEmpty ? null : value;
  }

  final names = <String>{};
  return [
    for (final row in rows.skip(1))
      if (get(row, 'host') case final host?)
        () {
          final telnet = get(row, 'protocol')?.toLowerCase() == 'telnet';
          var name = get(row, 'name') ?? host;
          // Names identify hosts in the import: the same one twice gets a number.
          for (var n = 2; !names.add(name); n++) {
            name = '${get(row, 'name') ?? host} ($n)';
          }
          return SshConfigHost(
            alias: name,
            hostName: host,
            user: get(row, 'username'),
            port: int.tryParse(get(row, 'port') ?? ''),
            group: get(row, 'group') ?? '',
            tags: [
              for (final tag in (get(row, 'tags') ?? '').split(RegExp('[;,]')))
                if (tag.trim().isNotEmpty) tag.trim(),
            ],
            telnet: telnet,
          );
        }(),
  ];
}

String _field(String value) => value.contains(RegExp(r'[",\n\r]')) ? '"${value.replaceAll('"', '""')}"' : value;

/// The vault's hosts as CSV: no passwords, keys, or identities.
String hostsToCsv(Iterable<HostEntry> hosts) {
  final lines = [
    _columns.join(','),
    for (final h in hosts)
      [h.name, h.host, '${h.port}', h.username, h.group, h.tags.join(';'), h.protocol.name].map(_field).join(','),
  ];
  return '${lines.join('\r\n')}\r\n';
}
