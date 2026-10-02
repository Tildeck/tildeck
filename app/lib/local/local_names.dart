import 'dart:io';

/// Names Windows keeps for devices, with or without an extension: a file
/// called "CON.txt" opens the console instead.
final _reserved = {
  'CON', 'PRN', 'AUX', 'NUL', //
  for (var i = 0; i <= 9; i++) ...['COM$i', 'LPT$i'],
};

/// A name from a server as one safe name on this computer: never a path,
/// never a step up, never a device. A Linux name may hold "\", ":" and the
/// like, which Windows reads as separators, drives, or streams: "..\..\x"
/// would land outside the folder it was meant for. Such characters become
/// "_", as do trailing dots and spaces (Windows drops them, so ".." and "."
/// would become something else); a device name gets "_" in front.
String localNameFor(String remote) {
  var name = String.fromCharCodes(
    remote.codeUnits.map((c) => c < 32 || c == 127 || r'<>:"/\|?*'.codeUnits.contains(c) ? 0x5f : c),
  );
  name = name.replaceAllMapped(RegExp(r'[. ]+$'), (m) => '_' * m[0]!.length);
  if (name.isEmpty) return '_';
  if (_reserved.contains(name.split('.').first.toUpperCase())) return '_$name';
  return name;
}

/// Whether [candidate] is [root] itself or inside it, once both are made
/// absolute: a check that does not trust how a path was built.
bool isInside(String root, String candidate) {
  String norm(String p) {
    final abs = File(p).absolute.path.replaceAll('\\', '/');
    final trimmed = abs.endsWith('/') && abs.length > 1 ? abs.substring(0, abs.length - 1) : abs;
    // Windows paths do not care about letter case.
    return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
  }

  final r = norm(root), c = norm(candidate);
  final parts = c.split('/');
  // A ".." anywhere means the path was not built from safe names.
  if (parts.contains('..')) return false;
  return c == r || c.startsWith('$r/');
}
