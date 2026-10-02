import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ssh/file_browser.dart' show RemoteEntry, SortBy;
import 'local_shell.dart' show localHome;

/// Browses this computer's files, for the local side of the files tab:
/// folders first, then files, in the order chosen, dotfiles only when
/// asked for. Entries use the remote browser's type, so one table shows
/// both sides.
class LocalBrowser extends ChangeNotifier {
  LocalBrowser({this.home});

  /// Where it starts; the user's home folder when null.
  final String? home;
  String? path;
  List<RemoteEntry> _all = const [];
  bool showHidden = false;
  SortBy sortBy = SortBy.name;

  /// A folder that cannot be read, until another one opens.
  bool denied = false;

  List<RemoteEntry> get entries => showHidden ? _all : _all.where((e) => !e.isHidden).toList();

  /// For a browser that lists by itself, such as a test's.
  @protected
  set entries(List<RemoteEntry> list) => _all = _sorted(list);

  /// Opens the user's home folder.
  Future<void> start() => open(home ?? localHome() ?? Directory.current.path);

  Future<void> open(String folder) async {
    try {
      final list = <RemoteEntry>[];
      await for (final item in Directory(folder).list(followLinks: false)) {
        final stat = await item.stat();
        final name = item.uri.pathSegments.where((p) => p.isNotEmpty).last;
        list.add(
          RemoteEntry(
            name: name,
            path: item.path,
            isDirectory: stat.type == FileSystemEntityType.directory,
            isLink: stat.type == FileSystemEntityType.link,
            size: stat.type == FileSystemEntityType.file ? stat.size : null,
            modified: stat.modified,
          ),
        );
      }
      path = Directory(folder).absolute.path;
      _all = _sorted(list);
      denied = false;
    } on FileSystemException {
      denied = true;
    }
    notifyListeners();
  }

  Future<void> refresh() => open(path ?? localHome() ?? Directory.current.path);

  Future<void> up() {
    final current = Directory(path!);
    final parent = current.parent;
    return parent.path == current.path ? Future.value() : open(parent.path);
  }

  /// At a drive's or the system's root, with no folder above.
  bool get atRoot => path == null || Directory(path!).parent.path == path;

  void setShowHidden(bool value) {
    showHidden = value;
    notifyListeners();
  }

  void setSortBy(SortBy value) {
    sortBy = value;
    _all = _sorted(_all);
    notifyListeners();
  }

  /// [name] in the current folder, or "name (2).ext" and so on when it is
  /// taken: a download never replaces a file the user has.
  String unusedPath(String name) {
    final sep = Platform.pathSeparator;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '$path$sep$name';
    for (var i = 2; FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound; i++) {
      candidate = '$path$sep$stem ($i)$ext';
    }
    return candidate;
  }

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
}
