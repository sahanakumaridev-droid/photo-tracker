import 'package:flutter/material.dart';

/// Full SRVBOARD app icon (splash, login, headers).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.radius,
    this.withShadow = false,
    this.borderColor,
    this.tint,
  });

  final double size;
  final double? radius;
  final bool withShadow;
  final Color? borderColor;
  final Color? tint;

  static const String _asset = 'assets/icons/srvboard_full.png';

  @override
  Widget build(BuildContext context) {
    Widget mark = Image.asset(
      _asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
    if (withShadow) {
      mark = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: mark,
      );
    }
    return SizedBox(width: size, height: size, child: mark);
  }
}
