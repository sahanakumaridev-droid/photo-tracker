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
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/common/app_logo.dart';

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
  static const Color _hair       = Color(0xFFE5E7EB);


  String? _selectedCategory;
  final Set<int> _optimisticFlips = {};
  Position? _devicePosition;

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
    final list = all.where((p) {
      if (_selectedCategory != null &&
          categoryOf(p.category).value != _selectedCategory) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final pos = _devicePosition;
        if (pos != null) {
          final da = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, a.latitude, a.longitude);
          final db = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, b.latitude, b.longitude);
          return da.compareTo(db);
        }
        return (b.timestamp ?? '').compareTo(a.timestamp ?? '');
      });
    return list;
  }

  int _countFor(List<PhotoModel> all, String? cat) {
    if (cat == null) return all.length;
    return all.where((p) => categoryOf(p.category).value == cat).length;
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
        color: _card,
        border: Border(bottom: BorderSide(color: _hair, width: 0.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const AppLogo(size: 38, radius: 11, withShadow: false),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                  ).createShader(b),
                  child: const Text('GeoTag',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.6)),
                ),
                const Spacer(),
                _iconBtn(Icons.notifications_none_rounded,
                    badge: true, onTap: () => context.push('/log')),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/settings');
                  },
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: _purple,
                    child: Text(
                      name.isEmpty ? 'A' : name[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
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
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
                color: _bg, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: _ink),
          ),
          if (badge)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                    color: Color(0xFFEF4444), shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  // ── Full feed ─────────────────────────────────────────────────────────────
  Widget _feed(
      AuthState auth, List<PhotoModel> all, List<ProfileModel> profiles) {
    final posts = _filtered(all);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // ── Category chips ──────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _categoryStrip(all),
        ),
        // ── Stories (profiles) ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _storiesRow(auth, profiles),
        ),
        const SliverToBoxAdapter(
          child: Divider(height: 1, color: _hair),
        ),
        // ── Posts ────────────────────────────────────────────────────────────
        if (posts.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyFeed(),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                if (i < posts.length) return _postCard(posts[i]);
                return const SizedBox(height: 100);
              },
              childCount: posts.length + 1,
            ),
          ),
      ],
    );
  }

  // ── Category strip ────────────────────────────────────────────────────────
  Widget _categoryStrip(List<PhotoModel> all) {
    final chips = <({String? value, String label, Color color, Color soft, IconData icon})>[
      (value: null,       label: 'All',      color: _ink,             soft: const Color(0xFFF3F4F6), icon: Icons.apps_rounded),
      (value: 'asap',     label: 'ASAP',     color: const Color(0xFFEF4444), soft: const Color(0xFFFEE2E2), icon: Icons.bolt_rounded),
      (value: 'special',  label: 'Special',  color: const Color(0xFFF97316), soft: const Color(0xFFFFEDD5), icon: Icons.star_rounded),
      (value: 'standard', label: 'Standard', color: const Color(0xFF10B981), soft: const Color(0xFFD1FAE5), icon: Icons.check_circle_rounded),
      (value: 'next_day', label: 'Next Day', color: const Color(0xFFEAB308), soft: const Color(0xFFFEF9C3), icon: Icons.event_rounded),
    ];

    return Container(
      color: _card,
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: chips.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final c = chips[i];
            final sel = _selectedCategory == c.value;
            final n = _countFor(all, c.value);
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedCategory = c.value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? c.color : c.soft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.icon,
                        size: 14,
                        color: sel ? Colors.white : c.color),
                    const SizedBox(width: 5),
                    Text(c.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : c.color)),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: sel
                            ? Colors.white.withValues(alpha: 0.3)
                            : c.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$n',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: sel ? Colors.white : c.color)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Stories row ───────────────────────────────────────────────────────────
  Widget _storiesRow(AuthState auth, List<ProfileModel> profiles) {
    final name = _firstName(auth.email);
    return Container(
      color: _card,
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: profiles.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, i) {
          if (i == 0) {
            // "Your story" — upload new
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.push('/upload');
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: _purpleSoft,
                        child: Text(
                          name.isEmpty ? 'A' : name[0].toUpperCase(),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _purple),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: _purple,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Your story',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _ink)),
                ],
              ),
            );
          }
          final p = profiles[i - 1];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/settings');
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFF97316)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _card,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: _purpleSoft,
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _purple),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 62,
                  child: Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _ink)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Instagram-style post card ─────────────────────────────────────────────
  Widget _postCard(PhotoModel p) {
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: cat.softColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(cat.icon, size: 11, color: cat.color),
                    const SizedBox(width: 4),
                    Text(cat.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cat.color)),
                  ]),
                ),
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

          // ── Full-width photo ──────────────────────────────────────────
          GestureDetector(
            onDoubleTap: () => _toggleFav(p),
            onTap: () {
              HapticFeedback.selectionClick();
              context.push('/photo/${p.id}');
            },
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                _fullUrl(p.imageUrl),
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null
                    ? child
                    : Container(
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
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF3F4F6),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.image_not_supported_outlined,
                            color: _muted, size: 32),
                        const SizedBox(height: 8),
                        Text('No image',
                            style: TextStyle(
                                color: _muted.withValues(alpha: 0.6),
                                fontSize: 12)),
                      ]),
                ),
              ),
            ),
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
                        borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(8),
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
                child: const Icon(Icons.photo_camera_outlined,
                    size: 34, color: _purple),
              ),
              const SizedBox(height: 18),
              const Text('No GeoTags yet',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _ink)),
              const SizedBox(height: 6),
              Text(
                _selectedCategory != null
                    ? 'No ${categoryOf(_selectedCategory).label} photos found.\nTry a different category.'
                    : 'Upload your first location photo\nto get started.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: _muted, height: 1.5),
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
            Icon(Icons.cloud_off_rounded, size: 48, color: _muted),
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
                  _bone(i == 0 ? 56 : 90, 36, r: 20),
                  if (i < 4) const SizedBox(width: 8),
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

extension _S on String {
  String _cap() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
}
