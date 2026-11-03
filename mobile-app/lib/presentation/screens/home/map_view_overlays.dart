part of 'map_view_screen.dart';

class _FloatingHeader extends StatelessWidget {
  const _FloatingHeader({
    required this.onRefresh,
    required this.photoCount,
    required this.pinCount,
  });
  final VoidCallback onRefresh;
  final int photoCount;
  final int pinCount;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
                children: [
                  TextSpan(
                    text: 'SRV',
                    style: TextStyle(color: _kAccent),
                  ),
                  TextSpan(
                    text: 'BOARD',
                    style: TextStyle(color: _kInk),
                  ),
                ],
              ),
            ),
            if (photoCount > 0) ...[
              const SizedBox(height: 1),
              Text(
                '$photoCount photo${photoCount != 1 ? 's' : ''}'
                ' · $pinCount pin${pinCount != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: _kInkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onRefresh();
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _kFab,
            shape: BoxShape.circle,
            border: Border.all(color: _kSep),
          ),
          child: const Icon(
            Icons.refresh_rounded,
            size: 18,
            color: _kInk,
          ),
        ),
      ),
      const SizedBox(width: 8),
      // Settings / account — the single entry point now that the bottom
      // Settings tab has been removed.
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          context.push('/settings');
        },
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: _kAccent,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    ],
  );
}

// ── Search bar ────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
  });
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded, color: _kSubtle, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(fontSize: 14, color: _kInk),
              decoration: const InputDecoration(
                hintText: 'Search location, profile or ZIP',
                hintStyle: TextStyle(color: _kSubtle, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
                isDense: true,
              ),
            ),
          ),
          VoiceMicButton(
            controller: controller,
            tooltip: 'Search by voice',
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: controller.clear,
              child: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.close_rounded, size: 18, color: _kSubtle),
              ),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Hint pill ─────────────────────────────────────────────────────────────────
class _HintPill extends StatelessWidget {
  const _HintPill();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.center,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded, size: 11, color: Colors.white70),
          SizedBox(width: 5),
          Text(
            'Tap map to upload  ·  Tap pin to view',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── My-location FAB ───────────────────────────────────────────────────────────
class _LocationFab extends StatelessWidget {
  const _LocationFab({
    required this.onTap,
    this.userPosition,
    this.following = false,
    this.loading = false,
  });
  final VoidCallback onTap;
  final Position?    userPosition;
  final bool         following;
  final bool         loading;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: following ? const Color(0xFF1A73E8) : Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: loading
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kAccent,
                ),
              ),
            )
          : Icon(
              Icons.my_location_rounded,
              size: 20,
              color: following
                  ? Colors.white
                  : (userPosition != null ? _kInk : _kSubtle),
            ),
    ),
  );
}

// ── Empty state shown when the active filter matches zero pins ───────────────
class _EmptyFilterCard extends StatelessWidget {
  const _EmptyFilterCard({required this.onClearFilters});
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
    decoration: BoxDecoration(
      color: _kSurface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.11),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.filter_alt_off_rounded,
              size: 20, color: _kAccent),
        ),
        const SizedBox(height: 10),
        const Text(
          'No pins match your filters',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: _kInk),
        ),
        const SizedBox(height: 4),
        const Text(
          'Try widening the distance or picking a different priority level.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: _kInkMuted),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _CardBtn(
            icon: Icons.filter_alt_off_rounded,
            label: 'Clear Filters',
            onTap: onClearFilters,
            filled: true,
          ),
        ),
      ],
    ),
  );
}

// ── Selected-pin job card ────────────────────────────────────────────────────
class _JobPreviewCard extends StatefulWidget {
  const _JobPreviewCard({
    super.key,
    required this.attempts,
    required this.address,
    required this.lat,
    required this.lng,
    required this.title,
    required this.onNewAttempt,
    required this.onPreviewPhoto,
    this.photos = const [],
    this.distance,
    this.atCap = false,
    this.pending = false,
    this.attemptEnabled = true,
  });

  final int attempts;
  final bool atCap;
  final bool pending;
  final bool attemptEnabled;
  final String? distance;
  final String address;
  final double lat;
  final double lng;
  final String title;
  final List<PhotoModel> photos;
  final VoidCallback onNewAttempt;
  final ValueChanged<int> onPreviewPhoto;

  @override
  State<_JobPreviewCard> createState() => _JobPreviewCardState();
}

class _JobPreviewCardState extends State<_JobPreviewCard> {
  final _page = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(_JobPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.photos, widget.photos)) {
      _index = 0;
      if (_page.hasClients) _page.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final preview =
        widget.photos.where((p) => p.imageUrl.trim().isNotEmpty).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xF7FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kSep),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 132,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _page,
                      itemCount: preview.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onPreviewPhoto(i),
                        child: CachedNetworkImage(
                          imageUrl: preview[i].imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const ColoredBox(
                            color: Color(0xFFE8EDF3),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => const ColoredBox(
                            color: Color(0xFFE8EDF3),
                            child: Icon(
                              Icons.photo_outlined,
                              color: _kSubtle,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (preview.length > 1) ...[
                      Positioned(
                        right: 8,
                        top: 8,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_index + 1}/${preview.length}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 8,
                        child: IgnorePointer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < preview.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  curve: const Cubic(0.23, 1, 0.32, 1),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _index ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: i == _index
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.distance != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(widget.distance!,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kInkMuted)),
            ),
          if (widget.pending) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kPending.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Pending',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kPending,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _kInk,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              MapsLauncher.openLocation(
                address: widget.address,
                lat: widget.lat,
                lng: widget.lng,
              );
            },
            child: Text(
              widget.address,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _kAccent,
                height: 1.3,
                decoration: TextDecoration.underline,
                decorationColor: _kAccent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE3E7EE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${widget.attempts} of ${AttemptDraftController.kMaxAttemptsPerJob} '
              'attempt${widget.attempts == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.atCap ? const Color(0xFFFBBF24) : _kInkMuted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: IntrinsicWidth(
              child: _CardBtn(
                icon: widget.atCap || !widget.attemptEnabled
                    ? Icons.block_rounded
                    : Icons.add_rounded,
                label: widget.atCap
                    ? 'Max attempts'
                    : widget.attemptEnabled
                        ? 'Add Attempt'
                        : 'Add Attempt',
                onTap: widget.atCap || !widget.attemptEnabled
                    ? null
                    : widget.onNewAttempt,
                filled: !widget.atCap && widget.attemptEnabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card action button ────────────────────────────────────────────────────────
class _CardBtn extends StatelessWidget {
  const _CardBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });
  final IconData     icon;
  final String       label;
  final VoidCallback? onTap;
  final bool         filled;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: filled ? _kAccent : const Color(0xFFE3E7EE),
          borderRadius: BorderRadius.circular(24),
          border: filled ? null : Border.all(color: _kSep),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: _kAccent.withValues(alpha: 0.28),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: filled ? Colors.white : _kInk),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : _kInk,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Job pin — filled teardrop, blue or yellow (pending). ─────────────────────
