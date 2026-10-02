import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../local/local_names.dart';
import 'ssh_connector.dart' show ConnectException, ConnectProblem;

/// Why a file operation failed. Each maps to a localized message.
enum FileProblem { noSftp, denied, notFound, exists, failed, disconnected, tooLarge, notText, changed }

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

/// A remote text file open for editing, and how it was when it was read:
/// saving checks that nobody changed it since.
class EditedFile {
  EditedFile({required this.path, required this.text, required this.modified, required this.size, required this.crlf});

  final String path;

  /// With \n line ends; [crlf] files get \r\n back when saved.
  final String text;
  int? modified;
  int? size;
  final bool crlf;

  String get name => path.substring(path.lastIndexOf('/') + 1);
}

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

enum TransferState { running, done, failed, cancelled }

/// An upload or download and its progress: one file, or a folder with
/// everything in it.
class Transfer {
  Transfer(this.name, this.direction, this.total);

  final String name;
  final TransferDirection direction;
  int? total;
  int done = 0;
  TransferState state = TransferState.running;
  FileProblem? problem;

  /// Files in a folder transfer, and how many are through.
  int files = 1;
  int filesDone = 0;

  bool _cancelled = false;
  final _onCancel = <FutureOr<void> Function()>[];

  /// Stops it; what was partly written is removed.
  Future<void> cancel() async {
    if (state != TransferState.running || _cancelled) return;
    _cancelled = true;
    for (final stop in _onCancel.toList()) {
      await stop();
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  /// From 0 to 1; null while the size is unknown.
  double? get progress => total == null || total == 0 ? null : (done / total!).clamp(0, 1);
}

class _Cancelled implements Exception {
  const _Cancelled();
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

  /// Larger files are downloaded, not edited here.
  static const editLimit = 2 * 1024 * 1024;

  /// Reads [entry] as text to edit; null with [problem] set when it is too
  /// large, not text, or cannot be read.
  Future<EditedFile?> openText(RemoteEntry entry) async {
    EditedFile? opened;
    await _guard(() async {
      final attrs = await _sftp!.stat(entry.path);
      if ((attrs.size ?? 0) > editLimit) throw const FileProblemException(FileProblem.tooLarge);
      final file = await _sftp!.open(entry.path);
      final Uint8List bytes;
      try {
        bytes = await file.readBytes();
      } finally {
        await file.close();
      }
      // A NUL byte means binary, whatever else decodes.
      if (bytes.contains(0)) throw const FileProblemException(FileProblem.notText);
      final String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw const FileProblemException(FileProblem.notText);
      }
      final crlf = text.contains('\r\n');
      opened = EditedFile(
        path: entry.path,
        text: crlf ? text.replaceAll('\r\n', '\n') : text,
        modified: attrs.modifyTime,
        size: attrs.size,
        crlf: crlf,
      );
    });
    return opened;
  }

  /// Writes [text] over [file] on the server. Unless [overwrite], refuses
  /// with [FileProblem.changed] when the file changed since it was read.
  Future<bool> saveText(EditedFile file, String text, {bool overwrite = false}) async {
    var saved = false;
    await _guard(() async {
      final now = await _sftp!.stat(file.path);
      if (!overwrite && (now.modifyTime != file.modified || now.size != file.size)) {
        throw const FileProblemException(FileProblem.changed);
      }
      final bytes = utf8.encode(file.crlf ? text.replaceAll('\n', '\r\n') : text);
      final remote = await _sftp!.open(file.path, mode: SftpFileOpenMode.write | SftpFileOpenMode.truncate);
      try {
        await remote.writeBytes(bytes);
      } finally {
        await remote.close();
      }
      final after = await _sftp!.stat(file.path);
      file
        ..modified = after.modifyTime
        ..size = after.size;
      saved = true;
      if (path != null) await _list(path!);
    });
    return saved;
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
  /// failure or when cancelled.
  Future<Transfer> download(RemoteEntry entry, File target) async {
    final transfer = Transfer(entry.name, TransferDirection.download, entry.size);
    transfers.insert(0, transfer);
    _changed();
    await _run(
      transfer,
      () => _downloadFile(transfer, entry.path, target, 0),
      cleanup: () async {
        if (await target.exists()) await target.delete();
      },
    );
    return transfer;
  }

  /// Downloads a remote folder and everything in it into [target], which
  /// is created. A partial folder is removed on failure or when cancelled.
  Future<Transfer> downloadFolder(RemoteEntry entry, Directory target) async {
    final transfer = Transfer(entry.name, TransferDirection.download, null);
    transfers.insert(0, transfer);
    _changed();
    await _run(
      transfer,
      () async {
        final folders = <String>[];
        final files = <(String, String, int)>[];
        await _walk(entry.path, '', folders, files, transfer);
        transfer
          ..files = files.length
          ..total = files.fold<int>(0, (sum, f) => sum + f.$3);
        // Each step of a server path becomes one safe local name, two names
        // that end up the same get a number, and the result is checked to
        // stay inside the target: a hostile server must not write elsewhere.
        final taken = <String, String>{};
        String local(String relative) {
          final known = taken[relative];
          if (known != null) return known;
          final slash = relative.lastIndexOf('/');
          final parent = slash < 0 ? target.path : local(relative.substring(0, slash));
          final name = localNameFor(relative.substring(slash + 1));
          var candidate = '$parent${Platform.pathSeparator}$name';
          for (var i = 2; taken.containsValue(candidate); i++) {
            candidate = '$parent${Platform.pathSeparator}$name ($i)';
          }
          if (!isInside(target.path, candidate)) throw const FileProblemException(FileProblem.failed);
          return taken[relative] = candidate;
        }

        await target.create(recursive: true);
        for (final relative in folders) {
          await Directory(local(relative)).create(recursive: true);
        }
        for (final (remote, relative, _) in files) {
          transfer._checkCancelled();
          await _downloadFile(transfer, remote, File(local(relative)), transfer.done);
          transfer.filesDone++;
        }
      },
      cleanup: () async {
        if (await target.exists()) await target.delete(recursive: true);
      },
    );
    return transfer;
  }

  /// Everything under [folder], by path below the top: the folders, and
  /// the files with their remote paths and sizes. Links and devices are
  /// left out: a folder copy holds folders and files.
  Future<void> _walk(
    String folder,
    String relative,
    List<String> folders,
    List<(String, String, int)> files,
    Transfer transfer,
  ) async {
    transfer._checkCancelled();
    for (final n in await _sftp!.listdir(folder)) {
      if (n.filename == '.' || n.filename == '..') continue;
      final remote = joinRemote(folder, n.filename);
      final below = relative.isEmpty ? n.filename : '$relative/${n.filename}';
      final type = n.attr.mode?.type;
      if (type == SftpFileType.directory) {
        folders.add(below);
        await _walk(remote, below, folders, files, transfer);
      } else if (type == SftpFileType.regularFile) {
        files.add((remote, below, n.attr.size ?? 0));
      }
    }
  }

  /// Copies one remote file into [target], counting from [base] bytes.
  Future<void> _downloadFile(Transfer transfer, String remote, File target, int base) async {
    final file = await _sftp!.open(remote);
    final sink = target.openWrite();
    final finished = Completer<void>();
    late final StreamSubscription<Uint8List> reading;
    Future<void> stop() async {
      await reading.cancel();
      if (!finished.isCompleted) finished.completeError(const _Cancelled());
    }

    transfer._onCancel.add(stop);
    try {
      reading = file
          .read(
            onProgress: (n) {
              transfer.done = base + n;
              _changed();
            },
          )
          .listen(
            sink.add,
            onDone: () => finished.isCompleted ? null : finished.complete(),
            onError: (Object e) => finished.isCompleted ? null : finished.completeError(e),
            cancelOnError: true,
          );
      await finished.future;
    } finally {
      transfer._onCancel.remove(stop);
      await sink.flush().catchError((Object _) {});
      await sink.close().catchError((Object _) {});
      await file.close().catchError((Object _) {});
    }
  }

  /// Runs [work] for [transfer], recording how it ended; [cleanup] removes
  /// what a failed or cancelled one left behind.
  Future<void> _run(Transfer transfer, Future<void> Function() work, {required Future<void> Function() cleanup}) async {
    try {
      await work();
      transfer._checkCancelled();
      transfer.state = TransferState.done;
    } on _Cancelled {
      await cleanup().catchError((Object _) {});
      transfer.state = TransferState.cancelled;
    } catch (e) {
      await cleanup().catchError((Object _) {});
      transfer
        ..state = transfer._cancelled ? TransferState.cancelled : TransferState.failed
        ..problem = transfer._cancelled ? null : _problemOf(e);
    }
    _changed();
  }

  /// Uploads [source] into the current folder under [name], never over an
  /// existing file.
  Future<void> upload(Stream<List<int>> source, String name, int? size) async {
    final folder = path!;
    final transfer = Transfer(name, TransferDirection.upload, size);
    transfers.insert(0, transfer);
    _changed();
    String? created;
    await _run(
      transfer,
      () async {
        final target = joinRemote(folder, _safeName(name));
        if (await _exists(target)) throw const FileProblemException(FileProblem.exists);
        created = target;
        await _uploadFile(transfer, source, target, 0);
        if (path == folder) await _list(folder);
      },
      cleanup: () async {
        if (created != null) await _sftp!.remove(created!);
      },
    );
  }

  /// Uploads a local folder and everything in it into the current folder,
  /// never over an existing entry. A partial copy is removed on failure or
  /// when cancelled.
  Future<void> uploadFolder(Directory source) async {
    final folder = path!;
    final name = source.uri.pathSegments.where((p) => p.isNotEmpty).last;
    final transfer = Transfer(name, TransferDirection.upload, null);
    transfers.insert(0, transfer);
    _changed();
    String? created;
    await _run(
      transfer,
      () async {
        final target = joinRemote(folder, _safeName(name));
        if (await _exists(target)) throw const FileProblemException(FileProblem.exists);
        final items = await source.list(recursive: true, followLinks: false).toList();
        final files = items.whereType<File>().toList();
        transfer
          ..files = files.length
          ..total = 0;
        for (final f in files) {
          transfer.total = transfer.total! + await f.length();
        }
        await _sftp!.mkdir(target);
        created = target;
        String remoteOf(FileSystemEntity e) =>
            joinRemote(target, e.path.substring(source.path.length + 1).replaceAll(Platform.pathSeparator, '/'));
        for (final dir in items.whereType<Directory>().toList()..sort((a, b) => a.path.length - b.path.length)) {
          transfer._checkCancelled();
          await _sftp!.mkdir(remoteOf(dir));
        }
        for (final f in files) {
          transfer._checkCancelled();
          await _uploadFile(transfer, f.openRead(), remoteOf(f), transfer.done);
          transfer.filesDone++;
        }
        if (path == folder) await _list(folder);
      },
      cleanup: () async {
        if (created != null) await _remove(created!, isDirectory: true);
        if (path == folder) await _list(folder);
      },
    );
  }

  Future<void> _uploadFile(Transfer transfer, Stream<List<int>> source, String target, int base) async {
    final file = await _sftp!.open(
      target,
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.exclusive,
    );
    try {
      final writer = file.write(
        source.map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk)),
        onProgress: (n) {
          transfer.done = base + n;
          _changed();
        },
      );
      Future<void> stop() => writer.abort();
      transfer._onCancel.add(stop);
      try {
        await writer.done;
      } finally {
        transfer._onCancel.remove(stop);
      }
      transfer._checkCancelled();
    } finally {
      await file.close().catchError((Object _) {});
    }
  }

  /// Deletes several entries; stops at the first that fails.
  Future<void> deleteAll(List<RemoteEntry> list) => _guard(() async {
    for (final entry in list) {
      await _remove(entry.path, isDirectory: entry.isDirectory && !entry.isLink);
    }
    await _list(path!);
  });

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
