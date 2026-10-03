import 'dart:io';

import '../ssh/file_browser.dart';

/// Dropped paths as a terminal types them: separated by spaces, a path
/// with a space quoted, and a space after the last.
String droppedPathsInput(List<String> paths) => '${[for (final p in paths) p.contains(' ') ? '"$p"' : p].join(' ')} ';

/// Uploads dropped files and folders into [browser]'s folder, one after the
/// other, each shown in its transfers; nothing when the folder is not open.
Future<void> uploadDropped(FileBrowser browser, List<String> paths) async {
  if (browser.path == null) return;
  for (final path in paths) {
    if (await FileSystemEntity.isDirectory(path)) {
      await browser.uploadFolder(Directory(path));
    } else {
      final file = File(path);
      await browser.upload(file.openRead(), file.uri.pathSegments.last, await file.length());
    }
  }
}
