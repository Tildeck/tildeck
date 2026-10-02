import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../local/local_names.dart';

/// A local file chosen for upload.
class PickedFile {
  const PickedFile(this.name, this.size, this.read);

  final String name;
  final int? size;
  final Stream<List<int>> Function() read;
}

/// This device's side of file transfers: choosing files to upload, and
/// where a download goes.
abstract class LocalFiles {
  Future<List<PickedFile>> pickToUpload();

  /// The file a download is written to while it runs.
  Future<File> downloadTarget(String name);

  /// Puts a finished download where the user keeps files. Returns where it
  /// went, for a message, or null when the user cancelled.
  Future<String?> keep(File downloaded, String name);

  /// Whether whole folders can be moved: on the desktop, where folders can
  /// be chosen and written freely.
  bool get folders;

  /// A new folder for a downloaded folder, never one that exists.
  Future<Directory> folderTarget(String name);

  /// A folder to upload, or null when the user cancelled.
  Future<Directory?> pickFolderToUpload();
}

/// The platform's pickers. On desktop a download goes straight into the
/// Downloads folder, written as it arrives; on Android it goes through the
/// system's save dialog.
class DeviceFiles implements LocalFiles {
  const DeviceFiles();

  @override
  Future<List<PickedFile>> pickToUpload() async {
    final files = await FilePicker.pickFiles();
    return [for (final f in files) PickedFile(f.name, await f.length(), f.readAsByteStream)];
  }

  @override
  Future<File> downloadTarget(String remoteName) async {
    final name = localNameFor(remoteName);
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      return File('${dir.path}${Platform.pathSeparator}$name');
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    return _unused(dir, name);
  }

  @override
  bool get folders => !Platform.isAndroid && !Platform.isIOS;

  @override
  Future<Directory> folderTarget(String remoteName) async {
    final name = localNameFor(remoteName);
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    var candidate = Directory('${dir.path}$sep$name');
    for (var i = 2; candidate.existsSync(); i++) {
      candidate = Directory('${dir.path}$sep$name ($i)');
    }
    return candidate;
  }

  @override
  Future<Directory?> pickFolderToUpload() async {
    final path = await FilePicker.getDirectoryPath();
    return path == null ? null : Directory(path);
  }

  @override
  Future<String?> keep(File downloaded, String name) async {
    if (!Platform.isAndroid) return downloaded.path;
    try {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: await downloaded.readAsBytes(),
        mimeType: 'application/octet-stream',
      );
      return uri == null ? null : name;
    } finally {
      await downloaded.delete();
    }
  }

  /// [name] in [dir], or "name (2).ext" and so on when it is taken: a
  /// download never replaces a file the user has.
  static File _unused(Directory dir, String name) {
    final sep = Platform.pathSeparator;
    var candidate = File('${dir.path}$sep$name');
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; candidate.existsSync(); i++) {
      candidate = File('${dir.path}$sep$stem ($i)$ext');
    }
    return candidate;
  }
}
