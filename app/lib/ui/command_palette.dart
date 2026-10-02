import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// One thing the palette can do: open a tab, connect to a host, go to a
/// section, or run an action.
class PaletteItem {
  const PaletteItem({required this.icon, required this.title, required this.kind, this.detail, required this.run});

  final IconData icon;
  final String title;

  /// What it is ("Open tab", "Connect"), shown at the end of its row.
  final String kind;

  /// More to match and show: a host's address, say.
  final String? detail;
  final VoidCallback run;

  bool matches(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final text = '$title ${detail ?? ''} $kind'.toLowerCase();
    return words.every(text.contains);
  }
}

/// Finds anything by typing: Ctrl+Shift+P on the desktop.
Future<void> showCommandPalette(BuildContext context, List<PaletteItem> items) async {
  final chosen = await showDialog<PaletteItem>(
    context: context,
    builder: (_) => _CommandPalette(items: items),
  );
  chosen?.run();
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.items});

  final List<PaletteItem> items;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _query = TextEditingController();
  int _current = 0;

  static const _maxShown = 50;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<PaletteItem> get _shown => widget.items.where((i) => i.matches(_query.text)).take(_maxShown).toList();

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final shown = _shown;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _current = shown.isEmpty ? 0 : (_current + 1) % shown.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _current = shown.isEmpty ? 0 : (_current - 1 + shown.length) % shown.length);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _choose() {
    final shown = _shown;
    if (shown.isNotEmpty) Navigator.pop(context, shown[_current.clamp(0, shown.length - 1)]);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = context.colors;
    final shown = _shown;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      child: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const ValueKey('paletteQuery'),
                  controller: _query,
                  autofocus: true,
                  onChanged: (_) => setState(() => _current = 0),
                  onSubmitted: (_) => _choose(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t.paletteHint,
                    isDense: true,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: c.line),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        t.paletteNoMatch,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final item = shown[i];
                        return ListTile(
                          key: ValueKey('paletteItem-$i'),
                          dense: true,
                          selected: i == _current,
                          selectedTileColor: c.brand.withValues(alpha: 0.14),
                          selectedColor: c.ink,
                          leading: Icon(item.icon, size: 20, color: c.brand),
                          title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: item.detail == null
                              ? null
                              : Text(
                                  item.detail!,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: c.muted),
                                ),
                          trailing: Text(item.kind, style: TextStyle(color: c.muted, fontSize: 12)),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
