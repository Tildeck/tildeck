import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../l10n/app_localizations.dart';
import '../ssh/file_browser.dart';
import '../theme.dart';
import 'files_page.dart' show formatSize;

/// Which side of the files tab a table shows.
enum FileSide { local, remote }

/// Entries dragged from one table, for the other to take.
class FileDrag {
  const FileDrag(this.from, this.entries);
  final FileSide from;
  final List<RemoteEntry> entries;
}

/// The entries chosen in a table: a click chooses one, Ctrl adds or takes
/// one away, Shift takes the range from the last click.
class FileSelection extends ChangeNotifier {
  final paths = <String>{};
  String? _anchor;
  ({String path, DateTime at})? _lastClick;

  bool contains(RemoteEntry e) => paths.contains(e.path);
  List<RemoteEntry> of(List<RemoteEntry> entries) => entries.where(contains).toList();
  bool get isEmpty => paths.isEmpty;
  int get length => paths.length;

  void clear() {
    if (paths.isEmpty) return;
    paths.clear();
    notifyListeners();
  }

  void selectAll(List<RemoteEntry> entries) {
    paths.addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  void click(RemoteEntry entry, List<RemoteEntry> entries) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed && _anchor != null) {
      final from = entries.indexWhere((e) => e.path == _anchor);
      final to = entries.indexOf(entry);
      if (from >= 0 && to >= 0) {
        final (a, b) = from < to ? (from, to) : (to, from);
        paths
          ..clear()
          ..addAll(entries.sublist(a, b + 1).map((e) => e.path));
        notifyListeners();
        return;
      }
    }
    if (keys.isControlPressed || keys.isMetaPressed) {
      if (!paths.remove(entry.path)) paths.add(entry.path);
    } else {
      paths
        ..clear()
        ..add(entry.path);
    }
    _anchor = entry.path;
    notifyListeners();
  }

  /// Whether this click on [entry] makes a double-click with the last one.
  /// Told apart here, so a single click selects at once instead of waiting.
  bool isDoubleClick(RemoteEntry entry) {
    final now = DateTime.now();
    final again = _lastClick?.path == entry.path && now.difference(_lastClick!.at) < const Duration(milliseconds: 400);
    _lastClick = again ? null : (path: entry.path, at: now);
    return again;
  }
}

/// A file manager's table: column titles that sort, rows that select,
/// open, offer actions, and can be dragged to the other side, which takes
/// them when dropped.
class FileTable extends StatelessWidget {
  const FileTable({
    super.key,
    required this.side,
    required this.entries,
    required this.selection,
    required this.sortBy,
    required this.onSort,
    required this.onOpen,
    required this.onMenu,
    required this.focusNode,
    required this.onKey,
    this.onDrop,
    this.showPermissions = true,
    this.empty,
  });

  final FileSide side;
  final List<RemoteEntry> entries;
  final FileSelection selection;
  final SortBy sortBy;
  final ValueChanged<SortBy> onSort;
  final ValueChanged<RemoteEntry> onOpen;
  final void Function(Offset at, RemoteEntry entry) onMenu;
  final FocusNode focusNode;
  final FocusOnKeyEventCallback onKey;

  /// Entries dropped from the other side; null takes no drops.
  final ValueChanged<FileDrag>? onDrop;
  final bool showPermissions;

  /// Shown when there are no entries.
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final muted = TextStyle(color: c.muted, fontSize: 12.5);
    // A left-to-right value (a size, a name) at its column's start.
    final start = Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left;

    Widget header(String label, SortBy? by, {double? width}) {
      final on = by != null && sortBy == by;
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
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: text)
          : InkWell(
              key: ValueKey('sort-${side.name}-${by.name}'),
              onTap: () => onSort(by),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: text),
            );
      return width == null ? Expanded(child: cell) : SizedBox(width: width, child: cell);
    }

    Widget row(RemoteEntry e) {
      final on = selection.contains(e);
      final size = !e.isDirectory && e.size != null ? formatSize(e.size!, locale) : '';
      final date = e.modified == null ? '' : DateFormat.yMMMd(locale).add_Hm().format(e.modified!);
      final content = Material(
        color: on ? c.brand.withValues(alpha: 0.14) : Colors.transparent,
        child: InkWell(
          key: ValueKey(side == FileSide.remote ? 'row-${e.name}' : 'local-row-${e.name}'),
          hoverColor: c.brand.withValues(alpha: 0.06),
          onTap: () {
            focusNode.requestFocus();
            selection.isDoubleClick(e) ? onOpen(e) : selection.click(e, entries);
          },
          onSecondaryTapUp: (d) {
            focusNode.requestFocus();
            if (!selection.contains(e)) selection.click(e, entries);
            onMenu(d.globalPosition, e);
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
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
                      Expanded(
                        child: Text(
                          e.name,
                          textDirection: TextDirection.ltr,
                          textAlign: start,
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
                  width: 96,
                  child: Text(size, textDirection: TextDirection.ltr, textAlign: start, style: muted),
                ),
                SizedBox(
                  width: 170,
                  child: Text(date, overflow: TextOverflow.ellipsis, style: muted),
                ),
                if (showPermissions)
                  SizedBox(
                    width: 104,
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
      // Dragging a chosen row takes everything chosen with it.
      final dragged = on ? selection.of(entries) : [e];
      return Draggable<FileDrag>(
        data: FileDrag(side, dragged),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: c.brand,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              dragged.length == 1 ? dragged.single.name : t.selectedCount(dragged.length),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        child: content,
      );
    }

    final table = Column(
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              header(t.columnName, SortBy.name),
              header(t.columnSize, SortBy.size, width: 96),
              header(t.columnModified, SortBy.modified, width: 170),
              if (showPermissions) header(t.permissionsTitle, null, width: 104),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(empty ?? '', style: TextStyle(color: c.muted)),
                )
              : Focus(
                  focusNode: focusNode,
                  onKeyEvent: onKey,
                  child: ListenableBuilder(
                    listenable: selection,
                    builder: (context, _) => ListView.builder(
                      key: ValueKey('filesTable-${side.name}'),
                      itemCount: entries.length,
                      itemExtent: 36,
                      itemBuilder: (context, i) => row(entries[i]),
                    ),
                  ),
                ),
        ),
      ],
    );

    final drop = onDrop;
    if (drop == null) return table;
    return DragTarget<FileDrag>(
      onWillAcceptWithDetails: (d) => d.data.from != side,
      onAcceptWithDetails: (d) => drop(d.data),
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: candidates.isEmpty ? null : Border.all(color: c.brand, width: 2),
          color: candidates.isEmpty ? null : c.brand.withValues(alpha: 0.05),
        ),
        child: table,
      ),
    );
  }
}
