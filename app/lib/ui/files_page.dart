import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../l10n/app_localizations.dart';
import '../ssh/file_browser.dart';
import '../ssh/local_files.dart';
import '../theme.dart';
import 'desktop_sidebar.dart' show isDesktopLayout;
import 'file_editor_page.dart';
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
  const FilesPage({super.key, required this.browser, required this.title, this.local = const DeviceFiles()});

  final FileBrowser browser;

  /// Who and where: user@host.
  final String title;
  final LocalFiles local;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  FileBrowser get browser => widget.browser;

  /// Paths chosen with a long press, for acting on several at once.
  final _selected = <String>{};

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
    });
  }

  @override
  void dispose() {
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
      case 'delete':
        await _delete(entry);
    }
  }

  /// The last entry clicked, where a Shift+click range starts.
  String? _anchor;

  /// The last click, to tell a double-click.
  ({String path, DateTime at})? _lastClick;

  /// A click selects one entry; with Ctrl it adds or removes one; with
  /// Shift it selects the range from the last click.
  void _click(RemoteEntry entry) {
    final keys = HardwareKeyboard.instance;
    final list = browser.entries;
    setState(() {
      if (keys.isShiftPressed && _anchor != null) {
        final from = list.indexWhere((e) => e.path == _anchor);
        final to = list.indexOf(entry);
        if (from >= 0 && to >= 0) {
          final (a, b) = from < to ? (from, to) : (to, from);
          _selected
            ..clear()
            ..addAll(list.sublist(a, b + 1).map((e) => e.path));
          return;
        }
      }
      if (keys.isControlPressed || keys.isMetaPressed) {
        if (!_selected.remove(entry.path)) _selected.add(entry.path);
      } else {
        _selected
          ..clear()
          ..add(entry.path);
      }
      _anchor = entry.path;
    });
  }

  /// A folder opens; a file opens in the editor.
  void _openEntry(RemoteEntry entry) {
    setState(_selected.clear);
    if (entry.isDirectory) {
      browser.open(entry.path);
    } else {
      _act('edit', entry);
    }
  }

  Future<void> _contextMenu(Offset at, RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
    if (!_selected.contains(entry.path)) _click(entry);
    final several = _selected.length > 1;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        if (!several && !entry.isDirectory)
          PopupMenuItem(key: const ValueKey('rowEdit'), value: 'edit', child: Text(t.editFile)),
        if (!several && entry.isDirectory) PopupMenuItem(value: 'open', child: Text(t.open)),
        if (widget.local.folders || !entry.isDirectory || several)
          PopupMenuItem(key: const ValueKey('rowDownload'), value: 'download', child: Text(t.download)),
        if (!several) ...[
          PopupMenuItem(key: const ValueKey('rowRename'), value: 'rename', child: Text(t.renameAction)),
          PopupMenuItem(value: 'permissions', child: Text(t.permissionsTitle)),
          PopupMenuItem(value: 'copyPath', child: Text(t.copyPath)),
        ],
        PopupMenuItem(key: const ValueKey('rowDelete'), value: 'delete', child: Text(t.deleteAction)),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'open':
        _openEntry(entry);
      case 'download' when several:
        await _downloadChosen();
      case 'delete' when several:
        await _deleteChosen();
      default:
        await _act(action, entry);
    }
  }

  /// The keys of a file manager, while the list has the focus.
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
        setState(_selected.clear);
        browser.up();
      case LogicalKeyboardKey.keyA when HardwareKeyboard.instance.isControlPressed:
        setState(() => _selected.addAll(browser.entries.map((e) => e.path)));
      case LogicalKeyboardKey.escape when _selected.isNotEmpty:
        setState(_selected.clear);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  final _listFocus = FocusNode(debugLabel: 'files');

  /// Files on a wide window: a toolbar with the path, a table with sortable
  /// columns, and the transfers under it, as a file manager has them.
  Widget _desktop(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ListenableBuilder(
      listenable: browser,
      builder: (context, _) {
        final ready = browser.path != null;
        final path = browser.path ?? '';
        final segments = path.split('/').where((p) => p.isNotEmpty).toList();
        final muted = TextStyle(color: c.muted, fontSize: 12.5);

        Widget header(String label, SortBy? by, {double? width, TextAlign align = TextAlign.start}) {
          final on = by != null && browser.sortBy == by;
          final text = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: on ? c.ink : c.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
              if (on) Icon(Icons.arrow_downward_rounded, size: 14, color: c.ink),
            ],
          );
          final cell = by == null
              ? text
              : InkWell(
                  key: ValueKey('sort-${by.name}'),
                  onTap: () => browser.setSortBy(by),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: text),
                );
          return width == null ? Expanded(child: cell) : SizedBox(width: width, child: cell);
        }

        final selected = _chosen;
        // A left-to-right value (a size, a name) at its column's start.
        final start = Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left;
        return Scaffold(
          backgroundColor: c.page,
          body: Column(
            children: [
              // Toolbar: up, the path as steps, and the folder's actions.
              Container(
                height: 56,
                padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 14, 0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('filesUp'),
                      tooltip: t.parentFolder,
                      onPressed: ready && path != '/' ? browser.up : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    IconButton(
                      key: const ValueKey('filesRefresh'),
                      tooltip: t.refresh,
                      onPressed: ready && !browser.loading ? browser.refresh : null,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 6),
                    // Paths read left to right in either language.
                    Expanded(
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
                                // Short paths start at the left; a long one
                                // shows its end, the folder you are in.
                                child: LayoutBuilder(
                                  builder: (context, box) => SingleChildScrollView(
                                    key: const ValueKey('filesPath'),
                                    scrollDirection: Axis.horizontal,
                                    reverse: true,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: box.maxWidth),
                                      child: Row(
                                        children: [
                                          for (var i = 0; i <= segments.length; i++)
                                            TextButton(
                                              key: ValueKey('crumb-$i'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: i == segments.length ? c.ink : c.muted,
                                                minimumSize: const Size(0, 30),
                                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                                textStyle: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
                                              ),
                                              onPressed: i == segments.length
                                                  ? null
                                                  : () => browser.open(i == 0 ? '/' : '/${segments.take(i).join('/')}'),
                                              child: Text(
                                                i == 0 ? '/' : '${segments[i - 1]}${i < segments.length ? ' /' : ''}',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('filesGoTo'),
                                tooltip: t.goToFolder,
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                onPressed: ready ? _goTo : null,
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (selected.isNotEmpty) ...[
                      Text(t.selectedCount(selected.length), key: const ValueKey('selectionCount'), style: muted),
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
                      const SizedBox(width: 6),
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
                    const SizedBox(width: 6),
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
                      builder: (context, menu, _) => FilledButton.icon(
                        key: const ValueKey('filesUpload'),
                        onPressed: ready ? () => menu.isOpen ? menu.close() : menu.open() : null,
                        icon: const Icon(Icons.upload_rounded, size: 18),
                        label: Text(t.upload),
                      ),
                    ),
                  ],
                ),
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
              if (browser.loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
              // Column titles; a click sorts by that column.
              Container(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    header(t.columnName, SortBy.name),
                    header(t.columnSize, SortBy.size, width: 110),
                    header(t.columnModified, SortBy.modified, width: 190),
                    header(t.permissionsTitle, null, width: 120),
                  ],
                ),
              ),
              Expanded(
                child: !ready
                    ? const SizedBox.shrink()
                    : browser.entries.isEmpty && !browser.loading
                    ? Center(
                        child: Text(t.folderEmpty, style: TextStyle(color: c.muted)),
                      )
                    : Focus(
                        focusNode: _listFocus,
                        onKeyEvent: _onListKey,
                        child: ListView.builder(
                          key: const ValueKey('filesTable'),
                          itemCount: browser.entries.length,
                          itemExtent: 36,
                          itemBuilder: (context, i) {
                            final e = browser.entries[i];
                            final on = _selected.contains(e.path);
                            final size = !e.isDirectory && e.size != null ? formatSize(e.size!, locale) : '';
                            final date = e.modified == null
                                ? ''
                                : DateFormat.yMMMd(locale).add_Hm().format(e.modified!);
                            return Material(
                              color: on ? c.brand.withValues(alpha: 0.14) : Colors.transparent,
                              child: InkWell(
                                key: ValueKey('row-${e.name}'),
                                hoverColor: c.brand.withValues(alpha: 0.06),
                                // A double-click is told apart here, so a single
                                // click selects at once instead of waiting.
                                onTap: () {
                                  _listFocus.requestFocus();
                                  final now = DateTime.now();
                                  final again =
                                      _lastClick?.path == e.path &&
                                      now.difference(_lastClick!.at) < const Duration(milliseconds: 400);
                                  _lastClick = again ? null : (path: e.path, at: now);
                                  again ? _openEntry(e) : _click(e);
                                },
                                onSecondaryTapUp: (d) {
                                  _listFocus.requestFocus();
                                  _contextMenu(d.globalPosition, e);
                                },
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              e.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                                              size: 18,
                                              color: e.isDirectory ? c.brand : c.muted,
                                            ),
                                            const SizedBox(width: 10),
                                            // A name reads left to right, at the row's start.
                                            Expanded(
                                              child: Text(
                                                e.name,
                                                textDirection: TextDirection.ltr,
                                                textAlign: Directionality.of(context) == TextDirection.rtl
                                                    ? TextAlign.right
                                                    : TextAlign.left,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: e.isDirectory ? FontWeight.w600 : FontWeight.w400,
                                                  color: e.isHidden ? c.muted : c.ink,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          size,
                                          textDirection: TextDirection.ltr,
                                          textAlign: start,
                                          style: muted,
                                        ),
                                      ),
                                      SizedBox(width: 190, child: Text(date, style: muted)),
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          e.permissions == null ? '' : permissionString(e.permissions!),
                                          textDirection: TextDirection.ltr,
                                          textAlign: start,
                                          style: muted.copyWith(fontFamily: 'JetBrainsMono', fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
  });

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
                          tr.direction == TransferDirection.upload ? Icons.upload_rounded : Icons.download_rounded,
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
                              if (tr.state == TransferState.running) ...[
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
                        if (tr.state == TransferState.running)
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
