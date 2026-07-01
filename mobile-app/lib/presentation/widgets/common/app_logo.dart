import 'package:flutter/material.dart';

/// The GeoTag brand logo — the bare purple ribbon mark, rendered from one
/// shared asset so it stays consistent everywhere (splash, login, home header,
/// map header). No tile/background: just the mark.
///
/// The mark is solid purple on transparent, so it reads on light and dark
/// surfaces as-is. On the purple splash gradient it would disappear, so callers
/// there pass [tint] (white) to recolour it. Callers choose a [size]; [radius],
/// [withShadow] and [borderColor] are kept for API compatibility.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.radius,
    this.withShadow = false,
    this.borderColor,
    this.tint,
  });

  /// Width & height of the (square) logo in logical pixels.
  final double size;

  /// Retained for API compatibility (no longer used — there's no tile).
  final double? radius;

  /// Retained for API compatibility.
  final bool withShadow;

  /// Retained for API compatibility.
  final Color? borderColor;

  /// Recolour the mark (e.g. white on the purple splash gradient). When null
  /// the mark keeps its native brand purple.
  final Color? tint;

  static const String _asset = 'assets/geotag_mark.png';

  @override
  Widget build(BuildContext context) {
    Widget mark = Image.asset(
      _asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (tint != null) {
      mark = ColorFiltered(
        colorFilter: ColorFilter.mode(tint!, BlendMode.srcIn),
        child: mark,
      );
    }
    return SizedBox(width: size, height: size, child: mark);
  }
}
