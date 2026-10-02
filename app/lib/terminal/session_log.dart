import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Escape sequences: CSI (colors, cursor moves), OSC (titles) ended by BEL
/// or ST, character set choices, and the two-character ones.
final _escapes = RegExp(
  r'\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()*+][0-9A-Za-z]|\x1b[@-Z\\-_=>78]',
);

/// Control characters other than line breaks and tabs.
final _controls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]');

/// Where session logs go: Documents/Tildeck/logs.
Future<Directory> sessionLogsDirectory() async => Directory(
  '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}Tildeck'
  '${Platform.pathSeparator}logs',
);

/// A session's output as plain text in a file: what was on the screen,
/// without colors or cursor movement.
class SessionLog {
  SessionLog._(this.file, this._sink);

  final File file;
  final IOSink _sink;
  bool _closed = false;

  /// A new log in [dir], named by when it started and what it connects to.
  static Future<SessionLog> open(Directory dir, String label, DateTime at) async {
    await dir.create(recursive: true);
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}-${two(at.minute)}-${two(at.second)}';
    // Only characters every file system takes.
    final name = label.replaceAll(RegExp(r'[^A-Za-z0-9._@-]+'), '_');
    final file = File('${dir.path}${Platform.pathSeparator}$stamp $name.log');
    return SessionLog._(file, file.openWrite(mode: FileMode.append));
  }

  /// Output as the terminal received it.
  void add(String output) {
    if (_closed) return;
    _sink.write(plainText(output));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sink.flush();
    await _sink.close();
  }

  /// [output] without escape sequences or control characters; each line
  /// ends with a line feed.
  static String plainText(String output) =>
      output.replaceAll(_escapes, '').replaceAll('\r\n', '\n').replaceAll('\r', '').replaceAll(_controls, '');
}
