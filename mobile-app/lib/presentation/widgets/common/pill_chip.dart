import 'package:flutter/material.dart';

import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/category.dart';

/// Base soft-color icon+label pill renderer, shared by [PriorityChip] and
/// [StatusChip]. Sizing params exist so each call site can reproduce its
/// existing exact geometry rather than forcing one size everywhere.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    this.radius = 20,
    this.border = false,
    this.borderAlpha = 0.3,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    this.iconSize = 11,
    this.fontSize = 11,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
  final double radius;
  final bool border;
  final double borderAlpha;
  final EdgeInsets padding;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(color: color.withValues(alpha: borderAlpha))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: fontSize, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Priority pill (ASAP/Special/Standard/Next Day) sourced from
/// [categoryOf] — the single centralized color/icon/label source in
/// `core/utils/category.dart`.
class PriorityChip extends StatelessWidget {
  const PriorityChip({
    super.key,
    required this.category,
    this.radius = 20,
    this.border = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    this.iconSize = 11,
    this.fontSize = 11,
  });

  final String? category;
  final double radius;
  final bool border;
  final EdgeInsets padding;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(category);
    return PillChip(
      label: cat.label,
      icon: cat.icon,
      color: cat.color,
      background: cat.softColor,
      radius: radius,
      border: border,
      padding: padding,
      iconSize: iconSize,
      fontSize: fontSize,
    );
  }
}

/// Attempt-outcome pill (Pending/Successful/Unsuccessful) sourced from
/// [attemptStatusByValue] in `core/utils/attempt_status.dart`.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.radius = 20,
    this.border = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    this.iconSize = 11,
    this.fontSize = 11,
  });

  final String? status;
  final double radius;
  final bool border;
  final EdgeInsets padding;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final opt = attemptStatusByValue(status) ?? kAttemptStatuses.first;
    return PillChip(
      label: opt.label,
      icon: opt.icon,
      color: opt.color,
      background: opt.softColor,
      radius: radius,
      border: border,
      padding: padding,
      iconSize: iconSize,
      fontSize: fontSize,
    );
  }
}
