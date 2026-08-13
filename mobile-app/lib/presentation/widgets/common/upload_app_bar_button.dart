import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';

/// App-bar Upload action — replaces the old bottom-nav tab.
class UploadAppBarButton extends StatelessWidget {
  const UploadAppBarButton({this.compact = false, super.key});

  /// Icon-only circle for tight headers (map search row).
  final bool compact;

  void _open(BuildContext context) {
    HapticFeedback.lightImpact();
    context.push('/upload');
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: () => _open(context),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(Icons.cloud_upload_rounded,
              size: 20, color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_rounded, size: 16, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'Upload',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
