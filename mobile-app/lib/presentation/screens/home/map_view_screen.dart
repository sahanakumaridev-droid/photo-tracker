import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/storage/upload_queue.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import 'map_pin_popup_sheet.dart';
import 'map_upload_sheet.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kSurface  = Color(0xFFFFFFFF);
const _kInk      = Color(0xFF0F0F0F);
const _kInkMuted = Color(0xFF6B7280);
const _kSubtle   = Color(0xFF9CA3AF);
const _kSep      = Color(0xFFE5E7EB);
const _kAccent   = Color(0xFF7C3AED);

// Category palette
const _kAsap     = Color(0xFFEF4444);
const _kNextDay  = Color(0xFFF59E0B);
const _kStd      = Color(0xFF10B981);
const _kSpecial  = Color(0xFF8B5CF6);

// ── Static category definitions ───────────────────────────────────────────────
const List<List<String>> _kCats = [
  ['asap',     'ASAP'],
  ['next_day', 'Next Day'],
  ['standard', 'Standard'],
  ['special',  'Special'],
];

// ── Helpers ───────────────────────────────────────────────────────────────────
Color _svcColor(String? t) {
  switch ((t ?? '').toLowerCase()) {
    case 'rush':    return const Color(0xFFEF4444);
    case 'airport': return const Color(0xFF0EA5E9);
    default:        return const Color(0xFF10B981);
  }
}

Color _catColor(String c) {
  switch (c) {
    case 'asap':     return _kAsap;
    case 'next_day': return _kNextDay;
    case 'special':  return _kSpecial;
    default:         return _kStd;
  }
}

IconData _catIcon(String c) {
  switch (c) {
    case 'asap':     return Icons.bolt_rounded;
    case 'next_day': return Icons.access_time_rounded;
    case 'special':  return Icons.star_rounded;
    default:         return Icons.check_circle_rounded;
  }
}

Map<String, List<PhotoModel>> _groupByLocation(List<PhotoModel> photos) {
  final map = <String, List<PhotoModel>>{};
  for (final p in photos) {
    final key =
        '${p.latitude.toStringAsFixed(5)}_${p.longitude.toStringAsFixed(5)}';
    map.putIfAbsent(key, () => []).add(p);
  }
  return map;
}

Map<String, int> _countByService(List<PhotoModel> photos) {
  final counts = <String, int>{};
  for (final p in photos) {
    final s = (p.serviceType ?? 'standard').toLowerCase();
    counts[s] = (counts[s] ?? 0) + 1;
  }
  return counts;
}

// ── Screen ────────────────────────────────────────────────────────────────────
class MapViewScreen extends ConsumerStatefulWidget {
  const MapViewScreen({super.key});

  @override
  ConsumerState<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends ConsumerState<MapViewScreen> {
  late final MapController _mapController;
  String   _selectedProfile   = 'all';
  bool     _fetchingLocation  = false;
  bool     _locationAttemptDone = false;
  Position? _userPosition;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    // Centring happens in [_onMapReady] (fired once the map can accept camera
    // moves): a cached last-known fix snaps the camera to the user instantly,
    // then the accurate fix refines it. This avoids moving the controller
    // before the map is mounted.
  }

  /// Fired by FlutterMap once it's ready to accept camera moves. Centre on the
  /// user as fast as possible, then refine.
  void _onMapReady() {
    _centerOnLastKnown(); // instant — from the OS location cache
    _fetchUserLocation(moveCamera: true); // accurate — refines when it lands
  }

  /// Snap the camera to the last-known location immediately so the map opens
  /// on the user instead of a default city while the accurate fix is computed.
  Future<void> _centerOnLastKnown() async {
    final last = await LocationService.getLastKnownLocation();
    // Don't fight a fresh accurate fix if it already arrived first.
    if (last != null && mounted && _userPosition == null) {
      _mapController.move(LatLng(last.latitude, last.longitude), 14);
    }
  }

  Future<void> _fetchUserLocation({bool moveCamera = false}) async {
    if (_fetchingLocation) return;
    setState(() => _fetchingLocation = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null && mounted) {
        setState(() => _userPosition = pos);
        // Only recentre on the user when explicitly asked (e.g. the FAB).
        // On first load we want the camera to frame the pins, not jump to
        // the device location, which otherwise leaves all pins off-screen.
        if (moveCamera) {
          _mapController.move(LatLng(pos.latitude, pos.longitude), 14);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _fetchingLocation = false;
          _locationAttemptDone = true;
        });
      }
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
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // All pins at (nearly) the same spot → bounds have ~zero area and
    // fitCamera would slam to maxZoom. Just centre on it at a sane zoom.
    if ((maxLat - minLat).abs() < 1e-4 && (maxLng - minLng).abs() < 1e-4) {
      _mapController.move(LatLng(minLat, minLng), 14);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(80),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: the map must open INSTANTLY, centred on the user — never gate it
    // behind the jobs network call, which can stall on poor field signal and
    // leave the user staring at a blank spinner. Render the map with whatever
    // data we already have; pins and the profile selector fill in on their own
    // as the requests complete. The primary action (tap the map to log a new
    // attempt) works the moment the map is up — no waiting on existing pins.
    final photos   = ref.watch(photosProvider).valueOrNull ?? const <PhotoModel>[];
    final profiles =
        ref.watch(profilesProvider).valueOrNull ?? const <ProfileModel>[];

    return Scaffold(
      // Full-screen map — no AppBar, body extends to top
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF0F0F0),
      body: _MapBody(
        photos: photos,
        profiles: profiles,
        selectedProfile: _selectedProfile,
        searchCtrl: _searchCtrl,
        mapController: _mapController,
        userPosition: _userPosition,
        fetchingLocation: _fetchingLocation,
        locationAttemptDone: _locationAttemptDone,
        onMapReady: _onMapReady,
        onProfileChanged: (v) => setState(() => _selectedProfile = v),
        onFitAll: _fitAll,
        onRefresh: _refresh,
        onMyLocation: () => _fetchUserLocation(moveCamera: true),
      ),
    );
  }
}

// ── Map body ──────────────────────────────────────────────────────────────────
class _MapBody extends ConsumerStatefulWidget {
  const _MapBody({
    required this.photos,
    required this.profiles,
    required this.selectedProfile,
    required this.searchCtrl,
    required this.mapController,
    required this.onMapReady,
    required this.onProfileChanged,
    required this.onFitAll,
    required this.onRefresh,
    required this.onMyLocation,
    this.userPosition,
    this.fetchingLocation = false,
    this.locationAttemptDone = false,
  });

  final List<PhotoModel>               photos;
  final List<ProfileModel>             profiles;
  final String                         selectedProfile;
  final TextEditingController          searchCtrl;
  final MapController                  mapController;
  final VoidCallback                   onMapReady;
  final ValueChanged<String>           onProfileChanged;
  final ValueChanged<List<PhotoModel>> onFitAll;
  final VoidCallback                   onRefresh;
  final VoidCallback                   onMyLocation;
  final Position?                      userPosition;
  final bool                           fetchingLocation;
  final bool                           locationAttemptDone;

  @override
  ConsumerState<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends ConsumerState<_MapBody> {
  final Set<String> _levels = {};
  bool _didInitialFit = false;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    // Apply profile filter
    var filtered = widget.selectedProfile == 'all'
        ? widget.photos
        : widget.photos.where((p) {
            final pid = widget.selectedProfile;
            return p.profileId?.toString() == pid ||
                (p.profiles?.any((pr) => pr.id.toString() == pid) ?? false);
          }).toList();

    // Apply category filter (F2)
    if (_levels.isNotEmpty) {
      filtered = filtered
          .where((p) => _levels.contains(p.category ?? 'standard'))
          .toList();
    }

    final geotagged = filtered
        .where((p) => p.latitude != 0 || p.longitude != 0)
        .toList();
    final groups    = _groupByLocation(geotagged);
    final svcCounts = _countByService(geotagged);
    final hasData   = geotagged.isNotEmpty;

    // The app opens centred on the user's live GPS (handled by the parent's
    // last-known + accurate fixes). Only fall back to framing the pins once the
    // location attempt has FINISHED with no fix — otherwise this would yank the
    // camera away from the user while the GPS fix is still being acquired.
    if (!_didInitialFit &&
        hasData &&
        widget.userPosition == null &&
        widget.locationAttemptDone) {
      _didInitialFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFitAll(geotagged);
      });
    }

    const mapCenter = LatLng(32.7157, -117.1611);

    return Stack(
      children: [
        // ── Full-screen map ────────────────────────────────────────────
        FlutterMap(
          mapController: widget.mapController,
          options: MapOptions(
            initialCenter: mapCenter,
            initialZoom: 13,
            minZoom: 2,
            maxZoom: 18,
            onMapReady: widget.onMapReady,
            onTap: (_, latLng) {
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
            // Photo pin markers
            MarkerLayer(
              markers: groups.entries.map((entry) {
                final sorted = [...entry.value]
                  ..sort((a, b) =>
                      (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
                final latest  = sorted.first;
                final hasRush = sorted.any((p) => p.serviceType == 'rush');
                final color   = _svcColor(hasRush ? 'rush' : latest.serviceType);
                final count   = sorted.length;

                return Marker(
                  point: LatLng(latest.latitude, latest.longitude),
                  width:  count > 1 ? 62 : 56,
                  height: 74,
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
            // Live user-location marker
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

        // ── Top floating control panel ─────────────────────────────────
        Positioned(
          top: topPad + 10,
          left: 14,
          right: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title + subtitle + refresh
              _FloatingHeader(
                onRefresh: widget.onRefresh,
                photoCount: geotagged.length,
                pinCount: groups.length,
              ),
              const SizedBox(height: 10),
              // Search bar
              _SearchBar(
                controller: widget.searchCtrl,
                profiles: widget.profiles,
                selectedProfile: widget.selectedProfile,
                onProfileChanged: widget.onProfileChanged,
              ),
              const SizedBox(height: 8),
              // Category chips (F2) — leading "All" chip, then the four levels.
              _CategoryChips(
                selected: _levels,
                onToggle: (cat) => setState(() {
                  _levels.contains(cat)
                      ? _levels.remove(cat)
                      : _levels.add(cat);
                }),
                onClearAll: () => setState(_levels.clear),
              ),
              const SizedBox(height: 8),
              // Contextual hint
              const _HintPill(),
              // Offline upload queue indicator (auto-retries in the background).
              const _PendingUploadsPill(),
            ],
          ),
        ),

        // ── Bottom stats card ──────────────────────────────────────────
        if (hasData)
          Positioned(
            bottom: 16,
            left: 14,
            right: 14,
            child: _BottomCard(
              count: geotagged.length,
              groupCount: groups.length,
              svcCounts: svcCounts,
              onFitAll: () => widget.onFitAll(geotagged),
              onViewList: () => context.push(
                _levels.length == 1
                    ? '/log?category=${_levels.first}'
                    : '/log',
              ),
            ),
          ),

        // ── My-location FAB (must be LAST in Stack for highest z-index) ─
        Positioned(
          right: 14,
          bottom: hasData ? 204 : 28,
          child: Material(
            color: Colors.transparent,
            child: _LocationFab(
              userPosition: widget.userPosition,
              loading: widget.fetchingLocation,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onMyLocation();
                if (widget.userPosition != null) {
                  widget.mapController.move(
                    LatLng(
                      widget.userPosition!.latitude,
                      widget.userPosition!.longitude,
                    ),
                    15,
                  );
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Floating header ───────────────────────────────────────────────────────────
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
                    text: 'Geo',
                    style: TextStyle(color: Color(0xFF7C3AED)), // purple
                  ),
                  TextSpan(
                    text: 'Tag',
                    style: TextStyle(color: Color(0xFF5B21B6)), // dark
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
            color: _kSurface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.refresh_rounded,
            size: 18,
            color: _kInkMuted,
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kAccent, Color(0xFF5445E6)],
            ),
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
    required this.profiles,
    required this.selectedProfile,
    required this.onProfileChanged,
  });
  final TextEditingController controller;
  final List<ProfileModel>    profiles;
  final String                selectedProfile;
  final ValueChanged<String>  onProfileChanged;

  @override
  Widget build(BuildContext context) {
    final filtered = selectedProfile != 'all';
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kSep, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
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
                hintText: 'Search profiles…',
                hintStyle: TextStyle(color: _kSubtle, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
                isDense: true,
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: onProfileChanged,
            color: _kSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(Icons.grid_view_rounded, size: 16, color: _kInkMuted),
                    SizedBox(width: 8),
                    Text(
                      'All Profiles',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: filtered
                    ? _kAccent.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 19,
                    color: filtered ? _kAccent : _kInkMuted,
                  ),
                  if (filtered) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: _kAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          '1',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category chips (F2) ───────────────────────────────────────────────────────
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.selected,
    required this.onToggle,
    required this.onClearAll,
  });
  final Set<String>          selected;
  final ValueChanged<String> onToggle;
  final VoidCallback         onClearAll;

  @override
  Widget build(BuildContext context) {
    // All five chips share the row width so they're visible at once (no
    // horizontal scroll). Each chip's content auto-scales to fit its cell.
    final chips = <Widget>[];
    for (int i = 0; i <= _kCats.length; i++) {
      if (i > 0) chips.add(const SizedBox(width: 6));
      chips.add(Expanded(child: _chip(i)));
    }
    return SizedBox(height: 34, child: Row(children: chips));
  }

  // i == 0 is the leading "All" chip; i >= 1 maps to _kCats[i - 1].
  Widget _chip(int i) {
    final bool isAll = i == 0;
    final String cat = isAll ? '' : _kCats[i - 1][0];
    // Shorten "Next Day" -> "NEXT" so the chip stays compact.
    final String label = isAll
        ? 'All'
        : (cat == 'next_day' ? 'NEXT' : _kCats[i - 1][1]);
    final bool sel = isAll ? selected.isEmpty : selected.contains(cat);
    final Color color = isAll ? _kAccent : _catColor(cat);
    final IconData icon = isAll ? Icons.apps_rounded : _catIcon(cat);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        isAll ? onClearAll() : onToggle(cat);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: sel ? color : _kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? color : _kSep,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: sel
                  ? color.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: sel ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: sel ? Colors.white : color),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : _kInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

// ── Pending offline uploads pill ────────────────────────────────────────────
/// Surfaces the offline upload queue. Hidden when empty; tapping forces a
/// retry. The queue also retries itself automatically on a timer + when
/// connectivity returns.
class _PendingUploadsPill extends StatelessWidget {
  const _PendingUploadsPill();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: UploadQueueService.instance.pendingCount,
        builder: (_, count, __) {
          if (count == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: UploadQueueService.instance.process,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kAccent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_upload_rounded,
                          size: 13, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        '$count upload${count > 1 ? 's' : ''} pending · '
                        'retrying…',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}

// ── My-location FAB ───────────────────────────────────────────────────────────
class _LocationFab extends StatelessWidget {
  const _LocationFab({
    required this.onTap,
    this.userPosition,
    this.loading = false,
  });
  final VoidCallback onTap;
  final Position?    userPosition;
  final bool         loading;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _kSurface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
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
              userPosition != null
                  ? Icons.location_on_outlined
                  : Icons.location_on_outlined,
              size: 22,
              color: userPosition != null ? _kAccent : _kSubtle,
            ),
    ),
  );
}

// ── Bottom stats card ─────────────────────────────────────────────────────────
class _BottomCard extends StatelessWidget {
  const _BottomCard({
    required this.count,
    required this.groupCount,
    required this.svcCounts,
    required this.onFitAll,
    required this.onViewList,
  });
  final int              count;
  final int              groupCount;
  final Map<String, int> svcCounts;
  final VoidCallback     onFitAll;
  final VoidCallback     onViewList;

  @override
  Widget build(BuildContext context) {
    final svcEntries = svcCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
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
          // Drag handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: _kSep,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 18,
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _kInk,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            '$count photo${count != 1 ? 's' : ''}'
                            ' · $groupCount pin${groupCount != 1 ? 's' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _kSubtle,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Service type breakdown
                if (svcEntries.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: svcEntries.map((e) {
                      final color = _svcColor(e.key);
                      final label = e.key == 'rush'
                          ? 'ASAP'
                          : e.key == 'airport'
                              ? 'Airport'
                              : 'Standard';
                      return Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$label ${e.value}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _kInkMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // Proportional color bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: Row(
                        children: svcEntries
                            .map((e) => Expanded(
                                  flex: e.value,
                                  child: Container(
                                      color: _svcColor(e.key)),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _CardBtn(
                        icon: Icons.fullscreen_rounded,
                        label: 'Fit All',
                        onTap: onFitAll,
                        filled: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CardBtn(
                        icon: Icons.format_list_bulleted_rounded,
                        label: 'View List',
                        onTap: onViewList,
                        filled: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
  final VoidCallback onTap;
  final bool         filled;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      HapticFeedback.lightImpact();
      onTap();
    },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        gradient: filled
            ? const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: filled ? null : _kAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: filled
            ? null
            : Border.all(color: _kAccent.withValues(alpha: 0.22)),
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
          Icon(icon, size: 15, color: filled ? Colors.white : _kAccent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : _kAccent,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Pin marker ────────────────────────────────────────────────────────────────
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
        alignment: Alignment.center,
        children: [
          // Ambient glow ring
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
          ),
          // Photo circle
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
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
                  color: color.withValues(alpha: 0.15),
                  child: Icon(Icons.person_rounded, color: color, size: 22),
                ),
              ),
            ),
          ),
          // Count badge
          if (count > 1)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
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
      // Pin stem + dot
      Container(width: 2, height: 7, color: color),
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
          ],
        ),
      ),
    ],
  );
}

// ── User-location marker (pulsing) ────────────────────────────────────────────
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
        Container(
          width: 48 + _pulse.value * 8,
          height: 48 + _pulse.value * 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kAccent.withValues(
                alpha: 0.12 - _pulse.value * 0.08),
            border: Border.all(
              color: _kAccent.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
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
