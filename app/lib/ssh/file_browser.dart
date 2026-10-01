import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'ssh_connector.dart' show ConnectException, ConnectProblem;

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
    this.permissions,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isLink;
  final int? size;
  final DateTime? modified;

  /// The permission bits (0o755 and the like), when the server says.
  final int? permissions;

  bool get isHidden => name.startsWith('.');
}

enum SortBy { name, size, modified }

/// Permission bits as ls shows them: rwxr-xr-x.
String permissionString(int mode) {
  const letters = 'rwxrwxrwx';
  final out = StringBuffer();
  for (var i = 0; i < 9; i++) {
    out.write(mode & (1 << (8 - i)) != 0 ? letters[i] : '-');
  }
  return out.toString();
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
  FileBrowser(this._open, {this.onClose});

  /// Opens the SFTP channel on the session's connection.
  final Future<SftpClient> Function() _open;
  SftpClient? _sftp;

  /// Called when the browser is done: closes a connection opened for it
  /// alone.
  final VoidCallback? onClose;

  String? path;

  /// Everything in the folder, hidden or not, in the order chosen.
  List<RemoteEntry> _all = const [];

  /// What is shown: dotfiles only when asked for.
  List<RemoteEntry> get entries => showHidden ? _all : _all.where((e) => !e.isHidden).toList();

  /// For a browser that lists by itself, such as a test's.
  @protected
  set entries(List<RemoteEntry> list) => _all = _sorted(list);

  bool showHidden = false;
  SortBy sortBy = SortBy.name;
  bool loading = false;
  FileProblem? problem;

  /// Why the connection for a browser of its own could not be made.
  ConnectProblem? connectProblem;
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
            permissions: entry.permissions,
          );
        } on SftpStatusError {
          // A broken link stays a file that cannot be downloaded.
        }
      }
      list.add(entry);
    }
    path = folder;
    _all = _sorted(list);
  }

  /// Folders first, then by the chosen order; newest and largest first.
  List<RemoteEntry> _sorted(List<RemoteEntry> list) {
    int byName(RemoteEntry a, RemoteEntry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return [...list]..sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      final order = switch (sortBy) {
        SortBy.name => 0,
        SortBy.size => (b.size ?? 0).compareTo(a.size ?? 0),
        SortBy.modified => (b.modified ?? DateTime(0)).compareTo(a.modified ?? DateTime(0)),
      };
      return order != 0 ? order : byName(a, b);
    });
  }

  void setShowHidden(bool value) {
    showHidden = value;
    _changed();
  }

  void setSortBy(SortBy value) {
    sortBy = value;
    _all = _sorted(_all);
    _changed();
  }

  /// Opens a folder typed by the user; relative to the current one.
  Future<void> goTo(String typed) {
    final trimmed = typed.trim();
    final target = trimmed.startsWith('/') ? trimmed : joinRemote(path ?? '/', trimmed);
    return open(target.length > 1 && target.endsWith('/') ? target.substring(0, target.length - 1) : target);
  }

  /// Renames [entry] in its folder, never over another entry.
  Future<void> rename(RemoteEntry entry, String name) => _guard(() async {
    final target = joinRemote(parentOf(entry.path), _safeName(name));
    if (target == entry.path) return;
    if (await _exists(target)) throw const FileProblemException(FileProblem.exists);
    await _sftp!.rename(entry.path, target);
    await _list(path!);
  });

  /// Deletes [entry]; a folder with everything in it. Links are removed,
  /// never followed.
  Future<void> delete(RemoteEntry entry) => _guard(() async {
    await _remove(entry.path, isDirectory: entry.isDirectory && !entry.isLink);
    await _list(path!);
  });

  Future<void> _remove(String target, {required bool isDirectory}) async {
    if (!isDirectory) return _sftp!.remove(target);
    for (final n in await _sftp!.listdir(target)) {
      if (n.filename == '.' || n.filename == '..') continue;
      final type = n.attr.mode?.type;
      await _remove(joinRemote(target, n.filename), isDirectory: type == SftpFileType.directory);
    }
    await _sftp!.rmdir(target);
  }

  /// Sets the permission bits of [entry].
  Future<void> setPermissions(RemoteEntry entry, int mode) => _guard(() async {
    await _sftp!.setStat(entry.path, SftpFileAttrs(mode: SftpFileMode.value(mode & 0x1ff)));
    await _list(path!);
  });

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
      permissions: n.attr.mode == null ? null : n.attr.mode!.value & 0x1ff,
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
    connectProblem = null;
    _changed();
    try {
      await action();
    } on ConnectException catch (e) {
      connectProblem = e.problem;
      problem = FileProblem.disconnected;
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
    onClose?.call();
    super.dispose();
  }
}
