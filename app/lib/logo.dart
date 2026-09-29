import 'package:flutter/material.dart';

/// The product mark: a tilde on a rounded tile. The geometry is the one in
/// panel/public/favicon.svg, drawn in the same 32x32 box. Decorative: the
/// product name next to it carries the meaning.
class TildeckLogo extends StatelessWidget {
  const TildeckLogo({super.key, required this.tile, required this.stroke, this.size = 28});

  final Color tile;
  final Color stroke;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _LogoPainter(tile, stroke)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.tile, this.stroke);

  final Color tile;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 32, 32), const Radius.circular(8)),
      Paint()..color = tile,
    );
    final wave = Path()
      ..moveTo(7.5, 18.5)
      ..cubicTo(9.1, 14.7, 11.9, 13.5, 14.5, 16)
      ..cubicTo(17.1, 18.5, 19.9, 17.3, 21.5, 13.5);
    canvas.drawPath(
      wave,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.tile != tile || old.stroke != stroke;
}
