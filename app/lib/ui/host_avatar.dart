import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../ssh/host_os.dart';
import '../theme.dart';
import '../vault/models.dart';
import 'os_logos.dart';

/// The colour of each [HostTint]: mid tones that read on light and dark.
const hostTintColors = <HostTint, Color>{
  HostTint.teal: Color(0xFF0FA89A),
  HostTint.blue: Color(0xFF3478E5),
  HostTint.green: Color(0xFF2E9E4F),
  HostTint.amber: Color(0xFFD99A06),
  HostTint.orange: Color(0xFFE5672A),
  HostTint.red: Color(0xFFD93A3A),
  HostTint.pink: Color(0xFFD9468C),
  HostTint.slate: Color(0xFF5B6B7C),
};

/// A host's mark: its system's logo, on its own colour if it has one, else
/// on the system's; a plain server (or cable, for a serial line) until the
/// system is known.
class HostAvatar extends StatelessWidget {
  const HostAvatar({super.key, this.os, this.tint, this.serial = false, this.telnet = false, this.size = 38});

  HostAvatar.of(HostEntry host, {Key? key, double size = 38})
    : this(key: key, os: host.os, tint: host.tint, serial: host.isSerial, telnet: host.isTelnet, size: size);

  final HostOs? os;
  final HostTint? tint;
  final bool serial;
  final bool telnet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final logo = osLogos[os];
    // Black brands (AlmaLinux) would vanish on a dark page.
    final brand = logo == null || logo.color.computeLuminance() < 0.02 ? null : logo.color;
    final fill =
        hostTintColors[tint] ??
        brand ??
        switch (os) {
          HostOs.windows => const Color(0xFF0078D4),
          null => null,
          _ => c.muted,
        };
    final glyph = fill == null
        ? c.brand
        : fill.computeLuminance() > 0.45
        ? const Color(0xFF1B1F24)
        : Colors.white;
    final inner = size * 0.56;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill ?? c.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: logo != null
          ? CustomPaint(size: Size.square(inner), painter: _LogoPainter(logo.path, glyph))
          : Icon(
              switch (os) {
                HostOs.windows => Icons.window_rounded,
                HostOs.macos => Icons.laptop_mac_rounded,
                _ when serial => Icons.usb_rounded,
                _ when telnet => Icons.lan_outlined,
                _ => Icons.dns_outlined,
              },
              size: inner,
              color: glyph,
            ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.data, this.color);

  final String data;
  final Color color;

  static final _paths = <String, Path>{};

  static Path _parse(String data) => _paths.putIfAbsent(data, () {
    final writer = _PathWriter();
    writeSvgPathDataToPath(data, writer);
    return writer.path;
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_parse(data), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.data != data || old.color != color;
}

class _PathWriter extends PathProxy {
  final path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
