import 'package:flutter/material.dart';

import '../theme.dart';
import 'desktop_sidebar.dart';

/// One saved thing in a page's list (a key, an identity, a snippet), drawn
/// as the hosts are: on the raised layer, with its icon in a tile, rising a
/// little under the pointer.
class ItemCard extends StatefulWidget {
  const ItemCard({
    super.key,
    this.tapKey,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.latinTitle = false,
  });

  /// On the part that is tapped, for tests and automation.
  final Key? tapKey;
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The icon's colour when it says something (a warning); the brand's
  /// otherwise.
  final Color? iconColor;

  /// The title is an address or other Latin text: left to right, at the
  /// start of the row in either direction.
  final bool latinTitle;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = widget.iconColor ?? c.brand;
    final lit = _hover && widget.onTap != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        transform: Matrix4.translationValues(0, lit ? -1 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [if (lit) BoxShadow(color: c.shadow, blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Material(
          color: c.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: lit ? c.brand.withValues(alpha: 0.45) : c.line),
          ),
          child: InkWell(
            key: widget.tapKey,
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.title,
                          textDirection: widget.latinTitle ? TextDirection.ltr : null,
                          textAlign: widget.latinTitle && Directionality.of(context) == TextDirection.rtl
                              ? TextAlign.right
                              : null,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          DefaultTextStyle.merge(
                            style: TextStyle(color: c.muted, fontSize: 12.5),
                            child: widget.subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?widget.trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [ItemCard]s side by side where there is room: as many columns as fit at
/// [minWidth] each, one on a phone.
class ItemGrid extends StatelessWidget {
  const ItemGrid({super.key, required this.children, this.minWidth = 320});

  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 12.0;
      final columns = ((box.maxWidth + gap) / (minWidth + gap)).floor().clamp(1, 4);
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    },
  );
}

/// Room around a page's list: the hosts' margins on the desktop, tighter on
/// a phone; [bottom] clears a floating button.
EdgeInsets listPadding(BuildContext context, {double bottom = 24}) {
  final side = isDesktopLayout(context) ? 28.0 : 12.0;
  return EdgeInsets.fromLTRB(side, 12, side, bottom);
}
