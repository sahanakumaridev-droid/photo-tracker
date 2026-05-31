import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The GeoTag brand logo, rendered from a single shared SVG so it stays
/// consistent everywhere (splash, login, home header, etc.).
///
/// The asset already includes the indigo rounded-icon background + the white
/// pin mark + the green accent dot, so callers only choose a [size]. Use
/// [withShadow] for floating placements (splash / login) and [borderColor]
/// when the logo sits on a similarly-coloured surface (the indigo header).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.radius,
    this.withShadow = false,
    this.borderColor,
  });

  /// Width & height of the (square) logo in logical pixels.
  final double size;

  /// Corner radius. Defaults to ~26% of [size] for an app-icon look.
  final double? radius;

  /// Drop a soft shadow behind the logo (nice on plain backgrounds).
  final bool withShadow;

  /// Optional hairline border — helps the logo read on indigo surfaces.
  final Color? borderColor;

  static const String _asset = 'assets/geotag_logo.svg';

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size * 0.26;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1.5)
            : null,
        boxShadow: withShadow
            ? [
                BoxShadow(
                  color: const Color(0xFF5445E6).withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: SvgPicture.asset(
          _asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
