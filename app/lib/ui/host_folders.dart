/// Folders of hosts: a host's group is a path, "Production/Web" being the
/// Web folder inside Production. Settings come from a folder and the ones
/// above it, the nearest first (Vault.effectiveGroup).
library;

/// "Production / Web " and "Production/Web" are the same folder.
String canonicalGroup(String raw) => raw.split('/').map((p) => p.trim()).where((p) => p.isNotEmpty).join('/');

/// The folders above [path], nearest last: "A/B/C" gives "A", "A/B".
List<String> ancestorsOf(String path) {
  final parts = path.split('/');
  return [for (var i = 1; i < parts.length; i++) parts.take(i).join('/')];
}

int depthOf(String path) => path.isEmpty ? 0 : path.split('/').length - 1;

String leafOf(String path) => path.split('/').last;

/// The folders to show, in order: every folder with hosts and the folders
/// above it, each parent before its children, alphabetically; the hosts
/// in no folder last.
List<String> folderOrder(Iterable<String> withHosts) {
  final paths = <String>{};
  var none = false;
  for (final p in withHosts) {
    if (p.isEmpty) {
      none = true;
      continue;
    }
    paths
      ..addAll(ancestorsOf(p))
      ..add(p);
  }
  int compare(String a, String b) {
    final x = a.split('/'), y = b.split('/');
    for (var i = 0; i < x.length && i < y.length; i++) {
      final c = x[i].toLowerCase().compareTo(y[i].toLowerCase());
      if (c != 0) return c;
    }
    return x.length.compareTo(y.length);
  }

  return [...paths.toList()..sort(compare), if (none) ''];
}

/// Whether a folder's header is hidden: a folder above it is collapsed.
bool headerHidden(String path, Set<String> collapsed) => ancestorsOf(path).any(collapsed.contains);

/// Whether a folder's hosts are hidden: it, or a folder above it, is collapsed.
bool hostsHidden(String path, Set<String> collapsed) => collapsed.contains(path) || headerHidden(path, collapsed);

/// How many hosts are in [path] and the folders inside it.
int hostCountUnder(String path, Map<String, List<Object>> byFolder) => byFolder.entries
    .where((e) => path.isEmpty ? e.key.isEmpty : e.key == path || e.key.startsWith('$path/'))
    .fold(0, (n, e) => n + e.value.length);
