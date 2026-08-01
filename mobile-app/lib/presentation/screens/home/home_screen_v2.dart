import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/app_config.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/photo_stamp.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/app_logo.dart';
import '../../widgets/common/pill_chip.dart';

class HomeScreenV2 extends ConsumerStatefulWidget {
  const HomeScreenV2({super.key});

  @override
  ConsumerState<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends ConsumerState<HomeScreenV2> {
  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color _ink        = Color(0xFF0F0F0F);
  static const Color _muted      = Color(0xFF6B7280);
  static const Color _purple     = Color(0xFF7C3AED);
  static const Color _purpleSoft = Color(0xFFEDE9FE);
  static const Color _bg         = Color(0xFFFAFAFA);
  static const Color _card       = Color(0xFFFFFFFF);


  final Set<int> _optimisticFlips = {};
  Position? _devicePosition;
  String? _selectedCategory; // null = show all

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final pos = await LocationService.getCurrentLocation();
      if (mounted && pos != null) setState(() => _devicePosition = pos);
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  String _shortDate(String? ts) {
    if (ts == null) return '';
    try { return DateFormat('MMM d').format(DateTime.parse(ts).toLocal()); }
    catch (_) { return ''; }
  }

  String _relativeTime(String? ts) {
    if (ts == null) return '';
    try {
      final d = DateTime.parse(ts).toLocal();
      final diff = DateTime.now().difference(d);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(d);
    } catch (_) { return ''; }
  }

  String _placeLabel(PhotoModel p) {
    if (p.address != null && p.address!.trim().isNotEmpty) {
      return p.address!.split(',').first.trim();
    }
    if (p.zipCode != null && p.zipCode!.trim().isNotEmpty) {
      return 'ZIP ${p.zipCode}';
    }
    return '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}';
  }

  String? _distanceLabel(PhotoModel p) {
    final pos = _devicePosition;
    if (pos == null) return null;
    final m = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, p.latitude, p.longitude);
    final mi = m / 1609.34;
    if (mi < 0.1) return 'Nearby';
    if (mi < 10) return '${mi.toStringAsFixed(1)} miles away';
    return '${mi.round()} miles away';
  }

  List<PhotoModel> _filtered(List<PhotoModel> all) {
    final src = _selectedCategory == null
        ? all
        : all.where((p) => (p.category ?? 'standard') == _selectedCategory).toList();
    return List<PhotoModel>.from(src)
      // Newest upload first, so a freshly added post always lands at the top.
      // `id` is auto-increment (higher = uploaded later) and always present;
      // fall back to created_at, then capture timestamp. Grouped pins sort by
      // their most-recent photo. (Distance is still shown per card via the
      // "Nearby / N miles away" label — it's just no longer the sort key.)
      ..sort((a, b) {
        if (a.id != b.id) return b.id.compareTo(a.id);
        final ca = a.createdAt ?? '';
        final cb = b.createdAt ?? '';
        if (ca != cb) return cb.compareTo(ca);
        return (b.timestamp ?? '').compareTo(a.timestamp ?? '');
      });
  }

  String _firstName(String? email) {
    if (email == null || email.isEmpty) return 'Admin';
    final local = email.split('@').first;
    final name = local.replaceAll(RegExp(r'[._\-0-9]'), ' ').trim();
    if (name.isEmpty) return 'Admin';
    return name.split(' ').first._cap();
  }

  bool _isFav(PhotoModel p) =>
      p.isFavorited ^ _optimisticFlips.contains(p.id);

  void _toggleFav(PhotoModel p) {
    HapticFeedback.selectionClick();
    setState(() => _optimisticFlips.contains(p.id)
        ? _optimisticFlips.remove(p.id)
        : _optimisticFlips.add(p.id));
    ref.read(toggleFavoriteProvider(p.id).future).then((_) {
      if (mounted) setState(() => _optimisticFlips.remove(p.id));
    }).catchError((_) {
      if (mounted) setState(() => _optimisticFlips.remove(p.id));
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final photosAsync   = ref.watch(photosProvider);
    final profilesAsync = ref.watch(profilesProvider);
    final authState     = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _topBar(authState),
          Expanded(
            child: RefreshIndicator(
              color: _purple,
              backgroundColor: _card,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref.invalidate(photosProvider);
                ref.invalidate(profilesProvider);
                await _loadPosition();
              },
              child: photosAsync.when(
                loading: _skeleton,
                error: (_, __) => _errorView(),
                data: (photos) => profilesAsync.when(
                  loading: _skeleton,
                  error: (_, __) => _errorView(),
                  data: (profiles) => _feed(authState, photos, profiles),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _topBar(AuthState auth) {
    final name = _firstName(auth.email);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo
                const AppLogo(size: 40, radius: 12, withShadow: false),
                const SizedBox(width: 10),
                // Wordmark: violet "Geo" + purple "Tag"
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      height: 1,
                    ),
                    children: [
                      TextSpan(
                        text: 'Geo',
                        style: TextStyle(color: Color(0xFFA78BFA)), // violet
                      ),
                      TextSpan(
                        text: 'Tag',
                        style: TextStyle(color: Color(0xFF7C3AED)), // purple
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Notification bell
                _iconBtn(CupertinoIcons.bell,
                    badge: true, onTap: () => context.push('/log')),
                const SizedBox(width: 10),
                // Avatar
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/settings');
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                      border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                          width: 2),
                    ),
                    child: Center(
                      child: Text(
                        name.isEmpty ? 'A' : name[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon,
      {required VoidCallback onTap, bool badge = false}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          if (badge)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFF87171),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF312E81), width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Category filter bar ───────────────────────────────────────────────────
  // Leading "All" chip shows every job; the category chips filter to one
  // service. Either way the feed below stays sorted nearest-first.
  Widget _categoryBar() {
    return Container(
      color: _card,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      // All five chips share the row width so they are visible at once
      // (no horizontal scroll). Each chip's content auto-scales to fit.
      child: Row(
        children: [
          Expanded(
            child: _filterChip(
              label: 'ALL',
              icon: Icons.apps_rounded,
              color: const Color(0xFF312E81),
              softColor: const Color(0xFFEEF2FF),
              selected: _selectedCategory == null,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedCategory = null);
              },
            ),
          ),
          ...kPhotoCategories.map((cat) {
            final selected = _selectedCategory == cat.value;
            // Show "NEXT" instead of "Next Day" to keep chips compact
            final chipLabel =
                cat.value == 'next_day' ? 'NEXT' : cat.label.toUpperCase();
            return Expanded(
              child: _filterChip(
                label: chipLabel,
                icon: cat.icon,
                color: cat.color,
                softColor: cat.softColor,
                selected: selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() =>
                      _selectedCategory = selected ? null : cat.value);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required Color color,
    required Color softColor,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            height: 36,
            decoration: BoxDecoration(
              color: selected ? color : softColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                // Scale icon+label down to fit the (now narrower) chip so all
                // five chips stay on one line without overflowing.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 12, color: selected ? Colors.white : color),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.white : color,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // ── Full feed ─────────────────────────────────────────────────────────────
  Widget _feed(
      AuthState auth, List<PhotoModel> all, List<ProfileModel> profiles) {
    // Default to showing every job ("All") — no category is pre-selected, so
    // the feed opens with the full list sorted nearest-first.
    final posts = _filtered(all);
    // Collapse photos that share a master pin (same location group) into one
    // card so a profile/location with several photos shows ONE post with a
    // swipeable multi-photo preview — not a separate card per photo.
    final groups = _groupByPin(posts);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Category filter bar (sticky) ──────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyBarDelegate(child: _categoryBar()),
        ),
        // ── Posts ────────────────────────────────────────────────────────────
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyFeed(),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                if (i < groups.length) return _postCard(groups[i]);
                return const SizedBox(height: 100);
              },
              childCount: groups.length + 1,
            ),
          ),
      ],
    );
  }

  // Group photos that belong to the same pin so one card shows all of them.
  // Primary key is "same profile + same address" (matches how uploads are
  // grouped server-side and collapses older photos that predate that logic);
  // falls back to the master-pin/location-group id, then the photo id.
  List<List<PhotoModel>> _groupByPin(List<PhotoModel> posts) {
    final map = <String, List<PhotoModel>>{};
    for (final p in posts) {
      final addr = (p.address ?? '').trim().toLowerCase();
      final prof = (p.profileName ?? '').trim().toLowerCase();
      final key = addr.isNotEmpty
          ? 'pa:$prof|$addr'
          : 'lg:${p.locationGroupId ?? p.id}';
      (map[key] ??= <PhotoModel>[]).add(p);
    }
    return map.values.toList();
  }


  // ── Instagram-style post card ─────────────────────────────────────────────
  // [group] holds every photo sharing this master pin; the first is the
  // primary used for the header/caption, and all of them feed the carousel.
  Widget _postCard(List<PhotoModel> group) {
    final p = group.first;
    final fav = _isFav(p);
    final cat = categoryOf(p.category);
    final dist = _distanceLabel(p);

    return Container(
      color: _card,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Post header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cat.color, cat.color.withValues(alpha: 0.5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (p.profileName?.isNotEmpty ?? false)
                          ? p.profileName![0].toUpperCase()
                          : 'G',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Name + place
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.profileName ?? 'GeoTag',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _ink)),
                      Row(children: [
                        const Icon(Icons.location_on_rounded,
                            size: 11, color: _muted),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(_placeLabel(p),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: _muted)),
                        ),
                      ]),
                    ],
                  ),
                ),
                // Category badge
                PriorityChip(category: p.category),
                const SizedBox(width: 8),
                // More
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/photo/${p.id}');
                  },
                  child: const Icon(Icons.more_horiz, size: 20, color: _muted),
                ),
              ],
            ),
          ),

          // ── Full-width photo (swipeable when the pin has several) ───────
          // The watermark caption is drawn as a live overlay per image (see
          // captions), so EVERY post shows it — including older photos uploaded
          // before the stamp was baked in.
          _PhotoCarousel(
            images: [for (final g in group) _fullUrl(g.imageUrl)],
            captions: [
              for (final g in group)
                WatermarkCaption(
                  takenAtIso: g.takenAt ?? g.timestamp,
                  address: g.address ?? '',
                  zipCode: g.zipCode,
                  fileNumber: g.fileNumber,
                  profileName: g.profileName,
                  latitude: g.latitude,
                  longitude: g.longitude,
                  compact: true,
                ),
            ],
            onOpenIndex: (i) {
              HapticFeedback.selectionClick();
              context.push('/photo/${group[i].id}');
            },
            onDoubleTap: () => _toggleFav(p),
          ),

          // ── Action bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                // Favorite
                GestureDetector(
                  onTap: () => _toggleFav(p),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      fav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(fav),
                      size: 26,
                      color: fav ? const Color(0xFFEF4444) : _ink,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                // Map
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/map');
                  },
                  child: const Icon(Icons.map_outlined, size: 24, color: _ink),
                ),
                const SizedBox(width: 18),
                // Share / detail
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/photo/${p.id}');
                  },
                  child: const Icon(Icons.near_me_outlined,
                      size: 24, color: _ink),
                ),
                const Spacer(),
                // Save/bookmark
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/photo/${p.id}');
                  },
                  child: const Icon(Icons.bookmark_border_rounded,
                      size: 24, color: _ink),
                ),
              ],
            ),
          ),

          // ── Caption ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address line
                Row(children: [
                  const Icon(Icons.location_on_rounded,
                      size: 13, color: _muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(_placeLabel(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: _ink)),
                  ),
                  if (dist != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _purpleSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(dist,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _purple)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                // Date + relative time + payout
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_shortDate(p.timestamp)}'
                            '  ·  '
                            '${_relativeTime(p.timestamp)}',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                    if (p.payRate != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '\$${p.payRate}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF16A34A)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyFeed() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    color: _purpleSoft, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_outlined,
                    size: 34, color: _purple),
              ),
              const SizedBox(height: 18),
              const Text('No GeoTags yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink)),
              const SizedBox(height: 6),
              const Text(
                'Upload your first location photo\nto get started.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push('/upload'),
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: const Text('Upload GeoTag',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorView() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: _muted),
            SizedBox(height: 14),
            Text('Something went wrong',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
            SizedBox(height: 6),
            Text('Pull down to refresh.',
                style: TextStyle(fontSize: 13, color: _muted)),
          ]),
        ],
      );

  // ── Skeleton ──────────────────────────────────────────────────────────────
  Widget _skeleton() => Shimmer.fromColors(
        baseColor: const Color(0xFFE5E7EB),
        highlightColor: const Color(0xFFF9FAFB),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // category strip
            Container(
              color: Colors.white,
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                for (var i = 0; i < 5; i++) ...[
                  Expanded(child: _bone(double.infinity, 36, r: 20)),
                  if (i < 4) const SizedBox(width: 6),
                ]
              ]),
            ),
            // stories
            Container(
              color: Colors.white,
              height: 104,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                for (var i = 0; i < 5; i++) ...[
                  Column(children: [
                    _bone(60, 60, r: 30),
                    const SizedBox(height: 5),
                    _bone(50, 10, r: 4),
                  ]),
                  if (i < 4) const SizedBox(width: 16),
                ]
              ]),
            ),
            const SizedBox(height: 8),
            // post skeletons
            for (var j = 0; j < 2; j++) ...[
              Container(
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Row(children: [
                      _bone(40, 40, r: 20),
                      const SizedBox(width: 10),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _bone(120, 13, r: 4),
                            const SizedBox(height: 5),
                            _bone(80, 11, r: 4),
                          ]),
                    ]),
                  ),
                  _bone(double.infinity, 280, r: 0),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _bone(double.infinity, 14, r: 4),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _bone(160, 12, r: 4),
                  ),
                  const SizedBox(height: 14),
                ]),
              ),
            ],
          ],
        ),
      );

  Widget _bone(double w, double h, {double r = 8}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(r)),
      );
}

class _StickyBarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyBarDelegate({required this.child});
  final Widget child;

  // Category bar: 8px top padding + 36px chip + 10px bottom padding = 54px
  static const double _h = 54;

  @override double get minExtent => _h;
  @override double get maxExtent => _h;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(_StickyBarDelegate old) => old.child != child;
}

extension _S on String {
  String _cap() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
}

/// Swipeable 4:3 photo preview for a post. When a pin has multiple photos it
/// shows a page count badge and dot indicators; with a single photo it's just
/// the image. Tapping opens the currently-visible photo's detail.
class _PhotoCarousel extends StatefulWidget {
  const _PhotoCarousel({
    required this.images,
    required this.onOpenIndex,
    required this.onDoubleTap,
    this.captions = const [],
  });

  final List<String> images;
  /// Watermark overlay per image (parallel to [images]); may be empty.
  final List<Widget> captions;
  final void Function(int index) onOpenIndex;
  final VoidCallback onDoubleTap;

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  final _controller = PageController();
  int _index = 0;

  static const Color _muted = Color(0xFF6B7280);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.images.length;
    return GestureDetector(
      onTap: () => widget.onOpenIndex(_index),
      onDoubleTap: widget.onDoubleTap,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: n,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.images[i],
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFFF3F4F6),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _muted),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFF3F4F6),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library_outlined,
                                color: _muted, size: 32),
                            const SizedBox(height: 8),
                            Text('No image',
                                style: TextStyle(
                                    color: _muted.withValues(alpha: 0.6),
                                    fontSize: 12)),
                          ]),
                    ),
                  ),
                  // Watermark caption overlay for this image.
                  if (i < widget.captions.length) widget.captions[i],
                ],
              ),
            ),
            // Count badge (top-right) — only when there's more than one photo.
            if (n > 1)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.collections_rounded,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text('${_index + 1}/$n',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
            // Dot indicators (bottom-center).
            if (n > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < n; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(3),
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
