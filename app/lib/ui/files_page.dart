import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../l10n/app_localizations.dart';
import '../ssh/file_browser.dart';
import '../ssh/local_files.dart';
import '../theme.dart';
import 'terminal_panel.dart' show connectProblemText;

String fileProblemText(AppLocalizations t, FileProblem problem) => switch (problem) {
  FileProblem.noSftp => t.fileErrorNoSftp,
  FileProblem.denied => t.fileErrorDenied,
  FileProblem.notFound => t.fileErrorNotFound,
  FileProblem.exists => t.fileErrorExists,
  FileProblem.disconnected => t.fileErrorDisconnected,
  FileProblem.failed => t.fileErrorFailed,
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

  @override
  void initState() {
    super.initState();
    if (browser.path == null) browser.start();
  }

  @override
  void dispose() {
    browser.dispose();
    super.dispose();
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _download(RemoteEntry entry) async {
    final t = AppLocalizations.of(context);
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    return ListenableBuilder(
      listenable: browser,
      builder: (context, _) {
        final ready = browser.path != null;
        return Scaffold(
          appBar: AppBar(
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
                child: FilledButton.icon(
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
                            onAction: (action) => _act(action, browser.entries[i]),
                            onTap: () {
                              final e = browser.entries[i];
                              if (e.isDirectory) {
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
  const _EntryTile({required this.entry, required this.onTap, required this.onAction});

  final RemoteEntry entry;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

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
      leading: Icon(
        entry.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
        color: entry.isDirectory ? c.brand : c.muted,
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
          if (!entry.isDirectory) PopupMenuItem(value: 'download', child: Text(t.download)),
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
                              if (tr.state == TransferState.running)
                                LinearProgressIndicator(value: tr.progress, minHeight: 3)
                              else
                                Text(
                                  tr.state == TransferState.done ? t.transferDone : fileProblemText(t, tr.problem!),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tr.state == TransferState.done ? c.success : c.danger,
                                  ),
                                ),
                            ],
                          ),
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
