part of 'map_view_screen.dart';

class _PinMarker extends StatefulWidget {
  const _PinMarker({
    required this.color,
    required this.selected,
    this.glow = false,
    this.label,
  });

  final Color color;
  final bool selected;
  final bool glow;
  final String? label;

  @override
  State<_PinMarker> createState() => _PinMarkerState();
}

class _PinMarkerState extends State<_PinMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.glow) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PinMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.glow && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.glow && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final head = widget.selected ? 26.0 : 22.0;
    final pin = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        SizedBox(
          width: head + 8,
          height: head + 14,
          child: CustomPaint(
            painter: _PinTipPainter(
              color: widget.color,
              selected: widget.selected,
            ),
          ),
        ),
      ],
    );
    if (!widget.glow) return pin;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 2,
              child: Container(
                width: 28 + t * 10,
                height: 28 + t * 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.28),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 2 + t * 3,
                    ),
                  ],
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: pin,
    );
  }
}


class _PinTipPainter extends CustomPainter {
  _PinTipPainter({required this.color, this.selected = false});

  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final r = size.width / 2;
    final head = Offset(r, r * 0.85);
    final headRadius = r * 0.72;
    canvas.drawCircle(head, headRadius, paint);
    final tip = ui.Path()
      ..moveTo(r - headRadius * 0.55, head.dy + headRadius * 0.35)
      ..quadraticBezierTo(r, size.height * 0.72, r, size.height - 1)
      ..quadraticBezierTo(
        r,
        size.height * 0.72,
        r + headRadius * 0.55,
        head.dy + headRadius * 0.35,
      )
      ..close();
    canvas.drawPath(tip, paint);
    canvas.drawCircle(
      head,
      headRadius * 0.38,
      Paint()..color = Colors.white,
    );
    if (selected) {
      canvas.drawCircle(
        head,
        headRadius + 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PinTipPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.selected != selected;
}

/// Finger-steered action wheel. Drag around the circle to swap the
/// highlighted action. Lift to choose it.
class _HotRouteBubbles extends StatefulWidget {
  const _HotRouteBubbles({
    required this.origin,
    required this.mileageOn,
    required this.attemptEnabled,
    required this.centerLabel,
    required this.onDismiss,
    required this.onChoice,
  });

  final Offset origin;
  final bool mileageOn;
  final bool attemptEnabled;
  final String centerLabel;
  final VoidCallback onDismiss;
  final ValueChanged<String> onChoice;

  @override
  State<_HotRouteBubbles> createState() => _HotRouteBubblesState();
}

class _WheelItem {
  const _WheelItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.color,
  });
  final String id;
  final IconData icon;
  final String label;
  final Color color;
}

class _HotRouteBubblesState extends State<_HotRouteBubbles> {
  int _index = 0;

  List<_WheelItem> get _items => [
        const _WheelItem(
          id: 'hot',
          icon: Icons.local_fire_department_rounded,
          label: 'Hot route',
          color: Color(0xFFEA580C),
        ),
        const _WheelItem(
          id: 'camera',
          icon: Icons.photo_camera_rounded,
          label: 'Camera',
          color: _kInk,
        ),
        _WheelItem(
          id: 'attempt',
          icon: Icons.add_location_alt_rounded,
          label: widget.attemptEnabled ? 'Attempt' : 'Attempt',
          color: widget.attemptEnabled ? _kAccent : const Color(0xFF94A3B8),
        ),
        _WheelItem(
          id: 'mileage',
          icon: Icons.directions_car_filled_rounded,
          label: widget.mileageOn ? 'Mileage on' : 'Mileage',
          color: widget.mileageOn ? _kAccent : const Color(0xFF5C6778),
        ),
      ];

  void _selectFromFinger(Offset local, Offset center) {
    final delta = local - center;
    if (delta.distance < 28) return;
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final count = _items.length;
    final slot = (angle / (math.pi * 2) * count).floor() % count;
    if (slot == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = slot);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cx = widget.origin.dx.clamp(120.0, math.max(120.0, size.width - 120));
    final items = _items;
    final selected = items[_index];

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final cy = widget.origin.dy.clamp(130.0, math.max(130.0, h - 150));
        const wheel = 220.0;
        const hub = wheel / 2;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismiss,
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: cx - hub,
              top: cy - hub,
              width: wheel,
              height: wheel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _selectFromFinger(d.localPosition, const Offset(hub, hub)),
                onTapUp: (_) {
                  HapticFeedback.mediumImpact();
                  widget.onChoice(items[_index].id);
                },
                onPanStart: (d) =>
                    _selectFromFinger(d.localPosition, const Offset(hub, hub)),
                onPanUpdate: (d) =>
                    _selectFromFinger(d.localPosition, const Offset(hub, hub)),
                onPanEnd: (_) {
                  HapticFeedback.mediumImpact();
                  widget.onChoice(items[_index].id);
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _WheelDisc(
                            count: items.length,
                            selected: _index,
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        child: SizedBox(
                          key: ValueKey(selected.id),
                          width: 86,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selected.label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_index + 1} / ${items.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7DD3FC),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < items.length; i++)
                      _placed(
                        index: i,
                        count: items.length,
                        hub: hub,
                        selected: i == _index,
                        item: items[i],
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _placed({
    required int index,
    required int count,
    required double hub,
    required bool selected,
    required _WheelItem item,
  }) {
    const ring = 74.0;
    final angle = (math.pi * 2 * index / count) - math.pi / 2;
    final dx = hub + ring * math.cos(angle) - 16;
    final dy = hub + ring * math.sin(angle) - 16;
    return Positioned(
      left: dx,
      top: dy,
      child: Icon(
        item.icon,
        color: selected ? Colors.white : const Color(0xE6FFFFFF),
        size: selected ? 30 : 24,
      ),
    );
  }
}

class _WheelDisc extends CustomPainter {
  _WheelDisc({required this.count, required this.selected});

  final int count;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2 - 1;
    const inner = 42.0;
    final sweep = math.pi * 2 / count;
    for (var i = 0; i < count; i++) {
      final start = -math.pi / 2 + i * sweep - sweep / 2;
      final path = ui.Path()
        ..moveTo(
          center.dx + inner * math.cos(start),
          center.dy + inner * math.sin(start),
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: outer),
          start,
          sweep,
          false,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: inner),
          start + sweep,
          -sweep,
          false,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = i == selected
              ? const Color(0x99FFFFFF)
              : const Color(0x5522262E),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0x66FFFFFF),
      );
    }
    canvas.drawCircle(
      center,
      inner,
      Paint()..color = const Color(0xCC1A2130),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outer - 3),
      math.pi * 0.72,
      0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF4A90E2),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelDisc oldDelegate) =>
      oldDelegate.selected != selected;
}

class _SpinRing extends StatefulWidget {
  const _SpinRing({required this.size});
  final double size;

  @override
  State<_SpinRing> createState() => _SpinRingState();
}

class _SpinRingState extends State<_SpinRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _spin,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _RingPainter(),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x66FFFFFF);
    canvas.drawCircle(center, radius, ring);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4A90E2);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      1.2,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Map/List segmented toggle — "List" opens the classic feed screen ───────
class _MapListToggle extends StatelessWidget {
  const _MapListToggle({required this.onListTap});
  final VoidCallback onListTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xF2FFFFFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _kSep),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _kAccent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_rounded, size: 14, color: Colors.white),
              SizedBox(width: 5),
              Text('Map',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onListTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.list_rounded, size: 14, color: _kInkMuted),
                SizedBox(width: 5),
                Text('List',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kInkMuted)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Map controls: fit, locate (crosshairs), filter sheet, mileage.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onFitTap,
    required this.userPosition,
    required this.loading,
    required this.onLocateTap,
    required this.onFilterTap,
    this.followingUser = false,
    this.filterActive = false,
  });
  final VoidCallback onFitTap;
  final Position? userPosition;
  final bool loading;
  final VoidCallback onLocateTap;
  final VoidCallback onFilterTap;
  final bool followingUser;
  final bool filterActive;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _fabBtn(icon: Icons.crop_free_rounded, onTap: onFitTap, label: 'Fit all'),
      const SizedBox(height: 10),
      _LocationFab(
        userPosition: userPosition,
        following: followingUser,
        loading: loading,
        onTap: onLocateTap,
      ),
      const SizedBox(height: 10),
      _fabBtn(
        icon: Icons.layers_rounded,
        onTap: onFilterTap,
        accent: filterActive,
      ),
      const SizedBox(height: 10),
      _MileageFab(),
    ],
  );

  Widget _fabBtn({
    required IconData icon,
    required VoidCallback onTap,
    String? label,
    bool accent = false,
  }) =>
      Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent ? _kAccent : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, size: 20, color: accent ? Colors.white : _kInk),
              ),
              if (label != null) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                    shadows: [Shadow(color: Colors.white, blurRadius: 6)],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _MileageFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MileageTracker.instance,
      builder: (context, _) {
        final on = MileageTracker.instance.tracking;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            final container = ProviderScope.containerOf(context);
            final dio = container.read(dioProvider);
            final email = container.read(authProvider).email;
            MileageTracker.instance.toggle(dio, email: email);
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: on ? _kAccent : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.directions_car_filled_rounded,
              size: 20,
              color: on ? Colors.white : _kInk,
            ),
          ),
        );
      },
    );
  }
}

/// Google Maps–style “you are here”: heading cone, white-ringed blue dot.
/// The translucent accuracy disc is a geographic CircleLayer, so it only
/// reads as a halo once the map is zoomed in.
class _GoogleBlueDot extends StatelessWidget {
  const _GoogleBlueDot({required this.headingDeg, required this.showCone});

  final double headingDeg;
  final bool showCone;

  @override
  Widget build(BuildContext context) {
    final heading = headingDeg.isFinite && headingDeg >= 0 ? headingDeg : 0.0;
    return Transform.rotate(
      angle: heading * math.pi / 180,
      child: CustomPaint(
        size: const Size(92, 92),
        painter: _GoogleLocationPainter(showCone: showCone),
      ),
    );
  }
}

class _GoogleLocationPainter extends CustomPainter {
  _GoogleLocationPainter({required this.showCone});

  final bool showCone;
  static const _blue = Color(0xFF1A73E8);
  static const _halo = Color(0xFF4285F4);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    const coneLen = 42.0;
    const sweep = 0.78;

    // Soft accuracy halo — the light-blue disc from Google Maps.
    canvas.drawCircle(
      c,
      22,
      Paint()..color = _halo.withValues(alpha: 0.22),
    );

    if (showCone) {
      final cone = ui.Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(
          Rect.fromCircle(center: c, radius: coneLen),
          -math.pi / 2 - sweep / 2,
          sweep,
          false,
        )
        ..close();
      canvas.drawPath(
        cone,
        Paint()
          ..shader = ui.Gradient.radial(
            c,
            coneLen,
            [
              _halo.withValues(alpha: 0.42),
              _halo.withValues(alpha: 0.18),
              _halo.withValues(alpha: 0.0),
            ],
            const [0.0, 0.48, 1.0],
          ),
      );
    }

    canvas.drawCircle(
      c,
      10,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawCircle(c, 8.4, Paint()..color = Colors.white);
    canvas.drawCircle(c, 5.6, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(covariant _GoogleLocationPainter oldDelegate) =>
      oldDelegate.showCone != showCone;
}

