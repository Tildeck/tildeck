import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../l10n/app_localizations.dart';
import '../local/local_browser.dart';
import '../ssh/file_browser.dart';
import '../ssh/local_files.dart';
import '../theme.dart';
import 'desktop_sidebar.dart' show isDesktopLayout;
import 'file_editor_page.dart';
import 'file_table.dart';
import 'server_picker.dart';
import 'terminal_panel.dart' show connectProblemText;

String fileProblemText(AppLocalizations t, FileProblem problem) => switch (problem) {
  FileProblem.noSftp => t.fileErrorNoSftp,
  FileProblem.denied => t.fileErrorDenied,
  FileProblem.notFound => t.fileErrorNotFound,
  FileProblem.exists => t.fileErrorExists,
  FileProblem.disconnected => t.fileErrorDisconnected,
  FileProblem.failed => t.fileErrorFailed,
  FileProblem.tooLarge => t.fileErrorTooLarge,
  FileProblem.notText => t.fileErrorNotText,
  FileProblem.changed => t.fileErrorChanged,
};

/// The files of the server behind an open session: browse folders, upload
/// files into the current one, download a file by tapping it. Paths and
/// names are LTR content in either language.
class FilesPage extends StatefulWidget {
  const FilesPage({
    super.key,
    required this.browser,
    required this.title,
    this.local = const DeviceFiles(),
    this.localBrowser,
    this.otherServer,
  });

  final FileBrowser browser;

  /// Who and where: user@host.
  final String title;
  final LocalFiles local;

  /// This computer's side in the desktop layout; made from the home folder
  /// when not given.
  final LocalBrowser? localBrowser;

  /// Opens another server's files, to copy entries to; null offers no copy.
  final Future<OtherServer?> Function(BuildContext context)? otherServer;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  FileBrowser get browser => widget.browser;

  /// The server's entries chosen: by long press on a phone, by click on
  /// the desktop.
  final _remoteSel = FileSelection();
  Set<String> get _selected => _remoteSel.paths;

  /// This computer's side of the desktop layout, and what is chosen there.
  late final LocalBrowser _local = widget.localBrowser ?? LocalBrowser();
  final _localSel = FileSelection();
  final _localFocus = FocusNode(debugLabel: 'localFiles');

  /// Whether this computer's side shows, beside the server's.
  var _twoPanes = true;

  void _toggle(RemoteEntry entry) => setState(() {
    if (!_selected.remove(entry.path)) _selected.add(entry.path);
  });

  List<RemoteEntry> get _chosen => browser.entries.where((e) => _selected.contains(e.path)).toList();

  @override
  void initState() {
    super.initState();
    // After the first frame: starting notifies the browser's listeners (a
    // tab showing its state, too), which must not happen while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && browser.path == null) browser.start();
      if (mounted && widget.local.folders && _local.path == null) _local.start();
    });
  }

  @override
  void dispose() {
    _localFocus.dispose();
    _localSel.dispose();
    _remoteSel.dispose();
    if (widget.localBrowser == null) _local.dispose();
    _listFocus.dispose();
    browser.dispose();
    super.dispose();
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _download(RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
    if (entry.isDirectory) {
      final folder = await widget.local.folderTarget(entry.name);
      final transfer = await browser.downloadFolder(entry, folder);
      if (transfer.state == TransferState.done && mounted) _say(t.fileSaved(folder.path));
      return;
    }
    final target = await widget.local.downloadTarget(entry.name);
    final transfer = await browser.download(entry, target);
    if (transfer.state != TransferState.done) return;
    final where = await widget.local.keep(target, entry.name);
    if (where != null && mounted) _say(t.fileSaved(where));
  }

  Future<void> _upload() async {
    final picked = await widget.local.pickToUpload();
    for (final file in picked) {
      await browser.upload(file.read(), file.name, file.size);
    }
  }

  Future<void> _uploadFolder() async {
    final folder = await widget.local.pickFolderToUpload();
    if (folder != null) await browser.uploadFolder(folder);
  }

  /// Downloads the chosen entries; folders only where folders can go.
  Future<void> _downloadChosen() async {
    final chosen = _chosen.where((e) => widget.local.folders || !e.isDirectory).toList();
    setState(_selected.clear);
    for (final entry in chosen) {
      await _download(entry);
    }
  }

  Future<void> _deleteChosen() async {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final chosen = _chosen;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteEntryTitle),
        content: Text(t.deleteSeveralBody(chosen.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            key: const ValueKey('confirmDelete'),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.deleteAction),
          ),
        ],
      ),
    );
    if (sure != true) return;
    setState(_selected.clear);
    await browser.deleteAll(chosen);
  }

  Future<void> _newFolder() async {
    final t = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: t.newFolder, label: t.folderNameLabel, action: t.create),
    );
    if (name == null || name.trim().isEmpty) return;
    await browser.createFolder(name);
    if (browser.problem == null && mounted) _say(t.folderCreated(name.trim()));
  }

  Future<void> _rename(RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _NameDialog(title: t.renameTitle, label: t.newNameLabel, action: t.renameAction, initial: entry.name),
    );
    if (name == null || name.trim().isEmpty || name.trim() == entry.name) return;
    await browser.rename(entry, name);
  }

  Future<void> _delete(RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    // Files on a server have no undo: this one asks.
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteEntryTitle),
        content: Text(
          entry.isDirectory && !entry.isLink ? t.deleteFolderBody(entry.name) : t.deleteFileBody(entry.name),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            key: const ValueKey('confirmDelete'),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.deleteAction),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await browser.delete(entry);
    if (browser.problem == null && mounted) _say(t.entryDeleted(entry.name));
  }

  Future<void> _permissions(RemoteEntry entry) async {
    final mode = await showDialog<int>(
      context: context,
      builder: (_) => _PermissionsDialog(entry: entry),
    );
    if (mode != null) await browser.setPermissions(entry, mode);
  }

  Future<void> _goTo() async {
    final t = AppLocalizations.of(context);
    final target = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: t.goToFolder, label: t.folderPathLabel, action: t.open, initial: browser.path),
    );
    if (target != null && target.trim().isNotEmpty) await browser.goTo(target);
  }

  Future<void> _act(String action, RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
    switch (action) {
      case 'download':
        await _download(entry);
      case 'edit':
        final file = await browser.openText(entry);
        if (file == null || !mounted) return;
        if (isDesktopLayout(context)) {
          // On the desktop, a large window over the files, not a page in
          // place of everything.
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(40),
              clipBehavior: Clip.antiAlias,
              child: FileEditorPage(browser: browser, file: file),
            ),
          );
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FileEditorPage(browser: browser, file: file),
            ),
          );
        }
      case 'rename':
        await _rename(entry);
      case 'permissions':
        await _permissions(entry);
      case 'copyPath':
        await Clipboard.setData(ClipboardData(text: entry.path));
        _say(t.pathCopied);
      case 'copyServer':
        await _copyToServer([entry]);
      case 'delete':
        await _delete(entry);
    }
  }

  /// Copies [entries] to a folder on another saved server, through this
  /// device. The copy shows among this server's transfers.
  Future<void> _copyToServer(List<RemoteEntry> entries) async {
    final open = widget.otherServer;
    if (open == null || entries.isEmpty) return;
    final t = AppLocalizations.of(context);
    final other = await open(context);
    if (other == null || !mounted) return;
    final target = other.browser;
    try {
      await target.start();
      if (!mounted) return;
      if (target.path == null) {
        _say(t.copyToServerFailed(other.label));
        return;
      }
      final folder = await showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(
          title: t.copyToServerWhere(other.label),
          label: t.folderPathLabel,
          action: t.copyAction,
          initial: target.path,
        ),
      );
      if (folder == null || folder.trim().isEmpty || !mounted) return;
      await target.goTo(folder);
      if (target.problem != null) {
        _say(t.copyToServerFailed(other.label));
        return;
      }
      final transfer = await browser.copyTo(target, entries);
      if (mounted && transfer.state == TransferState.done) _say(t.copiedToServer(other.label));
    } finally {
      target.dispose();
    }
  }

  /// A folder opens; a file opens in the editor.
  void _openEntry(RemoteEntry entry) {
    _remoteSel.clear();
    if (entry.isDirectory) {
      browser.open(entry.path);
    } else {
      _act('edit', entry);
    }
  }

  Future<void> _contextMenu(Offset at, RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
    final several = _remoteSel.length > 1;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (!several && !entry.isDirectory)
          PopupMenuItem(key: const ValueKey('rowEdit'), value: 'edit', child: Text(t.editFile)),
        if (!several && entry.isDirectory) PopupMenuItem(value: 'open', child: Text(t.open)),
        if (_showsLocal)
          PopupMenuItem(key: const ValueKey('rowDownloadHere'), value: 'toLocal', child: Text(t.downloadToPane)),
        if (widget.local.folders || !entry.isDirectory || several)
          PopupMenuItem(key: const ValueKey('rowDownload'), value: 'download', child: Text(t.downloadToDownloads)),
        if (!several) ...[
          PopupMenuItem(key: const ValueKey('rowRename'), value: 'rename', child: Text(t.renameAction)),
          PopupMenuItem(value: 'permissions', child: Text(t.permissionsTitle)),
          PopupMenuItem(value: 'copyPath', child: Text(t.copyPath)),
        ],
        if (widget.otherServer != null)
          PopupMenuItem(key: const ValueKey('rowCopyServer'), value: 'copyServer', child: Text(t.copyToServer)),
        PopupMenuItem(key: const ValueKey('rowDelete'), value: 'delete', child: Text(t.deleteAction)),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'open':
        _openEntry(entry);
      case 'toLocal':
        await _downloadToLocal(_remoteSel.of(browser.entries));
      case 'download' when several:
        await _downloadChosen();
      case 'copyServer':
        await _copyToServer(several ? _remoteSel.of(browser.entries) : [entry]);
      case 'delete' when several:
        await _deleteChosen();
      default:
        await _act(action, entry);
    }
  }

  /// The keys of a file manager, while the server's list has the focus.
  KeyEventResult _onListKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final chosen = _chosen;
    final one = chosen.length == 1 ? chosen.single : null;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.delete when chosen.isNotEmpty:
        chosen.length == 1 ? _delete(chosen.single) : _deleteChosen();
      case LogicalKeyboardKey.f2 when one != null:
        _rename(one);
      case LogicalKeyboardKey.enter when one != null:
        _openEntry(one);
      case LogicalKeyboardKey.backspace when browser.path != '/':
        _remoteSel.clear();
        browser.up();
      case LogicalKeyboardKey.keyA when HardwareKeyboard.instance.isControlPressed:
        _remoteSel.selectAll(browser.entries);
      case LogicalKeyboardKey.escape when !_remoteSel.isEmpty:
        _remoteSel.clear();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The local list's keys: open, up, select all.
  KeyEventResult _onLocalKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final chosen = _localSel.of(_local.entries);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter when chosen.length == 1 && chosen.single.isDirectory:
        _localSel.clear();
        _local.open(chosen.single.path);
      case LogicalKeyboardKey.backspace when !_local.atRoot:
        _localSel.clear();
        _local.up();
      case LogicalKeyboardKey.keyA when HardwareKeyboard.instance.isControlPressed:
        _localSel.selectAll(_local.entries);
      case LogicalKeyboardKey.escape when !_localSel.isEmpty:
        _localSel.clear();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  final _listFocus = FocusNode(debugLabel: 'files');

  /// Whether this computer's side is on screen.
  bool get _showsLocal => _twoPanes && widget.local.folders;

  /// Copies files and folders from this computer into the server's folder.
  Future<void> _uploadFromLocal(List<RemoteEntry> entries) async {
    _localSel.clear();
    for (final e in entries) {
      if (e.isDirectory) {
        await browser.uploadFolder(Directory(e.path));
      } else {
        final file = File(e.path);
        await browser.upload(file.openRead(), e.name, e.size);
      }
    }
  }

  /// Copies the server's files and folders into this computer's folder,
  /// never over what is there.
  Future<void> _downloadToLocal(List<RemoteEntry> entries) async {
    _remoteSel.clear();
    for (final e in entries) {
      final target = _local.unusedPath(e.name);
      if (e.isDirectory) {
        await browser.downloadFolder(e, Directory(target));
      } else {
        await browser.download(e, File(target));
      }
    }
    await _local.refresh();
  }

  /// Files on a wide window: this computer and the server side by side, as
  /// a file manager has them, with the transfers under both.
  Widget _desktop(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: Listenable.merge([browser, _local, _remoteSel, _localSel]),
      builder: (context, _) {
        final ready = browser.path != null;
        final muted = TextStyle(color: c.muted, fontSize: 12.5);
        final remoteChosen = _remoteSel.of(browser.entries);
        final localChosen = _localSel.of(_local.entries);

        Widget pathField(
          String? path, {
          required Key key,
          required void Function(String) onOpen,
          VoidCallback? onEdit,
        }) {
          final segments = (path ?? '').split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
          // A Windows path keeps its drive ("C:") as its first step.
          final windows = path != null && RegExp(r'^[A-Za-z]:').hasMatch(path);
          String upTo(int i) {
            final parts = segments.take(i).join(windows ? r'\' : '/');
            return windows ? (i == 1 ? '$parts\\' : parts) : '/$parts';
          }

          final steps = [
            if (!windows) ('/', '/'),
            for (var i = 1; i <= segments.length; i++) (segments[i - 1], upTo(i)),
          ];
          return Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      // Short paths start at the left; a long one shows its
                      // end, the folder you are in.
                      child: LayoutBuilder(
                        builder: (context, box) => SingleChildScrollView(
                          key: key,
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: box.maxWidth),
                            child: Row(
                              children: [
                                for (final (i, (label, to)) in steps.indexed)
                                  TextButton(
                                    key: ValueKey('$key-crumb-$i'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: i == steps.length - 1 ? c.ink : c.muted,
                                      minimumSize: const Size(0, 30),
                                      padding: const EdgeInsets.symmetric(horizontal: 5),
                                      textStyle: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                                    ),
                                    onPressed: i == steps.length - 1 ? null : () => onOpen(to),
                                    child: Text(label == '/' || i == steps.length - 1 ? label : '$label /'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (onEdit != null)
                      IconButton(
                        key: const ValueKey('filesGoTo'),
                        tooltip: t.goToFolder,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget bar(List<Widget> children) => Container(
          height: 56,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 12, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(children: children),
        );

        // Two panes share the width: the side's name keeps to an icon, and
        // shows in full when the pointer rests on it.
        Widget title(IconData icon, String text) => Tooltip(
          message: text,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
            child: _showsLocal
                ? Icon(icon, size: 20, color: c.brand)
                : Row(
                    children: [
                      Icon(icon, size: 18, color: c.brand),
                      const SizedBox(width: 8),
                      Text(
                        text,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
          ),
        );

        final remote = Column(
          children: [
            bar([
              title(Icons.dns_outlined, widget.title),
              IconButton(
                key: const ValueKey('filesUp'),
                tooltip: t.parentFolder,
                onPressed: ready && browser.path != '/' ? browser.up : null,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              IconButton(
                key: const ValueKey('filesRefresh'),
                tooltip: t.refresh,
                onPressed: ready && !browser.loading ? browser.refresh : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
              pathField(
                browser.path,
                key: const ValueKey('filesPath'),
                onOpen: (to) => browser.open(to),
                onEdit: ready ? _goTo : null,
              ),
              const SizedBox(width: 8),
              if (remoteChosen.isNotEmpty) ...[
                Text(t.selectedCount(remoteChosen.length), key: const ValueKey('selectionCount'), style: muted),
                if (_showsLocal)
                  IconButton(
                    key: const ValueKey('selectionToLocal'),
                    tooltip: t.downloadToPane,
                    onPressed: () => _downloadToLocal(remoteChosen),
                    icon: const Icon(Icons.download_rounded),
                  )
                else
                  IconButton(
                    key: const ValueKey('selectionDownload'),
                    tooltip: t.download,
                    onPressed: _downloadChosen,
                    icon: const Icon(Icons.download_rounded),
                  ),
                IconButton(
                  key: const ValueKey('selectionDelete'),
                  tooltip: t.deleteAction,
                  onPressed: _deleteChosen,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
              IconButton(
                key: const ValueKey('filesShowHidden'),
                tooltip: t.showHiddenFiles,
                isSelected: browser.showHidden,
                onPressed: () => browser.setShowHidden(!browser.showHidden),
                icon: const Icon(Icons.visibility_off_outlined),
                selectedIcon: const Icon(Icons.visibility_outlined),
              ),
              IconButton(
                key: const ValueKey('filesNewFolder'),
                tooltip: t.newFolder,
                onPressed: ready ? _newFolder : null,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              const SizedBox(width: 4),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    key: const ValueKey('filesUploadFiles'),
                    leadingIcon: const Icon(Icons.upload_file_outlined),
                    onPressed: _upload,
                    child: Text(t.uploadFiles),
                  ),
                  if (widget.local.folders)
                    MenuItemButton(
                      key: const ValueKey('filesUploadFolder'),
                      leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
                      onPressed: _uploadFolder,
                      child: Text(t.uploadFolder),
                    ),
                ],
                builder: (context, menu, _) => _showsLocal
                    ? IconButton.filled(
                        key: const ValueKey('filesUpload'),
                        tooltip: t.upload,
                        onPressed: ready ? () => menu.isOpen ? menu.close() : menu.open() : null,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                      )
                    : FilledButton.icon(
                        key: const ValueKey('filesUpload'),
                        onPressed: ready ? () => menu.isOpen ? menu.close() : menu.open() : null,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: Text(t.upload),
                      ),
              ),
            ]),
            if (browser.problem != null)
              Container(
                width: double.infinity,
                color: c.danger.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  browser.connectProblem != null
                      ? connectProblemText(t, browser.connectProblem!)
                      : fileProblemText(t, browser.problem!),
                  key: const ValueKey('filesProblem'),
                  style: TextStyle(color: c.danger),
                ),
              ),
            if (browser.loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
            Expanded(
              child: !ready
                  ? const SizedBox.shrink()
                  : FileTable(
                      side: FileSide.remote,
                      entries: browser.entries,
                      selection: _remoteSel,
                      sortBy: browser.sortBy,
                      onSort: browser.setSortBy,
                      onOpen: _openEntry,
                      onMenu: _contextMenu,
                      focusNode: _listFocus,
                      onKey: _onListKey,
                      empty: browser.loading ? null : t.folderEmpty,
                      onDrop: _showsLocal ? (drag) => _uploadFromLocal(drag.entries) : null,
                    ),
            ),
          ],
        );

        final local = Column(
          children: [
            bar([
              title(Icons.computer_outlined, t.thisComputer),
              IconButton(
                key: const ValueKey('localUp'),
                tooltip: t.parentFolder,
                onPressed: _local.atRoot ? null : _local.up,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              IconButton(tooltip: t.refresh, onPressed: _local.refresh, icon: const Icon(Icons.refresh_rounded)),
              pathField(_local.path, key: const ValueKey('localPath'), onOpen: _local.open),
              const SizedBox(width: 8),
              if (localChosen.isNotEmpty) ...[
                Text(t.selectedCount(localChosen.length), style: muted),
                IconButton.filledTonal(
                  key: const ValueKey('selectionToRemote'),
                  tooltip: t.uploadToServer,
                  onPressed: ready ? () => _uploadFromLocal(localChosen) : null,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                ),
              ],
            ]),
            if (_local.denied)
              Container(
                width: double.infinity,
                color: c.danger.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(t.fileErrorDenied, style: TextStyle(color: c.danger)),
              ),
            const SizedBox(height: 2),
            Expanded(
              child: FileTable(
                side: FileSide.local,
                entries: _local.entries,
                selection: _localSel,
                sortBy: _local.sortBy,
                onSort: _local.setSortBy,
                showPermissions: false,
                onOpen: (e) {
                  if (!e.isDirectory) return;
                  _localSel.clear();
                  _local.open(e.path);
                },
                onMenu: (at, e) async {
                  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
                  final chosen = _localSel.of(_local.entries);
                  final action = await showMenu<String>(
                    context: context,
                    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
                    items: [
                      if (e.isDirectory && chosen.length == 1) PopupMenuItem(value: 'open', child: Text(t.open)),
                      PopupMenuItem(key: const ValueKey('localUpload'), value: 'upload', child: Text(t.uploadToServer)),
                    ],
                  );
                  if (action == 'open') {
                    _localSel.clear();
                    await _local.open(e.path);
                  } else if (action == 'upload' && ready) {
                    await _uploadFromLocal(chosen);
                  }
                },
                focusNode: _localFocus,
                onKey: _onLocalKey,
                empty: t.folderEmpty,
                onDrop: ready ? (drag) => _downloadToLocal(drag.entries) : null,
              ),
            ),
          ],
        );

        return Scaffold(
          backgroundColor: c.page,
          body: Column(
            children: [
              Expanded(
                child: _showsLocal
                    ? Row(
                        children: [
                          Expanded(child: local),
                          VerticalDivider(width: 1, color: c.line),
                          Expanded(child: remote),
                        ],
                      )
                    : remote,
              ),
              // Two panes, or the server's alone.
              if (widget.local.folders)
                Container(
                  height: 34,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        key: const ValueKey('toggleTwoPanes'),
                        style: TextButton.styleFrom(
                          foregroundColor: c.muted,
                          textStyle: const TextStyle(fontSize: 12.5),
                        ),
                        onPressed: () => setState(() => _twoPanes = !_twoPanes),
                        icon: Icon(_twoPanes ? Icons.view_agenda_outlined : Icons.vertical_split_outlined, size: 16),
                        label: Text(_twoPanes ? t.hideThisComputer : t.showThisComputer),
                      ),
                      const Spacer(),
                      if (_showsLocal) Text(t.dragBetweenPanes, style: muted),
                    ],
                  ),
                ),
              if (browser.transfers.isNotEmpty) _Transfers(browser: browser),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopLayout(context)) return _desktop(context);
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: browser,
      builder: (context, _) {
        final ready = browser.path != null;
        return Scaffold(
          appBar: _selected.isNotEmpty
              ? AppBar(
                  backgroundColor: c.desk,
                  foregroundColor: c.deskInk,
                  leading: IconButton(
                    key: const ValueKey('selectionClear'),
                    tooltip: t.cancel,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_selected.clear),
                  ),
                  title: Text(t.selectedCount(_selected.length), key: const ValueKey('selectionCount')),
                  actions: [
                    IconButton(
                      key: const ValueKey('selectionDownload'),
                      tooltip: t.download,
                      color: c.deskMuted,
                      icon: const Icon(Icons.download_rounded),
                      onPressed: _downloadChosen,
                    ),
                    IconButton(
                      key: const ValueKey('selectionDelete'),
                      tooltip: t.deleteAction,
                      color: c.deskMuted,
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: _deleteChosen,
                    ),
                    const SizedBox(width: 8),
                  ],
                )
              : AppBar(
                  backgroundColor: c.desk,
                  foregroundColor: c.deskInk,
                  title: Text(t.filesTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                  actions: [
                    IconButton(
                      key: const ValueKey('filesRefresh'),
                      tooltip: t.refresh,
                      color: c.deskMuted,
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: ready && !browser.loading ? browser.refresh : null,
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('filesView'),
                      tooltip: t.viewOptions,
                      iconColor: c.deskMuted,
                      icon: const Icon(Icons.tune_rounded),
                      onSelected: (v) => switch (v) {
                        'hidden' => browser.setShowHidden(!browser.showHidden),
                        'name' => browser.setSortBy(SortBy.name),
                        'size' => browser.setSortBy(SortBy.size),
                        'modified' => browser.setSortBy(SortBy.modified),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        CheckedPopupMenuItem(
                          key: const ValueKey('filesShowHidden'),
                          value: 'hidden',
                          checked: browser.showHidden,
                          child: Text(t.showHiddenFiles),
                        ),
                        const PopupMenuDivider(),
                        for (final (value, label) in [
                          ('name', t.sortByName),
                          ('size', t.sortBySize),
                          ('modified', t.sortByModified),
                        ])
                          CheckedPopupMenuItem(
                            key: ValueKey('filesSort-$value'),
                            value: value,
                            checked: browser.sortBy.name == value,
                            child: Text(label),
                          ),
                      ],
                    ),
                    IconButton(
                      key: const ValueKey('filesNewFolder'),
                      tooltip: t.newFolder,
                      color: c.deskMuted,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      onPressed: ready ? _newFolder : null,
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      // Where folders can be chosen, Upload asks which: files
                      // or a folder. One button, so the bar fits a narrow
                      // window.
                      child: widget.local.folders
                          ? MenuAnchor(
                              menuChildren: [
                                MenuItemButton(
                                  key: const ValueKey('filesUploadFiles'),
                                  leadingIcon: const Icon(Icons.upload_file_outlined),
                                  onPressed: _upload,
                                  child: Text(t.uploadFiles),
                                ),
                                MenuItemButton(
                                  key: const ValueKey('filesUploadFolder'),
                                  leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
                                  onPressed: _uploadFolder,
                                  child: Text(t.uploadFolder),
                                ),
                              ],
                              builder: (context, menu, _) => FilledButton.icon(
                                key: const ValueKey('filesUpload'),
                                onPressed: ready ? () => menu.isOpen ? menu.close() : menu.open() : null,
                                icon: const Icon(Icons.upload_rounded, size: 18),
                                label: Text(t.upload),
                              ),
                            )
                          : FilledButton.icon(
                              key: const ValueKey('filesUpload'),
                              onPressed: ready ? _upload : null,
                              icon: const Icon(Icons.upload_rounded, size: 18),
                              label: Text(t.upload),
                            ),
                    ),
                  ],
                ),
          body: SafeArea(
            child: Column(
              children: [
                _PathBar(
                  title: widget.title,
                  path: browser.path,
                  onUp: ready && browser.path != '/' ? browser.up : null,
                  onGoTo: ready ? _goTo : null,
                ),
                if (browser.problem != null)
                  Container(
                    width: double.infinity,
                    color: c.danger.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      browser.connectProblem != null
                          ? connectProblemText(t, browser.connectProblem!)
                          : fileProblemText(t, browser.problem!),
                      key: const ValueKey('filesProblem'),
                      style: TextStyle(color: c.danger),
                    ),
                  ),
                if (browser.loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: !ready
                      ? const SizedBox.shrink()
                      : browser.entries.isEmpty && !browser.loading
                      ? Center(
                          child: Text(t.folderEmpty, style: TextStyle(color: c.muted)),
                        )
                      : ListView.separated(
                          itemCount: browser.entries.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
                          itemBuilder: (context, i) => _EntryTile(
                            entry: browser.entries[i],
                            selected: _selected.contains(browser.entries[i].path),
                            folders: widget.local.folders,
                            copyServer: widget.otherServer != null,
                            onAction: (action) => _act(action, browser.entries[i]),
                            onLongPress: () => _toggle(browser.entries[i]),
                            onTap: () {
                              final e = browser.entries[i];
                              if (_selected.isNotEmpty) {
                                _toggle(e);
                              } else if (e.isDirectory) {
                                browser.open(e.path);
                              } else {
                                _download(e);
                              }
                            },
                          ),
                        ),
                ),
                if (browser.transfers.isNotEmpty) _Transfers(browser: browser),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PathBar extends StatelessWidget {
  const _PathBar({required this.title, required this.path, required this.onUp, required this.onGoTo});

  final String title;
  final String? path;
  final VoidCallback? onUp;

  /// Opens a folder by its path.
  final VoidCallback? onGoTo;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.page,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('filesUp'),
            tooltip: t.parentFolder,
            onPressed: onUp,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
          Expanded(
            child: InkWell(
              key: const ValueKey('filesGoTo'),
              onTap: onGoTo,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  Text(
                    path ?? '',
                    key: const ValueKey('filesPath'),
                    textDirection: TextDirection.ltr,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onAction,
    required this.onLongPress,
    required this.selected,
    required this.folders,
    this.copyServer = false,
  });

  /// Offers copying to another server.
  final bool copyServer;

  final RemoteEntry entry;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;
  final VoidCallback onLongPress;
  final bool selected;

  /// Whether a folder can be downloaded here.
  final bool folders;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final size = !entry.isDirectory && entry.size != null ? formatSize(entry.size!, locale) : null;
    final date = entry.modified == null ? null : DateFormat.yMMMd(locale).add_Hm().format(entry.modified!);
    final muted = TextStyle(color: c.muted, fontSize: 12);
    // Each part keeps its own direction: a size is LTR inside a Hebrew line.
    final permissions = entry.permissions == null ? null : permissionString(entry.permissions!);
    final details = [
      if (size != null) Text(size, textDirection: TextDirection.ltr, style: muted),
      if (size != null && date != null) Text('  ·  ', style: muted),
      if (date != null) Text(date, style: muted),
      if (permissions != null) ...[
        Text('  ·  ', style: muted),
        Text(
          permissions,
          textDirection: TextDirection.ltr,
          style: muted.copyWith(fontFamily: 'JetBrainsMono'),
        ),
      ],
    ];
    final t = AppLocalizations.of(context);
    return ListTile(
      key: ValueKey('entry-${entry.name}'),
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: c.brand.withValues(alpha: 0.12),
      leading: Icon(
        selected
            ? Icons.check_circle_rounded
            : entry.isDirectory
            ? Icons.folder_rounded
            : Icons.insert_drive_file_outlined,
        color: entry.isDirectory || selected ? c.brand : c.muted,
      ),
      // A name reads left to right, but sits at the start of the row.
      title: Text(
        entry.name,
        textDirection: TextDirection.ltr,
        textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: entry.isDirectory ? FontWeight.w600 : FontWeight.w400),
      ),
      subtitle: details.isEmpty ? null : Wrap(children: details),
      trailing: PopupMenuButton<String>(
        key: ValueKey('entryMenu-${entry.name}'),
        onSelected: onAction,
        itemBuilder: (_) => [
          if (!entry.isDirectory)
            PopupMenuItem(key: const ValueKey('entryEdit'), value: 'edit', child: Text(t.editFile)),
          if (!entry.isDirectory || folders)
            PopupMenuItem(key: const ValueKey('entryDownload'), value: 'download', child: Text(t.download)),
          PopupMenuItem(key: const ValueKey('entryRename'), value: 'rename', child: Text(t.renameAction)),
          PopupMenuItem(key: const ValueKey('entryPermissions'), value: 'permissions', child: Text(t.permissionsTitle)),
          PopupMenuItem(key: const ValueKey('entryCopyPath'), value: 'copyPath', child: Text(t.copyPath)),
          if (copyServer)
            PopupMenuItem(key: const ValueKey('entryCopyServer'), value: 'copyServer', child: Text(t.copyToServer)),
          PopupMenuItem(key: const ValueKey('entryDelete'), value: 'delete', child: Text(t.deleteAction)),
        ],
      ),
    );
  }
}

/// Sizes in the units people read: 1.2 MB, not 1234567 bytes.
String formatSize(int bytes, String locale) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var unit = 0;
  while (n >= 1024 && unit < units.length - 1) {
    n /= 1024;
    unit++;
  }
  final number = NumberFormat(unit == 0 ? '0' : '0.#', locale).format(n);
  return '$number ${units[unit]}';
}

class _Transfers extends StatelessWidget {
  const _Transfers({required this.browser});

  final FileBrowser browser;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 0),
            child: Row(
              children: [
                Text(t.transfersTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed: browser.clearFinished, child: Text(t.clearFinished)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              children: [
                for (final tr in browser.transfers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          switch (tr.direction) {
                            TransferDirection.upload => Icons.upload_rounded,
                            TransferDirection.download => Icons.download_rounded,
                            TransferDirection.copy => Icons.swap_horiz_rounded,
                          },
                          size: 18,
                          color: tr.state == TransferState.failed ? c.danger : c.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr.name,
                                textDirection: TextDirection.ltr,
                                textAlign: Directionality.of(context) == TextDirection.rtl
                                    ? TextAlign.right
                                    : TextAlign.left,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              if (tr.state == TransferState.queued)
                                Text(t.transferQueued, style: TextStyle(fontSize: 12, color: c.muted))
                              else if (tr.state == TransferState.running) ...[
                                LinearProgressIndicator(value: tr.progress, minHeight: 3),
                                if (tr.files > 1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      t.filesProgress(tr.filesDone, tr.files),
                                      style: TextStyle(fontSize: 11, color: c.muted),
                                    ),
                                  ),
                              ] else
                                Text(
                                  switch (tr.state) {
                                    TransferState.done => t.transferDone,
                                    TransferState.cancelled => t.transferCancelled,
                                    _ => fileProblemText(t, tr.problem!),
                                  },
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: switch (tr.state) {
                                      TransferState.done => c.success,
                                      TransferState.cancelled => c.muted,
                                      _ => c.danger,
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!tr.finished)
                          IconButton(
                            key: ValueKey('cancelTransfer-${tr.name}'),
                            tooltip: t.cancel,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: tr.cancel,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a name or a path.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.label, required this.action, this.initial});

  final String title;
  final String label;
  final String action;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: _stemLength(widget.initial ?? ''));

  /// Renaming selects the name without its extension, as file managers do.
  static int _stemLength(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? dot : name.length;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('folderName'),
        controller: _name,
        autofocus: true,
        textDirection: TextDirection.ltr,
        onSubmitted: (_) => Navigator.pop(context, _name.text),
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('nameDialogOk'),
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// Read, write, and run for the owner, the group, and others, with the
/// octal value alongside, as chmod takes it.
class _PermissionsDialog extends StatefulWidget {
  const _PermissionsDialog({required this.entry});

  final RemoteEntry entry;

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  late int _mode = widget.entry.permissions ?? (widget.entry.isDirectory ? 0x1ed : 0x1a4);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    Widget bit(int shift) => Checkbox(
      key: ValueKey('permission-$shift'),
      value: _mode & (1 << shift) != 0,
      onChanged: (v) => setState(() => _mode = v! ? _mode | (1 << shift) : _mode & ~(1 << shift)),
    );
    TableRow row(String who, int base) => TableRow(
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(who)),
        bit(base + 2),
        bit(base + 1),
        bit(base),
      ],
    );
    final header = TextStyle(color: c.muted, fontSize: 12);
    return AlertDialog(
      title: Text(t.permissionsTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.entry.name,
              textDirection: TextDirection.ltr,
              textAlign: Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {0: FlexColumnWidth(2)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    const SizedBox.shrink(),
                    Center(child: Text(t.permissionRead, style: header)),
                    Center(child: Text(t.permissionWrite, style: header)),
                    Center(child: Text(t.permissionRun, style: header)),
                  ],
                ),
                row(t.permissionOwner, 6),
                row(t.permissionGroup, 3),
                row(t.permissionOthers, 0),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_mode.toRadixString(8).padLeft(3, '0')}  ${permissionString(_mode)}',
              key: const ValueKey('permissionValue'),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          key: const ValueKey('savePermissions'),
          onPressed: () => Navigator.pop(context, _mode),
          child: Text(t.save),
        ),
      ],
    );
  }
}
