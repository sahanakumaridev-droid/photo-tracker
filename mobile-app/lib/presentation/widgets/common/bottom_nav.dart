import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Premium consumer tab bar — clean white surface with four flat tabs and a
/// centered, elevated Capture button (Instagram / Airbnb style).
///
/// Index map (matches the router shell):
///   0 Home · 1 Map · 2 Capture/Upload · 3 Log · 4 Settings
class BottomNav extends StatelessWidget {
  const BottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const Color _purple = Color(0xFF7C3AED); // purple accent
  static const Color _black = Color(0xFF0F0F0F); // primary action
  static const Color _muted = Color(0xFF9CA3AF);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _hair = Color(0xFFE5E7EB);

  void _go(int i) {
    HapticFeedback.selectionClick();
    onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _card,
        border: Border(top: BorderSide(color: _hair)),
        boxShadow: [
          BoxShadow(
              color: Color(0x0F0F172A), blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  _tab(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                  _tab(1, Icons.map_outlined, Icons.map_rounded, 'Map'),
                  // Center gap — reserves space under the floating button.
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text('Capture',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: currentIndex == 2 ? _purple : _muted)),
                      ),
                    ),
                  ),
                  _tab(3, Icons.receipt_long_outlined,
                      Icons.receipt_long_rounded, 'Log'),
                  _tab(4, Icons.settings_outlined, Icons.settings_rounded,
                      'Settings'),
                ],
              ),
              // Floating capture button.
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(child: _captureButton()),
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
            Icon(active ? activeIcon : icon,
                size: 24, color: active ? _purple : _muted),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? _purple : _muted)),
          ],
        ),
      ),
    );
  }

  Widget _captureButton() {
    final active = currentIndex == 2;
    return GestureDetector(
      onTap: () => _go(2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _black,
          shape: BoxShape.circle,
          border: Border.all(color: _card, width: 4),
          boxShadow: [
            BoxShadow(
              color: _black.withValues(alpha: active ? 0.45 : 0.32),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add_a_photo_rounded,
            color: Colors.white, size: 25),
      ),
    );
  }
}
