import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// Renders a bike marker with a name label. The leader is distinct by shape,
/// not color alone: an outer ring plus a star badge.
class RiderMarkerFactory {
  RiderMarkerFactory(this.scheme, this.devicePixelRatio);

  final ColorScheme scheme;
  final double devicePixelRatio;
  final Map<String, BitmapDescriptor> _cache = {};

  static const double _disc = 40; // logical px
  static const double _ring = 6;

  /// [headingDeg] is bucketed to 15° so the cache stays small.
  Future<BitmapDescriptor> build({
    required String name,
    required bool leader,
    bool isSelf = false,
    double? headingDeg,
    String youLabel = 'You',
  }) async {
    final bucket = headingDeg == null ? null : ((headingDeg / 15).round() * 15) % 360;
    final key = '$name|$leader|$isSelf|$bucket';
    final cached = _cache[key];
    if (cached != null) return cached;

    final dpr = devicePixelRatio;
    final label = TextPainter(
      text: TextSpan(
        text: isSelf ? youLabel : (name.length > 14 ? '${name.substring(0, 13)}…' : name),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const outer = _disc + _ring * 2 + 4; // room for the ring
    final width = (label.width + 16).clamp(outer, 220.0);
    final height = outer + 6 + label.height + 8;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final cx = width / 2;
    const cy = outer / 2;

    if (leader) {
      canvas.drawCircle(
        Offset(cx, cy),
        _disc / 2 + _ring,
        Paint()
          ..color = scheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    final discColor =
        isSelf ? scheme.tertiary : (leader ? scheme.primary : scheme.secondaryContainer);
    if (bucket != null) {
      // Heading arrow on the rim, pointing the way the rider is going.
      final a = bucket * math.pi / 180;
      final r = _disc / 2 + _ring + 1;
      final tip = Offset(cx + r * math.sin(a), cy - r * math.cos(a));
      final back = _disc / 2 - 2;
      final left = Offset(cx + back * math.sin(a - 0.35), cy - back * math.cos(a - 0.35));
      final right = Offset(cx + back * math.sin(a + 0.35), cy - back * math.cos(a + 0.35));
      canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(left.dx, left.dy)..lineTo(right.dx, right.dy)..close(),
          Paint()..color = discColor);
    }
    canvas.drawCircle(Offset(cx, cy), _disc / 2, Paint()..color = discColor);
    canvas.drawCircle(
      Offset(cx, cy),
      _disc / 2,
      Paint()
        ..color = scheme.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    _paintIcon(canvas, Icons.two_wheeler, Offset(cx, cy), 22,
        isSelf ? scheme.onTertiary : (leader ? scheme.onPrimary : scheme.onSecondaryContainer));

    if (leader) {
      final badge = Offset(cx + _disc / 2 - 2, cy - _disc / 2 + 2);
      canvas.drawCircle(badge, 9, Paint()..color = scheme.tertiary);
      _paintIcon(canvas, Icons.star, badge, 13, scheme.onTertiary);
    }

    // Name pill
    final pillTop = outer + 6;
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, pillTop + (label.height + 6) / 2),
        width: label.width + 14,
        height: label.height + 6,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(
        pill, Paint()..color = isSelf ? scheme.tertiaryContainer : scheme.surfaceContainerHigh);
    label.paint(canvas, Offset(cx - label.width / 2, pillTop + 3));

    final image = await recorder
        .endRecording()
        .toImage((width * dpr).ceil(), (height * dpr).ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final bmp = BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: dpr);
    _cache[key] = bmp;
    return bmp;
  }

  /// Anchor so the disc centre (not the label) sits on the coordinate.
  static Offset anchorFor() => const Offset(0.5, 0.3);

  void _paintIcon(Canvas c, IconData icon, Offset center, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }
}
