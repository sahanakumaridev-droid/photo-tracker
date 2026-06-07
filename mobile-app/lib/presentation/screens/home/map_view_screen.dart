import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/location_service.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import 'map_pin_popup_sheet.dart';
import 'map_upload_sheet.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
const _kCanvas   = Color(0xFFFAFAFA);
const _kSurface  = Color(0xFFFFFFFF);
const _kInk      = Color(0xFF0F0F0F);
const _kInkMuted = Color(0xFF6B7280);
const _kSubtle   = Color(0xFF9CA3AF);
const _kSep      = Color(0xFFE5E7EB);
const _kAccent   = Color(0xFF7C3AED);

// ── Helpers ──────────────────────────────────────────────────────────────────
Color _svcColor(String? t) {
  switch ((t ?? '').toLowerCase()) {
    case 'rush':    return const Color(0xFFEF4444);
    case 'airport': return const Color(0xFF0EA5E9);
    default:        return const Color(0xFF10B981);
  }
}

/// Group photos that share the same lat/lng (rounded to 5 dp).
Map<String, List<PhotoModel>> _groupByLocation(List<PhotoModel> photos) {
  final map = <String, List<PhotoModel>>{};
  for (final ph in photos) {
    final key =
        '${ph.latitude.toStringAsFixed(5)}_${ph.longitude.toStringAsFixed(5)}';
    map.putIfAbsent(key, () => []).add(ph);
  }
  return map;
}

// ── Screen ───────────────────────────────────────────────────────────────────
class MapViewScreen extends ConsumerStatefulWidget {
  const MapViewScreen({super.key});

  @override
  ConsumerState<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends ConsumerState<MapViewScreen> {
  late final MapController _mapController;
  String _selectedProfile = 'all';
  final _searchCtrl = TextEditingController();
  Position? _userPosition;
  bool _fetchingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _fetchUserLocation();
  }

  Future<void> _fetchUserLocation() async {
    if (_fetchingLocation) return;
    setState(() => _fetchingLocation = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null && mounted) {
        setState(() => _userPosition = pos);
        // Centre map on user when first loaded
        _mapController.move(
          LatLng(pos.latitude, pos.longitude), 14,
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(photosProvider);
    ref.invalidate(profilesProvider);
    _fetchUserLocation();
  }

  void _fitAll(List<PhotoModel> photos) {
    if (photos.isEmpty) return;
    var minLat = photos.first.latitude;
    var maxLat = photos.first.latitude;
    var minLng = photos.first.longitude;
    var maxLng = photos.first.longitude;
    for (final p in photos) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(80),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync   = ref.watch(photosProvider);
    final profilesAsync = ref.watch(profilesProvider);

    return Scaffold(
      backgroundColor: _kCanvas,
      appBar: AppBar(
        backgroundColor: _kSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: _kSep)),
        title: const Text(
          'Explore Map',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _kInk,
            letterSpacing: -0.3,
          ),
        ),
        actions: const [],
      ),
      body: photosAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
        ),
        error: (e, _) => _ErrorView(error: e, onRetry: _refresh),
        data: (photos) => profilesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
          ),
          error: (e, _) => _ErrorView(error: e, onRetry: _refresh),
          data: (profiles) => _MapBody(
            photos: photos,
            profiles: profiles,
            selectedProfile: _selectedProfile,
            searchCtrl: _searchCtrl,
            mapController: _mapController,
            userPosition: _userPosition,
            onProfileChanged: (v) => setState(() => _selectedProfile = v),
            onFitAll: _fitAll,
            onRefresh: _refresh,
            onMyLocation: _fetchUserLocation,
          ),
        ),
      ),
    );
  }
}

// ── Map body (stateful so it can handle map taps) ────────────────────────────
class _MapBody extends ConsumerStatefulWidget {
  const _MapBody({
    required this.photos,
    required this.profiles,
    required this.selectedProfile,
    required this.searchCtrl,
    required this.mapController,
    required this.onProfileChanged,
    required this.onFitAll,
    required this.onRefresh,
    required this.onMyLocation,
    this.userPosition,
  });

  final List<PhotoModel>    photos;
  final List<ProfileModel>  profiles;
  final String              selectedProfile;
  final TextEditingController searchCtrl;
  final MapController       mapController;
  final ValueChanged<String> onProfileChanged;
  final ValueChanged<List<PhotoModel>> onFitAll;
  final VoidCallback        onRefresh;
  final VoidCallback        onMyLocation;
  final Position?           userPosition;

  @override
  ConsumerState<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends ConsumerState<_MapBody> {
  // F2 — selected service levels (empty = show all).
  final Set<String> _levels = {};

  @override
  Widget build(BuildContext context) {
    // Filter by selected profile
    var filtered = widget.selectedProfile == 'all'
        ? widget.photos
        : widget.photos.where((p) {
            final pid = widget.selectedProfile;
            return p.profileId?.toString() == pid ||
                (p.profiles?.any((pr) => pr.id.toString() == pid) ?? false);
          }).toList();

    // F2 — filter by selected service levels (category)
    if (_levels.isNotEmpty) {
      filtered = filtered
          .where((p) => _levels.contains(p.category ?? 'standard'))
          .toList();
    }

    // Only geotagged
    final geotagged = filtered.where((p) => p.latitude != 0 || p.longitude != 0).toList();

    // Group by location
    final groups = _groupByLocation(geotagged);

    const mapCenter = LatLng(32.7157, -117.1611);

    return Stack(
      children: [
        // ── Map ──────────────────────────────────────────────────────────
        FlutterMap(
          mapController: widget.mapController,
          options: MapOptions(
            initialCenter: mapCenter,
            initialZoom: 13,
            minZoom: 2,
            maxZoom: 18,
            // Tap on empty map → upload sheet
            onTap: (tapPos, latLng) {
              HapticFeedback.lightImpact();
              showMapUploadSheet(
                context,
                lat: latLng.latitude,
                lng: latLng.longitude,
                onUploaded: widget.onRefresh,
              );
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.photo_tracker',
            ),
            MarkerLayer(
              markers: groups.entries.map((entry) {
                final groupPhotos = entry.value;
                // Sort newest first
                final sorted = [...groupPhotos]
                  ..sort((a, b) =>
                      (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
                final latest   = sorted.first;
                final hasRush  = sorted.any((p) => p.serviceType == 'rush');
                final color    = _svcColor(hasRush ? 'rush' : latest.serviceType);
                final count    = sorted.length;

                return Marker(
                  point: LatLng(latest.latitude, latest.longitude),
                  width: count > 1 ? 58 : 50,
                  height: count > 1 ? 68 : 60,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      showPinPopupSheet(
                        context,
                        photos: sorted,
                        lat: latest.latitude,
                        lng: latest.longitude,
                        onUpdated: widget.onRefresh,
                      );
                    },
                    child: _PinMarker(
                      imageUrl: latest.imageUrl,
                      color: color,
                      count: count,
                    ),
                  ),
                );
              }).toList(),
            ),
            // ── Live user location marker ─────────────────────────────
            if (widget.userPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      widget.userPosition!.latitude,
                      widget.userPosition!.longitude,
                    ),
                    width: 56,
                    height: 56,
                    child: _UserLocationMarker(
                      accuracy: widget.userPosition!.accuracy,
                    ),
                  ),
                ],
              ),
          ],
        ),

        // ── Search + filter bar ───────────────────────────────────────────
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _SearchBar(
            controller: widget.searchCtrl,
            profiles: widget.profiles,
            selectedProfile: widget.selectedProfile,
            onProfileChanged: widget.onProfileChanged,
          ),
        ),

        // ── F2: service-level filter chips ────────────────────────────────
        Positioned(
          top: 62,
          left: 8,
          right: 8,
          child: SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                ['asap', 'ASAP'],
                ['next_day', 'Next Day'],
                ['standard', 'Standard'],
                ['special', 'Special'],
              ].map((lvl) {
                final sel = _levels.contains(lvl[0]);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(lvl[1], style: const TextStyle(fontSize: 12)),
                    selected: sel,
                    backgroundColor: Colors.white,
                    selectedColor: _kAccent,
                    labelStyle: TextStyle(
                        color: sel ? Colors.white : const Color(0xFF374151),
                        fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() {
                      sel ? _levels.remove(lvl[0]) : _levels.add(lvl[0]);
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // ── Tap-to-upload hint ────────────────────────────────────────────
        Positioned(
          top: 72,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_rounded, size: 12, color: Colors.white70),
                  SizedBox(width: 5),
                  Text(
                    'Tap map to upload · Tap pin to view',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Bottom info card ──────────────────────────────────────────────
        if (geotagged.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _BottomCard(
              count: geotagged.length,
              groupCount: groups.length,
              onFitAll: () => widget.onFitAll(geotagged),
              onViewList: () => context.push('/log'),
            ),
          ),

        // ── My Location FAB ───────────────────────────────────────────────
        Positioned(
          bottom: geotagged.isNotEmpty ? 140 : 24,
          right: 16,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onMyLocation();
              if (widget.userPosition != null) {
                widget.mapController.move(
                  LatLng(widget.userPosition!.latitude,
                      widget.userPosition!.longitude),
                  15,
                );
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _kSurface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                widget.userPosition != null
                    ? Icons.my_location_rounded
                    : Icons.location_searching_rounded,
                size: 22,
                color: widget.userPosition != null ? _kAccent : _kSubtle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pin marker widget ─────────────────────────────────────────────────────────
class _PinMarker extends StatelessWidget {
  const _PinMarker({
    required this.imageUrl,
    required this.color,
    required this.count,
  });
  final String imageUrl;
  final Color  color;
  final int    count;

  @override
  Widget build(BuildContext context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Photo circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: color.withOpacity(0.15),
                    child: Icon(
                      Icons.person_rounded,
                      color: color,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            // Count badge (top-right) — only when multiple photos
            if (count > 1)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Pin stem
        Container(width: 2, height: 6, color: color),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
            ],
          ),
        ),
      ],
    );
}

// ── Search bar ────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.profiles,
    required this.selectedProfile,
    required this.onProfileChanged,
  });
  final TextEditingController controller;
  final List<ProfileModel>    profiles;
  final String                selectedProfile;
  final ValueChanged<String>  onProfileChanged;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSep, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.search_rounded, color: _kSubtle, size: 18),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Search profiles…',
                hintStyle: TextStyle(color: _kSubtle, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
              ),
            ),
          ),
          // Filter popup
          PopupMenuButton<String>(
            onSelected: onProfileChanged,
            color: _kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.apps_rounded, size: 16, color: _kInkMuted),
                    SizedBox(width: 8),
                    Text('All Profiles'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              ...profiles.map((p) => PopupMenuItem(
                    value: p.id.toString(),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _svcColor(p.serviceType),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(p.name),
                      ],
                    ),
                  )),
            ],
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selectedProfile != 'all'
                    ? _kAccent.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 20,
                color: selectedProfile != 'all' ? _kAccent : _kInkMuted,
              ),
            ),
          ),
        ],
      ),
    );
}

// ── Bottom info card ──────────────────────────────────────────────────────────
class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.count,
    required this.groupCount,
    required this.onFitAll,
    required this.onViewList,
  });
  final int          count;
  final int          groupCount;
  final VoidCallback onFitAll;
  final VoidCallback onViewList;

  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kSep, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 16,
                  color: _kAccent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Geotagged Photos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                      ),
                    ),
                    Text(
                      '$count photo${count != 1 ? 's' : ''} · $groupCount pin${groupCount != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _kSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _cardBtn(
                  icon: Icons.zoom_out_map_rounded,
                  label: 'Fit All',
                  onTap: onFitAll,
                  filled: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _cardBtn(
                  icon: Icons.list_rounded,
                  label: 'View List',
                  onTap: onViewList,
                  filled: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );

  Widget _cardBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: filled ? _kAccent : _kAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: filled
                ? null
                : Border.all(color: _kAccent.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: filled ? Colors.white : _kAccent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : _kAccent,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── User location marker ──────────────────────────────────────────────────────
class _UserLocationMarker extends StatefulWidget {
  const _UserLocationMarker({required this.accuracy});
  final double accuracy;

  @override
  State<_UserLocationMarker> createState() => _UserLocationMarkerState();
}

class _UserLocationMarkerState extends State<_UserLocationMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            // Accuracy ring
            Container(
              width: 48 + _pulse.value * 8,
              height: 48 + _pulse.value * 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kAccent.withValues(alpha: 0.12 - _pulse.value * 0.08),
                border: Border.all(
                  color: _kAccent.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            // Blue dot
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kAccent,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: _kAccent.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── Error view ────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object    error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load map data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _kInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString().replaceAll('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _kSubtle),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
