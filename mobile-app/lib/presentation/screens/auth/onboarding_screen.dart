import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/category.dart';
import '../../providers/auth_provider.dart';

/// Three animated intro screens shown after the splash, before login.
///
/// Illustrations are pure vector (Flutter widgets + [flutter_animate]) so the
/// app ships no extra binary assets — every shape animates in and keeps a
/// subtle continuous motion.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFF4A90E2);
  static const Color _accent2 = Color(0xFF1E88E5);
  static const Color _ink = Color(0xFFFFFFFF);
  static const Color _inkMuted = Color(0xFF94A3B8);
  static const Color _inkSubtle = Color(0xFF6B7A8D);
  static const Color _canvas = Color(0xFF0F1219);

  final PageController _controller = PageController();
  int _page = 0;

  List<_OnboardData> get _pages => const [
        _OnboardData(
          title: 'Capture on location',
          body:
              'Snap a photo and it’s instantly tagged with exact GPS coordinates and a street address — no manual entry.',
          illustration: _CaptureIllustration(),
        ),
        _OnboardData(
          title: 'Organize by priority',
          body:
              'Tag every photo Standard, Special, Next Day or ASAP. Colour-coded categories keep urgent work front and centre.',
          illustration: _CategoryIllustration(),
        ),
        _OnboardData(
          title: 'Track, filter & export',
          body:
              'Review your activity log, filter by date or category, and email a clean report in a single tap.',
          illustration: _ExportIllustration(),
        ),
      ];

  bool get _isLast => _page == _pages.length - 1;

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    // Persist + update auth state so the router redirect lets us reach /login.
    await ref.read(authProvider.notifier).completeOnboarding();
    if (mounted) context.go('/login');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    HapticFeedback.selectionClick();
    _controller.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: Column(
          children: [
            // ── Skip ───────────────────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _isLast ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: _isLast ? null : _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _inkSubtle,
                    ),
                  ),
                ),
              ),
            ),
            // ── Pages ────────────────────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final data = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 300,
                          child: Center(child: data.illustration),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          data.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.5,
                          ),
                        )
                            .animate(key: ValueKey('title$i'))
                            .fadeIn(duration: 450.ms, delay: 120.ms)
                            .slideY(begin: 0.25, end: 0, curve: Curves.easeOut),
                        const SizedBox(height: 14),
                        Text(
                          data.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: _inkMuted,
                          ),
                        )
                            .animate(key: ValueKey('body$i'))
                            .fadeIn(duration: 450.ms, delay: 240.ms)
                            .slideY(begin: 0.25, end: 0, curve: Curves.easeOut),
                      ],
                    ),
                  );
                },
              ),
            ),
            // ── Dots + button ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 26 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? _accent
                                : _accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_accent, _accent2],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isLast ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isLast
                                  ? CupertinoIcons.checkmark
                                  : CupertinoIcons.arrow_right,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardData {
  const _OnboardData({
    required this.title,
    required this.body,
    required this.illustration,
  });
  final String title;
  final String body;
  final Widget illustration;
}

// ── Shared building blocks ─────────────────────────────────────────────────

/// Soft circular backdrop that gently breathes.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.02)],
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1.04, 1.04),
          duration: 2600.ms,
          curve: Curves.easeInOut,
        );
  }
}

/// A floating "glass" badge holding a central icon.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Icon(icon, size: 56, color: color),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(begin: -7, end: 7, duration: 2200.ms, curve: Curves.easeInOut);
  }
}

// ── Page 1 · Capture on location ────────────────────────────────────────────
class _CaptureIllustration extends StatelessWidget {
  const _CaptureIllustration();

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4F46E5);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        const _Backdrop(color: accent),
        const _IconBadge(icon: CupertinoIcons.camera_fill, color: accent),
        // Location pin floating top-right
        Positioned(
          top: 24,
          right: 18,
          child: _floatingChip(
            const Icon(CupertinoIcons.location_fill,
                color: Color(0xFFDC2626), size: 22),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(
              begin: 6, end: -6, duration: 1800.ms, curve: Curves.easeInOut),
        ),
        // Coordinate tag bottom-left
        Positioned(
          bottom: 30,
          left: 6,
          child: _pillTag('37.77, -122.41', CupertinoIcons.location, accent)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                  begin: -5, end: 5, duration: 2000.ms, curve: Curves.easeInOut),
        ),
      ],
    );
  }
}

// ── Page 2 · Organize by priority ───────────────────────────────────────────
class _CategoryIllustration extends StatelessWidget {
  const _CategoryIllustration();

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF4A90E2);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        const _Backdrop(color: accent),
        const _IconBadge(icon: CupertinoIcons.tag_fill, color: accent),
        // The four real category chips, fanned around the badge.
        for (var i = 0; i < kPhotoCategories.length; i++)
          _categoryChipPositioned(kPhotoCategories[i], i),
      ],
    );
  }

  Widget _categoryChipPositioned(PhotoCategory c, int i) {
    // top-left, top-right, bottom-left, bottom-right
    final positions = <Map<String, double?>>[
      {'top': 16, 'left': 0},
      {'top': 30, 'right': 0},
      {'bottom': 30, 'left': 6},
      {'bottom': 14, 'right': 8},
    ];
    final p = positions[i];
    return Positioned(
      top: p['top'],
      bottom: p['bottom'],
      left: p['left'],
      right: p['right'],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: c.color.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.icon, size: 15, color: c.color),
          const SizedBox(width: 6),
          Text(
            c.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.color,
            ),
          ),
        ]),
      )
          .animate(onPlay: (ctrl) => ctrl.repeat(reverse: true))
          .moveY(
            begin: i.isEven ? -6 : 6,
            end: i.isEven ? 6 : -6,
            duration: (1800 + i * 220).ms,
            curve: Curves.easeInOut,
          ),
    );
  }
}

// ── Page 3 · Track, filter & export ─────────────────────────────────────────
class _ExportIllustration extends StatelessWidget {
  const _ExportIllustration();

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6B7280);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        const _Backdrop(color: accent),
        const _IconBadge(icon: CupertinoIcons.graph_square, color: accent),
        Positioned(
          top: 22,
          left: 8,
          child: _floatingChip(
            const Icon(CupertinoIcons.envelope_fill,
                color: Color(0xFF4F46E5), size: 20),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(
              begin: -6, end: 6, duration: 1900.ms, curve: Curves.easeInOut),
        ),
        Positioned(
          bottom: 26,
          right: 0,
          child: _pillTag('Export ready', CupertinoIcons.arrow_down, accent)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(
                  begin: 6, end: -6, duration: 2100.ms, curve: Curves.easeInOut),
        ),
        Positioned(
          top: 40,
          right: 14,
          child: _floatingChip(
            const Icon(CupertinoIcons.slider_horizontal_3,
                color: Color(0xFFCA8A04), size: 20),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(
              begin: 5, end: -5, duration: 1700.ms, curve: Curves.easeInOut),
        ),
      ],
    );
  }
}

// ── Small reusable decorations ──────────────────────────────────────────────
Widget _floatingChip(Widget child) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(child: child),
    );

Widget _pillTag(String text, IconData icon, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ]),
    );
