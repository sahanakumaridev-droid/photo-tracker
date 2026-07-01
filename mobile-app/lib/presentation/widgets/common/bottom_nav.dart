import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Premium consumer tab bar — a floating, solid pill that sits with
/// margin above the bottom edge, with a centered, elevated Upload button.
///
/// Index map (matches the router shell):
///   0 Home · 1 Map · 2 Earnings · 3 Log · 4 Capture/Upload
/// Settings lives behind the top-bar avatar. The app launches on the Map but
/// Home stays available as its own tab.
class BottomNav extends StatelessWidget {
  const BottomNav({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const Color _muted = Color(0xFF9CA3AF);

  void _go(int i) {
    HapticFeedback.selectionClick();
    onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    // Follow the user's chosen accent so the picker recolours the whole app.
    final accent = Theme.of(context).colorScheme.primary;
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
              _tab(0, Icons.home_outlined, Icons.home_rounded, 'Home', accent),
              _tab(1, Icons.map_outlined, Icons.map_rounded, 'Map', accent),
              _tab(2, Icons.attach_money, Icons.monetization_on, 'Earnings',
                  accent),
              _tab(3, Icons.article_outlined, Icons.description_rounded, 'Log',
                  accent),
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
                          active: currentIndex == 4,
                          accent: accent,
                          onTap: () => _go(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: currentIndex == 4
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: currentIndex == 4 ? accent : _muted,
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: active
                    ? accent.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(active ? activeIcon : icon,
                  size: 20, color: active ? accent : _muted),
            ),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? accent : _muted)),
          ],
        ),
      ),
    );
  }
}

/// Floating Upload FAB with a brand gradient, glow shadow, and a tactile
/// press-down scale animation.
class _UploadButton extends StatefulWidget {
  const _UploadButton(
      {required this.active, required this.accent, required this.onTap});

  final bool active;
  final Color accent;
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.accent,
                Color.lerp(widget.accent, const Color(0xFF5445E6), 0.5)!,
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: widget.accent
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
