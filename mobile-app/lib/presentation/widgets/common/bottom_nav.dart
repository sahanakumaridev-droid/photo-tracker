import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Premium consumer tab bar — a floating, solid pill that sits with
/// margin above the bottom edge, with a centered, elevated Upload button.
///
/// Index map (matches the router shell):
///   0 Home · 1 Map · 2 Earnings · 3 Log · 4 Settings · 5 Capture/Upload
class BottomNav extends StatelessWidget {
  const BottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const Color _purple = Color(0xFF7C3AED); // purple accent
  static const Color _indigo = Color(0xFF5445E6); // brand indigo (logo/icon)
  static const Color _muted = Color(0xFF9CA3AF);
  static const Color _activePill = Color(0xFFF3E8FF); // soft purple pill

  void _go(int i) {
    HapticFeedback.selectionClick();
    onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _tab(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
              _tab(1, Icons.map_outlined, Icons.map_rounded, 'Map'),
              _tab(2, Icons.payments_outlined, Icons.payments_rounded,
                  'Earnings'),
              _tab(3, Icons.receipt_long_outlined,
                  Icons.receipt_long_rounded, 'Log'),
              _tab(4, Icons.settings_outlined, Icons.settings_rounded,
                  'Settings'),
              // End gap — hosts the floating Upload button above its own cell.
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned(
                        top: -22,
                        child: _UploadButton(
                          active: currentIndex == 5,
                          onTap: () => _go(5),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: currentIndex == 5
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: currentIndex == 5 ? _purple : _muted,
                          ),
                          child: const Text('Upload'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, IconData activeIcon, String label) {
    final active = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _go(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: active ? _activePill : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(active ? activeIcon : icon,
                  size: 20, color: active ? _purple : _muted),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? _purple : _muted)),
          ],
        ),
      ),
    );
  }
}

/// Floating Upload FAB with a brand gradient, glow shadow, and a tactile
/// press-down scale animation.
class _UploadButton extends StatefulWidget {
  const _UploadButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  State<_UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<_UploadButton> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [BottomNav._purple, BottomNav._indigo],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: BottomNav._purple
                    .withValues(alpha: widget.active ? 0.45 : 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.upload_rounded,
              color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
