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

/// GeoTag — consumer home. Photos & places are the hero: capture, recent
/// uploads gallery, nearby discovery and a light activity feed. Apple-style
/// white space, soft shadows, blue accent (#2563EB), no gradients.
class HomeScreenV2 extends ConsumerStatefulWidget {
  const HomeScreenV2({super.key});

  @override
  ConsumerState<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends ConsumerState<HomeScreenV2> {
  // ── Palette ────────────────────────────────────────────────────────────────
  static const Color _ink    = Color(0xFF0F0F0F); // text / black buttons
  static const Color _muted  = Color(0xFF6B7280); // secondary text
  static const Color _purple = Color(0xFF7C3AED); // purple accent
  static const Color _purpleSoft = Color(0xFFEDE9FE);
  static const Color _green  = Color(0xFF10B981); // success / verified
  static const Color _bg     = Color(0xFFFAFAFA); // background
  static const Color _card   = Color(0xFFFFFFFF); // cards
  static const Color _hair   = Color(0xFFE5E7EB); // hairline

  static const List<BoxShadow> _softShadow = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, 6)),
  ];

  String? _selectedCategory; // null = All
  final Set<int> _favorites = {};
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
    } catch (_) {/* nearby simply shows without distance */}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _fullUrl(String url) =>
      url.startsWith('http') ? url : '${AppConfig.apiBaseUrl}$url';

  String _shortDate(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('MMM d').format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return '';
    }
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
    } catch (_) {
      return '';
    }
  }

  int _thisMonthCount(List<PhotoModel> photos) {
    final now = DateTime.now();
    return photos.where((p) {
      if (p.timestamp == null) return false;
      try {
        final d = DateTime.parse(p.timestamp!);
        return d.year == now.year && d.month == now.month;
      } catch (_) {
        return false;
      }
    }).length;
  }

  int _locationCount(List<PhotoModel> photos) {
    final keys = <String>{};
    for (final p in photos) {
      keys.add((p.address?.trim().isNotEmpty ?? false)
          ? p.address!.trim().toLowerCase()
          : (p.zipCode?.trim().isNotEmpty ?? false)
              ? 'zip:${p.zipCode}'
              : '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}');
    }
    return keys.length;
  }

  String _placeLabel(PhotoModel p) {
    if (p.address != null && p.address!.trim().isNotEmpty) {
      return p.address!.split(',').first.trim();
    }
    if (p.zipCode != null && p.zipCode!.trim().isNotEmpty) return 'ZIP ${p.zipCode}';
    return '${p.latitude.toStringAsFixed(3)}, ${p.longitude.toStringAsFixed(3)}';
  }

  String? _distanceLabel(PhotoModel p) {
    final pos = _devicePosition;
    if (pos == null) return null;
    final meters = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, p.latitude, p.longitude);
    final miles = meters / 1609.34;
    if (miles < 0.1) return 'Nearby';
    if (miles < 10) return '${miles.toStringAsFixed(1)} mi';
    return '${miles.round()} mi';
  }

  List<PhotoModel> _filtered(List<PhotoModel> photos) {
    final list = photos.where((p) {
      if (_selectedCategory != null &&
          categoryOf(p.category).value != _selectedCategory) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return list;
  }

  String _firstName(String? email) {
    if (email == null || email.isEmpty) return 'Admin';
    final local = email.split('@').first;
    final name = local.replaceAll(RegExp(r'[._\-0-9]'), ' ').trim();
    if (name.isEmpty) return 'Admin';
    return name.split(' ').first.capitalize();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _toggleFav(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_favorites.add(id)) _favorites.remove(id);
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(photosProvider);
    final profilesAsync = ref.watch(profilesProvider);
    final authState = ref.watch(authProvider);

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
                error: (e, _) => _error(),
                data: (photos) => profilesAsync.when(
                  loading: _skeleton,
                  error: (e, _) => _error(),
                  data: (profiles) =>
                      _content(authState, photos, profiles),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 1 · Top bar ──────────────────────────────────────────────────────
  Widget _topBar(AuthState auth) {
    final name = _firstName(auth.email);
    return Container(
      decoration: const BoxDecoration(
        color: _card,
        border: Border(bottom: BorderSide(color: _hair)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: AppLogo(size: 40, radius: 11),
                ),
              ),
              const Text('GeoTag',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.3)),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _circleIcon(Icons.notifications_none_rounded,
                        onTap: () => context.push('/log')),
                    const SizedBox(width: 8),
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
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, {required VoidCallback onTap}) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(color: _bg, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: _ink),
        ),
      );

  // ── Content ───────────────────────────────────────────────────────────────
  Widget _content(
      AuthState auth, List<PhotoModel> photos, List<ProfileModel> profiles) {
    final filtered = _filtered(photos);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const SizedBox(height: 20),
        _welcome(auth),
        const SizedBox(height: 20),
        _captureCard(),
        const SizedBox(height: 24),
        _quickStats(photos, profiles),
        const SizedBox(height: 28),
        _recentUploads(filtered),
        const SizedBox(height: 28),
        _categoryChips(photos),
        const SizedBox(height: 24),
        _nearby(filtered),
        const SizedBox(height: 28),
        _activity(photos),
      ],
    );
  }

  // ── Section 2 · Welcome ──────────────────────────────────────────────────────
  Widget _welcome(AuthState auth) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_greeting()}, ${_firstName(auth.email)}',
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.8,
                    height: 1.1)),
            const SizedBox(height: 6),
            const Text('Discover and capture places around you',
                style: TextStyle(fontSize: 15, color: _muted, height: 1.3)),
          ],
        ),
      );

  // ── Section 3 · Capture card ─────────────────────────────────────────────────
  Widget _captureCard() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: _softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Capture New GeoTag',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Save a location with photos & coordinates.',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: _muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: const Color(0xFF0F0F0F),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push('/upload');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 13),
                    child: const Text(
                      'Capture',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // ── Section 4 · Quick stats ──────────────────────────────────────────────────
  Widget _quickStats(List<PhotoModel> photos, List<ProfileModel> profiles) {
    final stats = [
      (icon: Icons.photo_camera_rounded, value: '${photos.length}', label: 'Photos', tint: _purple),
      (icon: Icons.place_rounded, value: '${_locationCount(photos)}', label: 'Locations', tint: _green),
      (icon: Icons.favorite_rounded, value: '${_favorites.length}', label: 'Favorites', tint: const Color(0xFFEF4444)),
      (icon: Icons.calendar_today_rounded, value: '${_thisMonthCount(photos)}', label: 'This Month', tint: const Color(0xFFF59E0B)),
    ];
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final s = stats[i];
          return Container(
            width: 112,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: _softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(s.icon, size: 20, color: s.tint),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.value,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.5,
                            height: 1)),
                    const SizedBox(height: 2),
                    Text(s.label,
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Section 5 · Recent uploads (hero) ─────────────────────────────────────────
  Widget _recentUploads(List<PhotoModel> photos) {
    final recent = photos.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Recent Uploads',
            action: 'See all', onAction: () => context.push('/log')),
        const SizedBox(height: 14),
        if (recent.isEmpty)
          _inlineEmpty('No uploads yet', 'Capture your first GeoTag.')
        else
          SizedBox(
            height: 268,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: recent.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => _uploadCard(recent[i]),
            ),
          ),
      ],
    );
  }

  Widget _uploadCard(PhotoModel p) {
    final fav = _favorites.contains(p.id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/photo/${p.id}');
      },
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.network(
                    _fullUrl(p.imageUrl),
                    width: 240,
                    height: 160,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, prog) => prog == null
                        ? child
                        : Container(width: 240, height: 160, color: _bg),
                    errorBuilder: (_, __, ___) => Container(
                      width: 240,
                      height: 160,
                      color: _bg,
                      child: const Icon(Icons.image_outlined,
                          color: _muted, size: 28),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: () => _toggleFav(p.id),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        boxShadow: _softShadow,
                      ),
                      child: Icon(
                          fav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                          color: fav ? const Color(0xFFEF4444) : _ink),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: _verifiedBadge(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.profileName ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.location_on_rounded,
                        size: 13, color: _muted),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(_placeLabel(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: _muted)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(_shortDate(p.timestamp),
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: _muted,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    _miniCategoryDot(categoryOf(p.category)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verifiedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: _softShadow,
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_rounded, size: 13, color: _green),
          SizedBox(width: 4),
          Text('Verified',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: _green)),
        ]),
      );

  Widget _miniCategoryDot(PhotoCategory c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(c.label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: c.color)),
        ],
      );

  // ── Section 6 · Category chips ───────────────────────────────────────────────
  Widget _categoryChips(List<PhotoModel> photos) {
    final chips = <({String? value, String label})>[
      (value: null, label: 'All'),
      (value: 'asap', label: 'ASAP'),
      (value: 'special', label: 'Special'),
      (value: 'standard', label: 'Standard'),
      (value: 'next_day', label: 'Next Day'),
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final chip = chips[i];
          final selected = _selectedCategory == chip.value;
          final cat = chip.value != null ? categoryOf(chip.value) : null;
          final activeColor = cat?.color ?? _ink;
          final softColor = cat?.softColor ?? _bg;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedCategory = chip.value);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: chip.value == null ? 64 : 108,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? activeColor
                    : (chip.value != null ? softColor : _card),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? activeColor : _hair,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cat != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Icon(cat.icon,
                          size: 16,
                          color: selected ? Colors.white : activeColor),
                    ),
                  Text(
                    chip.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : _muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Section 7 · Nearby ─────────────────────────────────────────────────────────
  Widget _nearby(List<PhotoModel> photos) {
    var list = List<PhotoModel>.from(photos);
    if (_devicePosition != null) {
      list.sort((a, b) {
        final da = Geolocator.distanceBetween(_devicePosition!.latitude,
            _devicePosition!.longitude, a.latitude, a.longitude);
        final db = Geolocator.distanceBetween(_devicePosition!.latitude,
            _devicePosition!.longitude, b.latitude, b.longitude);
        return da.compareTo(db);
      });
    }
    list = list.take(8).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Nearby Locations',
            action: 'Map', onAction: () => context.push('/map')),
        const SizedBox(height: 14),
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => _nearbyCard(list[i]),
          ),
        ),
      ],
    );
  }

  Widget _nearbyCard(PhotoModel p) {
    final dist = _distanceLabel(p);
    final cat = categoryOf(p.category);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push('/photo/${p.id}');
      },
      child: Container(
        width: 168,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: Image.network(
                _fullUrl(p.imageUrl),
                width: 168,
                height: 104,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null
                    ? child
                    : Container(width: 168, height: 104, color: _bg),
                errorBuilder: (_, __, ___) => Container(
                  width: 168,
                  height: 104,
                  color: _bg,
                  child: const Icon(Icons.image_outlined,
                      color: _muted, size: 24),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_placeLabel(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          letterSpacing: -0.2)),
                  const SizedBox(height: 5),
                  Row(children: [
                    if (dist != null) ...[
                      const Icon(Icons.near_me_rounded,
                          size: 12, color: _purple),
                      const SizedBox(width: 3),
                      Text(dist,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _purple)),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: _miniCategoryDot(cat)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section 8 · Activity ──────────────────────────────────────────────────────
  Widget _activity(List<PhotoModel> photos) {
    final recent = (List<PhotoModel>.from(photos)
          ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? '')))
        .take(4)
        .toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Recent Activity',
            action: 'See all', onAction: () => context.push('/log')),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _softShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++)
                  _activityRow(recent[i], last: i == recent.length - 1),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _activityRow(PhotoModel p, {required bool last}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          context.push('/photo/${p.id}');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.cloud_upload_rounded,
                  size: 18, color: _purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Uploaded ${p.profileName ?? 'a GeoTag'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink)),
                  const SizedBox(height: 2),
                  Text(_placeLabel(p),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_relativeTime(p.timestamp),
                style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
            if (!last) ...[
              const SizedBox(height: 6),
              const Divider(height: 1, color: _hair),
            ],
          ]),
        ),
      );

  // ── Shared bits ────────────────────────────────────────────────────────────
  Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.5)),
          const Spacer(),
          if (action != null)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onAction?.call();
              },
              child: Text(action,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _purple)),
            ),
        ]),
      );

  Widget _inlineEmpty(String title, String subtitle) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: _softShadow,
          ),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: _bg, shape: BoxShape.circle),
              child: const Icon(Icons.photo_camera_outlined,
                  color: _muted, size: 24),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 4),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: _muted)),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => context.push('/upload'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Capture Now'),
            ),
          ]),
        ),
      );

  Widget _error() => ListView(
        padding: const EdgeInsets.fromLTRB(24, 100, 24, 24),
        children: const [
          Column(children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: _muted),
            SizedBox(height: 14),
            Text('Something went wrong',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
            SizedBox(height: 6),
            Text('Pull down to refresh and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _muted)),
          ]),
        ],
      );

  // ── Skeleton ────────────────────────────────────────────────────────────────
  Widget _skeleton() => Shimmer.fromColors(
        baseColor: const Color(0xFFE9EEF5),
        highlightColor: const Color(0xFFF8FAFC),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _box(180, 30, radius: 8),
            const SizedBox(height: 20),
            _box(double.infinity, 150, radius: 20),
            const SizedBox(height: 24),
            SizedBox(
              height: 96,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    _box(112, 96, radius: 16),
                    const SizedBox(width: 12),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 28),
            _box(160, 24, radius: 8),
            const SizedBox(height: 14),
            SizedBox(
              height: 268,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  _box(240, 268, radius: 20),
                  const SizedBox(width: 14),
                  _box(240, 268, radius: 20),
                ]),
              ),
            ),
          ],
        ),
      );

  Widget _box(double w, double h, {double radius = 12}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

extension _StringExt on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
}
