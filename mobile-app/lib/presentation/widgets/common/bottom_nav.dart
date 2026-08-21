import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';

/// Flat dark tab bar matching the field-app reference: icon + label,
/// blue when active, muted grey otherwise.
class BottomNav extends StatelessWidget {
  const BottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const Color _muted = AppTheme.darkTextTertiary;

  void _go(int i) {
    HapticFeedback.selectionClick();
    onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayDark,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.darkNav,
          border: Border(
            top: BorderSide(color: AppTheme.darkBorder, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                _tab(0, Icons.home_outlined, Icons.home_rounded, 'Home',
                    accent),
                _tab(1, Icons.cloud_upload_outlined, Icons.cloud_upload_rounded,
                    'Upload', accent),
                _tab(2, Icons.receipt_long_outlined, Icons.receipt_long_rounded,
                    'Log', accent),
                _tab(3, Icons.payments_outlined, Icons.payments_rounded,
                    'Earnings', accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, IconData activeIcon, String label,
      Color accent) {
    final active = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1.0 : 0.96,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: Icon(
                active ? activeIcon : icon,
                size: 22,
                color: active ? accent : _muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? accent : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
