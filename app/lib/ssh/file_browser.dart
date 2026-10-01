import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// Why a file operation failed. Each maps to a localized message.
enum FileProblem { noSftp, denied, notFound, exists, failed, disconnected }

class FileProblemException implements Exception {
  const FileProblemException(this.problem);
  final FileProblem problem;
}

/// One item in a remote folder.
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.isLink,
    this.size,
    this.modified,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isLink;
  final int? size;
  final DateTime? modified;
}

enum TransferDirection { upload, download }

enum TransferState { running, done, failed }

/// An upload or download and its progress.
class Transfer {
  Transfer(this.name, this.direction, this.total);

  final String name;
  final TransferDirection direction;
  final int? total;
  int done = 0;
  TransferState state = TransferState.running;
  FileProblem? problem;

  /// From 0 to 1; null while the size is unknown.
  double? get progress => total == null || total == 0 ? null : (done / total!).clamp(0, 1);
}

/// Remote paths are POSIX, whatever the local platform.
String joinRemote(String folder, String name) => folder.endsWith('/') ? '$folder$name' : '$folder/$name';

String parentOf(String path) {
  if (path == '/' || !path.contains('/')) return '/';
  final i = path.lastIndexOf('/');
  return i <= 0 ? '/' : path.substring(0, i);
}

/// Browses the files of an SSH server over SFTP on an open connection, and
/// moves files to and from it. Folders come first, then files, by name.
class FileBrowser extends ChangeNotifier {
  FileBrowser(this._open);

  /// Opens the SFTP channel on the session's connection.
  final Future<SftpClient> Function() _open;
  SftpClient? _sftp;

  String? path;
  List<RemoteEntry> entries = const [];
  bool loading = false;
  FileProblem? problem;
  final transfers = <Transfer>[];
  bool _disposed = false;

  /// Opens the server's starting folder (the user's home, usually).
  Future<void> start() => _guard(() async {
    final sftp = _sftp ??= await _open();
    path = await sftp.absolute('.');
    await _list(path!);
  });

  Future<void> open(String folder) => _guard(() => _list(folder));

  Future<void> up() => open(parentOf(path ?? '/'));

  Future<void> refresh() => open(path ?? '/');

  Future<void> _list(String folder) async {
    final names = await _sftp!.listdir(folder);
    final list = <RemoteEntry>[];
    for (final n in names) {
      if (n.filename == '.' || n.filename == '..') continue;
      var entry = _entry(folder, n);
      if (entry.isLink) {
        // Whether a link leads to a folder is known only by following it.
        try {
          final target = await _sftp!.stat(entry.path);
          entry = RemoteEntry(
            name: entry.name,
            path: entry.path,
            isDirectory: target.mode?.type == SftpFileType.directory,
            isLink: true,
            size: target.size,
            modified: entry.modified,
          );
        } on SftpStatusError {
          // A broken link stays a file that cannot be downloaded.
        }
      }
      list.add(entry);
    }
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    path = folder;
    entries = list;
  }

  static RemoteEntry _entry(String folder, SftpName n) {
    final type = n.attr.mode?.type;
    final mtime = n.attr.modifyTime;
    return RemoteEntry(
      name: n.filename,
      path: joinRemote(folder, n.filename),
      isDirectory: type == SftpFileType.directory,
      isLink: type == SftpFileType.symbolicLink,
      size: n.attr.size,
      modified: mtime == null ? null : DateTime.fromMillisecondsSinceEpoch(mtime * 1000),
    );
  }

  /// Creates a folder in the current one.
  Future<void> createFolder(String name) => _guard(() async {
    final target = joinRemote(path!, _safeName(name));
    if (await _exists(target)) throw const FileProblemException(FileProblem.exists);
    await _sftp!.mkdir(target);
    await _list(path!);
  });

  /// Downloads a remote file to [target]. A partial file is removed on
  /// failure.
  Future<Transfer> download(RemoteEntry entry, File target) async {
    final transfer = Transfer(entry.name, TransferDirection.download, entry.size);
    transfers.insert(0, transfer);
    _changed();
    final sink = target.openWrite();
    try {
      await _sftp!.download(
        entry.path,
        sink,
        onProgress: (n) {
          transfer.done = n;
          _changed();
        },
      );
      await sink.flush();
      await sink.close();
      transfer.state = TransferState.done;
    } catch (e) {
      await sink.close().catchError((Object _) {});
      if (await target.exists()) await target.delete();
      transfer
        ..state = TransferState.failed
        ..problem = _problemOf(e);
    }
    _changed();
    return transfer;
  }

  /// Uploads [source] into the current folder under [name], never over an
  /// existing file.
  Future<void> upload(Stream<List<int>> source, String name, int? size) async {
    final folder = path!;
    final transfer = Transfer(name, TransferDirection.upload, size);
    transfers.insert(0, transfer);
    _changed();
    try {
      final target = joinRemote(folder, _safeName(name));
      if (await _exists(target)) throw const FileProblemException(FileProblem.exists);
      final file = await _sftp!.open(
        target,
        mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.exclusive,
      );
      try {
        await file
            .write(
              source.map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
              onProgress: (n) {
                transfer.done = n;
                _changed();
              },
            )
            .done;
      } finally {
        await file.close();
      }
      transfer.state = TransferState.done;
      if (path == folder) await _list(folder);
    } catch (e) {
      transfer
        ..state = TransferState.failed
        ..problem = _problemOf(e);
    }
    _changed();
  }

  void clearFinished() {
    transfers.removeWhere((t) => t.state != TransferState.running);
    _changed();
  }

  /// A name for a new remote file or folder: never a path.
  static String _safeName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..' || trimmed.contains('/')) {
      throw const FileProblemException(FileProblem.failed);
    }
    return trimmed;
  }

  Future<bool> _exists(String target) async {
    try {
      await _sftp!.stat(target, followLink: false);
      return true;
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) return false;
      rethrow;
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    loading = true;
    problem = null;
    _changed();
    try {
      await action();
    } catch (e) {
      problem = _problemOf(e);
    } finally {
      loading = false;
      _changed();
    }
  }

  static FileProblem _problemOf(Object e) => switch (e) {
    FileProblemException(:final problem) => problem,
    SftpStatusError(code: SftpStatusCode.permissionDenied) => FileProblem.denied,
    SftpStatusError(code: SftpStatusCode.noSuchFile) => FileProblem.notFound,
    SftpStatusError(code: SftpStatusCode.noConnection || SftpStatusCode.connectionLost) => FileProblem.disconnected,
    SSHChannelOpenError() => FileProblem.noSftp,
    SftpError() => FileProblem.failed,
    SSHError() => FileProblem.disconnected,
    _ => FileProblem.failed,
  };

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sftp?.close();
    super.dispose();
  }
}
