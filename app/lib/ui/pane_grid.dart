import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Rows of panes whose sizes the user sets: the line between two rows, or
/// between two panes of a row, is dragged to move it, and double-clicked
/// to make them even again. Sizes are kept while the same layout (the
/// number of panes in each row) stays.
class ResizableGrid extends StatefulWidget {
  const ResizableGrid({super.key, required this.rows});

  final List<List<Widget>> rows;

  /// The smallest a pane and a row can be dragged to, where there is room;
  /// a terminal narrower than that has nothing useful to show.
  static const minWidth = 240.0;
  static const minHeight = 140.0;

  /// How wide the draggable line is.
  static const divider = 6.0;

  @override
  State<ResizableGrid> createState() => _ResizableGridState();
}

class _ResizableGridState extends State<ResizableGrid> {
  late List<double> _rows;
  late List<List<double>> _columns;
  String? _shape;

  void _fit() {
    final shape = [for (final r in widget.rows) r.length].join(',');
    if (shape == _shape) return;
    _shape = shape;
    _rows = List.filled(widget.rows.length, 1 / widget.rows.length);
    _columns = [for (final r in widget.rows) List.filled(r.length, 1 / r.length)];
  }

  /// Moves the line after [index] in [shares] by [delta] pixels of [total],
  /// keeping both sides at least [least] pixels (or a sixth of the pair,
  /// when there is no room for that).
  void _move(List<double> shares, int index, double delta, double total, double least) {
    final pair = shares[index] + shares[index + 1];
    var min = least / total;
    if (2 * min > pair) min = pair / 6;
    final first = (shares[index] + delta / total).clamp(min, pair - min);
    setState(() {
      shares[index] = first;
      shares[index + 1] = pair - first;
    });
  }

  void _even(List<double> shares) => setState(() => shares.fillRange(0, shares.length, 1 / shares.length));

  @override
  Widget build(BuildContext context) {
    _fit();
    return LayoutBuilder(
      builder: (context, box) {
        final height = box.maxHeight - ResizableGrid.divider * (widget.rows.length - 1);
        return Column(
          children: [
            for (var r = 0; r < widget.rows.length; r++) ...[
              if (r > 0)
                _Divider(
                  key: ValueKey('rowDivider-${r - 1}'),
                  vertical: false,
                  onDrag: (d) => _move(_rows, r - 1, d, height, ResizableGrid.minHeight),
                  onReset: () => _even(_rows),
                ),
              SizedBox(
                height: height * _rows[r],
                child: LayoutBuilder(
                  builder: (context, rowBox) {
                    final panes = widget.rows[r];
                    final width = rowBox.maxWidth - ResizableGrid.divider * (panes.length - 1);
                    return Row(
                      children: [
                        for (var p = 0; p < panes.length; p++) ...[
                          if (p > 0)
                            _Divider(
                              key: ValueKey('columnDivider-$r-${p - 1}'),
                              vertical: true,
                              onDrag: (d) => _move(_columns[r], p - 1, d, width, ResizableGrid.minWidth),
                              onReset: () => _even(_columns[r]),
                            ),
                          SizedBox(
                            width: width * _columns[r][p],
                            child: ClipRect(child: panes[p]),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The line between two rows or two panes: dragged to move it, and
/// double-clicked to make its side even.
class _Divider extends StatelessWidget {
  const _Divider({super.key, required this.vertical, required this.onDrag, required this.onReset});

  final bool vertical;
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return MouseRegion(
      cursor: vertical ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragUpdate: vertical ? (d) => onDrag(rtl ? -d.delta.dx : d.delta.dx) : null,
        onVerticalDragUpdate: vertical ? null : (d) => onDrag(d.delta.dy),
        onDoubleTap: onReset,
        child: SizedBox(
          width: vertical ? ResizableGrid.divider : double.infinity,
          height: vertical ? double.infinity : ResizableGrid.divider,
          child: Center(
            child: Container(
              width: vertical ? 1 : double.infinity,
              height: vertical ? double.infinity : 1,
              color: c.line,
            ),
          ),
        ),
      ),
    );
  }
}
