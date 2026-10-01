import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../l10n/app_localizations.dart';
import '../ssh/file_browser.dart';
import '../ssh/local_files.dart';
import '../theme.dart';

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
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || name.trim().isEmpty) return;
    await browser.createFolder(name);
    if (browser.problem == null && mounted) _say(t.folderCreated(name.trim()));
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
                ),
                if (browser.problem != null)
                  Container(
                    width: double.infinity,
                    color: c.danger.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(
                      fileProblemText(t, browser.problem!),
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
  const _PathBar({required this.title, required this.path, required this.onUp});

  final String title;
  final String? path;
  final VoidCallback? onUp;

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
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final RemoteEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final size = !entry.isDirectory && entry.size != null ? formatSize(entry.size!, locale) : null;
    final date = entry.modified == null ? null : DateFormat.yMMMd(locale).add_Hm().format(entry.modified!);
    final muted = TextStyle(color: c.muted, fontSize: 12);
    // Each part keeps its own direction: a size is LTR inside a Hebrew line.
    final details = [
      if (size != null) Text(size, textDirection: TextDirection.ltr, style: muted),
      if (size != null && date != null) Text('  ·  ', style: muted),
      if (date != null) Text(date, style: muted),
    ];
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
      trailing: entry.isDirectory
          ? Icon(Icons.chevron_right_rounded, color: c.muted, textDirection: Directionality.of(context))
          : Icon(Icons.download_rounded, color: c.muted, size: 20),
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

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.newFolder),
      content: TextField(
        key: const ValueKey('folderName'),
        controller: _name,
        autofocus: true,
        textDirection: TextDirection.ltr,
        onSubmitted: (_) => Navigator.pop(context, _name.text),
        decoration: InputDecoration(labelText: t.folderNameLabel),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: Text(t.create)),
      ],
    );
  }
}
