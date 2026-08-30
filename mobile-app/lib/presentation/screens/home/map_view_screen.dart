import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/map_tiles.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/file_number.dart';
import '../../../core/utils/place_search.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/profile_model.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/ai_prefs_provider.dart';
import '../../widgets/ai/ai_spark_button.dart';
import '../../widgets/ai/voice_mic_button.dart';
import '../../widgets/common/photo_preview_gallery.dart';
import '../upload/attempt_draft_controller.dart';
import '../upload/attempt_limits.dart';
import '../upload/resume_attempt_screen.dart';
import 'map_upload_sheet.dart';

// ── Design tokens (light field UI) ────────────────────────────────────────────
const _kSurface  = Color(0xFFFFFFFF);
const _kInk      = Color(0xFF1A2130);
const _kInkMuted = Color(0xFF5C6778);
const _kSubtle   = Color(0xFF8B95A5);
const _kSep      = Color(0xFFE3E7EE);
const _kAccent   = Color(0xFF4A90E2);
const _kPending  = Color(0xFFF5C400);
const _kFab      = Color(0xF2FFFFFF);



// Used for the "enable GPS" hint in the filter sheet. (Category colours now
// come from categoryOf() in category.dart.)
const _kAsap     = Color(0xFFEF4444);

// ── Helpers ───────────────────────────────────────────────────────────────────
Map<String, List<PhotoModel>> _groupByLocation(List<PhotoModel> photos) {
  final map = <String, List<PhotoModel>>{};
  for (final p in photos) {
    final key =
        '${p.latitude.toStringAsFixed(5)}_${p.longitude.toStringAsFixed(5)}';
    map.putIfAbsent(key, () => []).add(p);
  }
  return map;
}

/// One pin on the home map = one job (same grouping as the Jobs tab).
class _MapJob {
  _MapJob({required this.profile, required this.photos});

  final ProfileModel? profile;
  final List<PhotoModel> photos;

  PhotoModel? get latest => photos.isEmpty ? null : photos.first;

  bool get isPending {
    if (photos.isEmpty) return true;
    return normalizeAttemptStatus(latest!.attemptStatus) ==
        kAttemptStatusPending;
  }

  Color get pinColor => isPending ? _kPending : _kAccent;

  String get jobId {
    final fn = latest?.fileNumber?.trim();
    if (fn != null && fn.isNotEmpty) return fn;
    if (profile != null) return '${profile!.id}';
    return latest != null ? '${latest!.id}' : '—';
  }

  String get recipient {
    final name = profile?.name.trim();
    if (name != null && name.isNotEmpty) return name;
    final fromPhoto = latest?.profileName?.trim();
    if (fromPhoto != null && fromPhoto.isNotEmpty) return fromPhoto;
    return 'Unknown';
  }

  /// Pin card heading: profile name when file number is N/A or missing,
  /// otherwise "fileNumber profileName".
  String get pinSummaryTitle {
    final name = recipient;
    if (isAbsentFileNumber(latest?.fileNumber)) return name;
    final fn = latest!.fileNumber!.trim();
    if (name.isEmpty || name == 'Unknown') return fn;
    return '$fn $name';
  }

  String get address {
    final fromPhoto = latest?.address?.trim();
    if (fromPhoto != null && fromPhoto.isNotEmpty) {
      return PlaceSearch.withoutZip(fromPhoto);
    }
    final parts = [
      profile?.address,
      profile?.city,
      profile?.state,
      profile?.postalCode,
    ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
    if (parts.isNotEmpty) return PlaceSearch.withoutZip(parts.join(', '));
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  double? get _rawLat {
    if (_usable(profile?.latitude, profile?.longitude)) {
      return profile!.latitude;
    }
    return latest?.latitude;
  }

  double? get _rawLng {
    if (_usable(profile?.latitude, profile?.longitude)) {
      return profile!.longitude;
    }
    return latest?.longitude;
  }

  static bool _usable(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      (lat.abs() > 0.0001 || lng.abs() > 0.0001);

  bool get hasPoint =>
      _rawLat != null &&
      _rawLng != null &&
      (_rawLat!.abs() > 0.0001 || _rawLng!.abs() > 0.0001);

  double get lat => _rawLat!;
  double get lng => _rawLng!;
  LatLng get point => LatLng(lat, lng);

  int get attemptCount => jobAttemptCount(
        photos: photos,
        profileAttemptsCount: profile?.attemptsCount,
      );
}

// Breakdown by per-photo priority category (serviceType is legacy and now
// always 'standard').
Map<String, int> _countByService(List<PhotoModel> photos) {
  final counts = <String, int>{};
  for (final p in photos) {
    final s = categoryOf(p.category).value;
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

  /// Fired by FlutterMap once it's ready to accept camera moves.
  /// Pins are framed as soon as they load — locate FAB still jumps to GPS.
  void _onMapReady() {
    _fetchUserLocation(moveCamera: false);
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

  bool get _mapHasSize {
    try {
      final size = _mapController.camera.size;
      return size.x >= 8 && size.y >= 8;
    } catch (_) {
      return false;
    }
  }

  void _refresh() {
    ref.invalidate(photosProvider);
    ref.invalidate(profilesProvider);
    _fetchUserLocation();
  }

  void _fitAll(List<LatLng> points) {
    if (points.isEmpty) return;
    if (!_mapHasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAll(points);
      });
      return;
    }

    final core = _mainClusterPoints(points);

    var minLat = core.first.latitude;
    var maxLat = core.first.latitude;
    var minLng = core.first.longitude;
    var maxLng = core.first.longitude;
    for (final p in core) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final spanMi = LocationService.calculateDistance(
            minLat, minLng, maxLat, maxLng) *
        0.621371;
    if (spanMi > 500) {
      _mapController.move(core.first, 12);
      return;
    }

    if ((maxLat - minLat).abs() < 1e-4 && (maxLng - minLng).abs() < 1e-4) {
      _mapController.move(LatLng(minLat, minLng), 13);
      return;
    }

    final topInset = MediaQuery.of(context).padding.top;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: EdgeInsets.fromLTRB(48, topInset + 88, 56, 140),
        maxZoom: 13,
        forceIntegerZoomLevel: true,
      ),
    );
  }

  /// Default window: my GPS + the closest job pin, same viewport.
  void _fitMeAndNearest(List<LatLng> points) {
    if (!mounted) return;
    final user = _userPosition;
    final pins = _mainClusterPoints(points);
    if (user == null || pins.isEmpty) {
      _fitAll(points);
      return;
    }
    final origin = LatLng(user.latitude, user.longitude);
    LatLng nearest = pins.first;
    var bestKm = double.infinity;
    for (final p in pins) {
      final km = LocationService.calculateDistance(
          origin.latitude, origin.longitude, p.latitude, p.longitude);
      if (km < bestKm) {
        bestKm = km;
        nearest = p;
      }
    }
    final topInset = MediaQuery.of(context).padding.top;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([origin, nearest]),
        padding: EdgeInsets.fromLTRB(56, topInset + 96, 56, 148),
        maxZoom: 16,
        forceIntegerZoomLevel: true,
      ),
    );
  }

  // Excludes pins farther than [_outlierThresholdMi] from the median position
  // of the group, so a single stray outlier can't force "Fit All" out to a
  // world-scale zoom. Falls back to the full list if that would exclude
  // everything (e.g. the group is small or evenly spread out).
  static const double _outlierThresholdMi = 200;

  // (0,0) "null island" or out-of-range values from a bad GPS fix — dropped
  // before computing the median/bounds so a handful of them can't skew the
  // median enough to defeat the outlier filter below.
  List<LatLng> _mainClusterPoints(List<LatLng> points) {
    final valid = points.where((p) =>
        p.latitude.abs() > 0.0001 &&
        p.longitude.abs() > 0.0001 &&
        p.latitude.abs() <= 90 &&
        p.longitude.abs() <= 180).toList();
    final base = valid.isEmpty ? points : valid;
    if (base.length <= 2) return base;

    final lats = base.map((p) => p.latitude).toList()..sort();
    final lngs = base.map((p) => p.longitude).toList()..sort();
    final medianLat = lats[lats.length ~/ 2];
    final medianLng = lngs[lngs.length ~/ 2];

    final core = base.where((p) {
      final km = LocationService.calculateDistance(
          medianLat, medianLng, p.latitude, p.longitude);
      return km * 0.621371 <= _outlierThresholdMi;
    }).toList();

    return core.isEmpty ? base : core;
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: the map must open INSTANTLY, centred on the user — never gate it
    // behind the jobs network call, which can stall on poor field signal and
    // leave the user staring at a blank spinner. Render the map with whatever
    // data we already have; pins and the profile selector fill in on their own
    // as the requests complete. The primary action (tap the map to log a new
    // attempt) works the moment the map is up — no waiting on existing pins.
    final photos = ref.watch(photosProvider).valueOrNull ?? const <PhotoModel>[];

    return Scaffold(
      // Full-screen map — no AppBar, body extends to top
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF2F4F7),
      body: _MapBody(
        photos: photos,
        searchCtrl: _searchCtrl,
        mapController: _mapController,
        userPosition: _userPosition,
        fetchingLocation: _fetchingLocation,
        locationAttemptDone: _locationAttemptDone,
        onMapReady: _onMapReady,
        onFitAll: _fitAll,
        onFitMeAndNearest: _fitMeAndNearest,
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
    required this.searchCtrl,
    required this.mapController,
    required this.onMapReady,
    required this.onFitAll,
    required this.onFitMeAndNearest,
    required this.onRefresh,
    required this.onMyLocation,
    this.userPosition,
    this.fetchingLocation = false,
    this.locationAttemptDone = false,
  });

  final List<PhotoModel>               photos;
  final TextEditingController          searchCtrl;
  final MapController                  mapController;
  final VoidCallback                   onMapReady;
  final ValueChanged<List<LatLng>> onFitAll;
  final ValueChanged<List<LatLng>> onFitMeAndNearest;
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
  // Quick-filter pill: only today's pins. Independent of _levels so "All" +
  // "Today" can combine (e.g. every priority, today only).
  bool _todayOnly = false;
  int _fittedCount = -1;
  bool _fittedWithGps = false;
  // Distance filter — a radius from the user (0–100 mi).
  double _distanceMi = 100;
  String? _distanceMode; // 'distance' | null
  // Debounces the camera fit while the distance slider is being dragged, so
  // it flies once the user settles instead of on every intermediate tick.
  Timer? _filterFitDebounce;
  _MapJob? _selectedJob;

  @override
  void initState() {
    super.initState();
    widget.searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onSearchChanged);
    _filterFitDebounce?.cancel();
    super.dispose();
  }

  // Frames the map around the active distance filter, or the visible pins.
  void _fitToActiveFilter() {
    if (!mounted) return;
    if (_distanceMode == 'distance' && widget.userPosition != null) {
      final lat = widget.userPosition!.latitude;
      final lng = widget.userPosition!.longitude;
      final radiusMi = _distanceMi < 0.5 ? 0.5 : _distanceMi;
      final latDelta = radiusMi / 69.0;
      final cosLat = math.cos(lat * math.pi / 180).abs();
      final lngDelta = radiusMi / (69.0 * (cosLat < 0.01 ? 0.01 : cosLat));
      widget.mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(lat - latDelta, lng - lngDelta),
            LatLng(lat + latDelta, lng + lngDelta),
          ),
          padding: const EdgeInsets.all(60),
        ),
      );
      return;
    }
    widget.onFitAll(_mapJobs().map((j) => j.point).toList());
  }

  void _scheduleFilterFit() {
    _filterFitDebounce?.cancel();
    _filterFitDebounce =
        Timer(const Duration(milliseconds: 300), _fitToActiveFilter);
  }

  bool get _anyFilterActive =>
      _levels.isNotEmpty ||
      _todayOnly ||
      _distanceMode != null ||
      widget.searchCtrl.text.trim().isNotEmpty;

  // Resets every active filter (priority level, today, distance) from
  // outside the filter sheet — used by the "no pins match" empty state so a
  // narrow filter never strands the user without a way back.
  void _clearAllFilters() {
    setState(() {
      _levels.clear();
      _todayOnly = false;
      _distanceMode = null;
      _distanceMi = 100;
      _selectedJob = null;
    });
    widget.searchCtrl.clear();
    _scheduleFilterFit();
  }

  String _categoryDetail(String value) => switch (value) {
        'asap' => 'Rush jobs that need to go out as soon as possible.',
        'special' => 'Jobs that need extra care or special instructions.',
        'standard' => 'Regular service attempts at the usual pace.',
        'next_day' => 'Jobs scheduled for the next business day.',
        _ => 'Show matching pins on the map.',
      };

  int _geotaggedCountFor(String? category, {bool todayOnly = false}) {
    final now = DateTime.now();
    return widget.photos.where((p) {
      if (p.latitude == 0 && p.longitude == 0) return false;
      if (category != null && (p.category ?? 'standard') != category) {
        return false;
      }
      if (todayOnly) {
        final ts = p.takenAt ?? p.timestamp;
        if (ts == null) return false;
        final dt = DateTime.tryParse(ts)?.toLocal();
        if (dt == null) return false;
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }
      return true;
    }).length;
  }

  Widget _filterDetailRow({
    required String title,
    required String detail,
    required Color color,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    int? count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: const Cubic(0.23, 1, 0.32, 1),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : _kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color : _kSep,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected ? color : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: selected ? Colors.white : color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selected ? color : _kInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: _kInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? color : _kSubtle,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 20,
                  color: selected ? color : _kSep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // A soft grouped section container used inside the filter sheet.
  Widget _sheetCard({required String title, required List<Widget> children}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kSep),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _kInkMuted)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  // Filter sheet: same dock categories (with details) plus distance.
  // Opens from the tune button or a swipe-up on the filter dock.
  void _showFilterSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, ssheet) {
          // Runs the mutation exactly once, then rebuilds both the sheet and
          // the map behind it. Must NOT call fn() twice — toggles like the
          // priority-level bubbles (add-if-absent / remove-if-present) would
          // cancel themselves out on the second call.
          void refresh(VoidCallback fn) {
            fn();
            ssheet(() {});
            setState(() {}); // rebuild the map behind the sheet
          }

          final hasLoc = widget.userPosition != null;
          final anyActive =
              _levels.isNotEmpty || _todayOnly || _distanceMode != null;
          final resultCount = _mapJobs().length;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFF2F4F7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded,
                          size: 20, color: _kAccent),
                      const SizedBox(width: 8),
                      const Text('Filter pins',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kInk)),
                      const Spacer(),
                      if (anyActive)
                        TextButton(
                          onPressed: () {
                            refresh(() {
                              _levels.clear();
                              _todayOnly = false;
                              _distanceMode = null;
                              _distanceMi = 100;
                            });
                            _scheduleFilterFit();
                          },
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sheetCard(
                          title: 'When',
                          children: [
                            _filterDetailRow(
                              title: 'Today',
                              detail: 'Only pins captured today.',
                              color: _kAccent,
                              icon: Icons.calendar_today_rounded,
                              selected: _todayOnly,
                              count: _geotaggedCountFor(null, todayOnly: true),
                              onTap: () =>
                                  refresh(() => _todayOnly = !_todayOnly),
                            ),
                          ],
                        ),
                        // ── Distance ──
                        _sheetCard(
                          title: 'Distance',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Within my range',
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: _distanceMode == 'distance'
                                              ? _kInk
                                              : _kInkMuted)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _distanceMode == 'distance'
                                        ? _kAccent
                                        : _kAccent.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text('${_distanceMi.round()} mi',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: _distanceMode == 'distance'
                                              ? Colors.white
                                              : _kAccent)),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(sheetCtx).copyWith(
                                trackHeight: 4,
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16),
                              ),
                              child: Slider(
                                value: _distanceMi,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                activeColor: _kAccent,
                                inactiveColor:
                                    _kAccent.withValues(alpha: 0.15),
                                onChanged: hasLoc
                                    ? (v) {
                                        refresh(() {
                                          _distanceMi = v;
                                          _distanceMode = 'distance';
                                        });
                                        _scheduleFilterFit();
                                      }
                                    : null,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 2),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('0 mi',
                                      style: TextStyle(
                                          fontSize: 11, color: _kInkMuted)),
                                  Text('100 mi',
                                      style: TextStyle(
                                          fontSize: 11, color: _kInkMuted)),
                                ],
                              ),
                            ),
                            if (!hasLoc)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                    'Enable GPS to filter by distance.',
                                    style: TextStyle(
                                        fontSize: 12, color: _kAsap)),
                                ),
                            if (_distanceMode != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                      padding: const EdgeInsets.only(top: 8),
                                      foregroundColor: _kInkMuted,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap),
                                  onPressed: () {
                                    refresh(() {
                                      _distanceMode = null;
                                    });
                                    _scheduleFilterFit();
                                  },
                                  icon: const Icon(Icons.close_rounded,
                                      size: 15),
                                  label: const Text('Clear distance filter'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Sticky footer: apply / show results ──
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 12, 20, MediaQuery.of(sheetCtx).padding.bottom + 14),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _kSep)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: Text(
                          resultCount == 0
                              ? 'No pins match'
                              : 'Show $resultCount '
                                  'pin${resultCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Marker _jobMarker(_MapJob job, List<_MapJob> all) {
    final selected = _isSelectedJob(job);
    return Marker(
      point: _spreadPoint(job, all),
      width: selected ? 36 : 28,
      height: selected ? 48 : 38,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          setState(() => _selectedJob = job);
        },
        child: _PinMarker(
          color: job.pinColor,
          selected: selected,
          label: null,
        ),
      ),
    );
  }

  /// Fan coincident pins into a ring so 10 jobs at one GPS still all show.
  LatLng _spreadPoint(_MapJob job, List<_MapJob> all) {
    final twins = all
        .where((j) =>
            (j.lat - job.lat).abs() < 1e-4 && (j.lng - job.lng).abs() < 1e-4)
        .toList();
    if (twins.length <= 1) return job.point;
    final i = twins.indexOf(job);
    final n = twins.length;
    final angle = (2 * math.pi * (i < 0 ? 0 : i)) / n;
    // ~250m base, grows with count so a 10-job stack is a clear ring.
    final d = 0.0022 + n * 0.00045;
    return LatLng(
      job.lat + d * math.cos(angle),
      job.lng + d * math.sin(angle),
    );
  }

  bool _isSelectedJob(_MapJob job) {
    final s = _selectedJob;
    if (s == null) return false;
    if (s.profile != null && job.profile != null) {
      return s.profile!.id == job.profile!.id;
    }
    return s.jobId == job.jobId;
  }

  Future<void> _startAttemptFromPin(BuildContext context, {_MapJob? job}) async {
    final selected = job ?? _selectedJob;
    if (selected == null) return;
    final pid = selected.profile?.id ?? selected.latest?.profileId;
    if (pid == null || pid == 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open this job from Profiles, or create a profile first.',
          ),
        ),
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final ok = await ensureCanStartNewAttempt(
      context,
      ref,
      profileId: pid,
      knownCount: selected.attemptCount,
    );
    if (!ok || !context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeAttemptScreen(
          initialProfileId: pid,
          initialProfile: selected.profile,
        ),
      ),
    );
  }

  String? _distanceLabelFor(double lat, double lng) {
    final pos = widget.userPosition;
    if (pos == null) return null;
    final m = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, lat, lng);
    final mi = m / 1609.34;
    if (mi < 0.1) return 'Nearby';
    return '${mi.toStringAsFixed(1)} mi';
  }

  String _addressOf(PhotoModel p) {
    final addr = p.address?.trim();
    if (addr != null && addr.isNotEmpty) return addr;
    final zip = p.zipCode?.trim();
    if (zip != null && zip.isNotEmpty) return 'ZIP $zip';
    return '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
  }

  // The photos visible on the map after all active filters (service level,
  // distance) + a valid geotag. Shared by build() and the filter sheet's
  // live result count.
  List<PhotoModel> _visiblePhotos() {
    var filtered = widget.photos;

    if (_levels.isNotEmpty) {
      filtered = filtered
          .where((p) => _levels.contains(p.category ?? 'standard'))
          .toList();
    }

    if (_todayOnly) {
      final now = DateTime.now();
      filtered = filtered.where((p) {
        final ts = p.takenAt ?? p.timestamp;
        if (ts == null) return false;
        final dt = DateTime.tryParse(ts)?.toLocal();
        if (dt == null) return false;
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }).toList();
    }

    // Distance filter.
    if (_distanceMode == 'distance' && widget.userPosition != null) {
      final ulat = widget.userPosition!.latitude;
      final ulng = widget.userPosition!.longitude;
      filtered = filtered.where((p) {
        final km = LocationService.calculateDistance(
            ulat, ulng, p.latitude, p.longitude);
        return km * 0.621371 <= _distanceMi; // km → miles
      }).toList();
    }

    if (widget.searchCtrl.text.trim().isNotEmpty) {
      filtered = filtered.where((p) {
        return _matchesProfileOrZip(
          name: p.profileName,
          zip: p.zipCode,
          address: p.address,
        );
      }).toList();
    }

    return filtered
        .where((p) => p.latitude != 0 || p.longitude != 0)
        .toList();
  }

  /// Same job grouping as the Jobs tab: one pin per profile, plus leftover
  /// geotagged photos that have no profile. Pending / awaiting jobs stay on
  /// the map as yellow pins.
  List<_MapJob> _mapJobs() {
    final photos = _visiblePhotos();
    final profiles = ref.read(profilesProvider).valueOrNull ?? [];
    final used = <int>{};
    final jobs = <_MapJob>[];

    for (final profile in profiles) {
      final pPhotos = photos
          .where((ph) =>
              ph.profileId == profile.id ||
              (ph.profiles?.any((p) => p.id == profile.id) ?? false))
          .toList()
        ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      for (final p in pPhotos) {
        used.add(p.id);
      }
      if (pPhotos.isEmpty) {
        if (_todayOnly) continue;
        if (_levels.isNotEmpty &&
            !_levels.contains((profile.serviceType).toLowerCase())) {
          continue;
        }
        if (!profile.hasLocation) continue;
        if (!_profilePassesDistanceAndSearch(profile)) continue;
      }
      final job = _MapJob(profile: profile, photos: pPhotos);
      if (job.hasPoint) jobs.add(job);
    }

    final leftover = photos.where((p) => !used.contains(p.id)).toList();
    for (final g in _groupByLocation(leftover).values) {
      g.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      final job = _MapJob(profile: null, photos: g);
      if (job.hasPoint) jobs.add(job);
    }
    return jobs;
  }

  bool _profilePassesDistanceAndSearch(ProfileModel profile) {
    if (_distanceMode == 'distance' && widget.userPosition != null &&
        profile.hasLocation) {
      final km = LocationService.calculateDistance(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        profile.latitude!,
        profile.longitude!,
      );
      if (km * 0.621371 > _distanceMi) return false;
    }
    return _matchesProfileOrZip(
      name: profile.name,
      zip: profile.postalCode,
      address: profile.address,
    );
  }

  bool _matchesProfileOrZip({
    String? name,
    String? zip,
    String? address,
  }) {
    final q = widget.searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    if ((name ?? '').toLowerCase().contains(q)) return true;
    if ((zip ?? '').toLowerCase().contains(q)) return true;
    if (RegExp(r'^\d{5}').hasMatch(q) && (address ?? '').contains(q)) {
      return true;
    }
    return false;
  }

  Widget _nextUpChip(List<_MapJob> jobs) {
    final profiles = ref.read(profilesProvider).valueOrNull ?? [];
    ProfileModel? latestProfile;
    if (profiles.isNotEmpty) {
      latestProfile = profiles.reduce((a, b) => a.id >= b.id ? a : b);
    }

    _MapJob? next;
    if (latestProfile != null) {
      for (final j in jobs) {
        if (j.profile?.id == latestProfile.id) {
          next = j;
          break;
        }
      }
    }
    next ??= jobs.isEmpty ? null : jobs.reduce((a, b) {
      final aid = a.profile?.id ?? a.latest?.id ?? 0;
      final bid = b.profile?.id ?? b.latest?.id ?? 0;
      return bid >= aid ? b : a;
    });

    if (next == null && latestProfile == null) {
      return const SizedBox.shrink();
    }

    final name = latestProfile?.name.trim().isNotEmpty == true
        ? latestProfile!.name.trim()
        : next?.recipient ?? 'Unknown';
    final pid = latestProfile?.id ?? next?.profile?.id;

    double? miles;
    final pos = widget.userPosition;
    final lat = latestProfile != null &&
            _MapJob._usable(latestProfile.latitude, latestProfile.longitude)
        ? latestProfile.latitude
        : next?.hasPoint == true
            ? next!.lat
            : null;
    final lng = latestProfile != null &&
            _MapJob._usable(latestProfile.latitude, latestProfile.longitude)
        ? latestProfile.longitude
        : next?.hasPoint == true
            ? next!.lng
            : null;
    if (pos != null && lat != null && lng != null) {
      miles = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, lat, lng) /
          1609.34;
    }

    final dist = miles == null
        ? null
        : miles < 0.1
            ? 'Nearby'
            : miles < 10
                ? '${miles.toStringAsFixed(1)} mi'
                : '${miles.round()} mi';
    final pay = latestProfile?.payRate ?? next?.profile?.payRate;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          if (pid != null) {
            context.push(
              '/new-attempt?profileId=$pid',
              extra: latestProfile ?? next?.profile,
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xF5FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kSep),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: _kAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    'Next up · $name',
                    if (dist != null) dist,
                    if (pay != null) '\$$pay',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kInk,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: _kSubtle),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    ref.watch(profilesProvider);

    final jobs = _mapJobs();
    final hasData = jobs.isNotEmpty;

    if (hasData &&
        (jobs.length != _fittedCount ||
            (widget.userPosition != null && !_fittedWithGps))) {
      _fittedCount = jobs.length;
      _fittedWithGps = widget.userPosition != null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onFitMeAndNearest(
            jobs.map((j) => _spreadPoint(j, jobs)).toList());
      });
    }

    const mapCenter = LatLng(32.7157, -117.1611);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Tight constraints so flutter_map's camera size matches the screen.
        // A loose Stack child lets tiles paint in a small strip while markers
        // still use the full camera, which is what the gray "map hole" was.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
                return const ColoredBox(color: Color(0xFFF2F4F7));
              }
              return FlutterMap(
            mapController: widget.mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 13,
              minZoom: 2,
              maxZoom: 18,
              keepAlive: true,
              backgroundColor: const Color(0xFFF2F4F7),
              onMapReady: widget.onMapReady,
              onTap: _selectedJob != null
                  ? null
                  : (_, latLng) {
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
              AppMapTiles.layer(),
            // Visualize the active radius filter
            if (_distanceMode == 'distance' && widget.userPosition != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(
                      widget.userPosition!.latitude,
                      widget.userPosition!.longitude,
                    ),
                    radius: _distanceMi * 1609.34,
                    useRadiusInMeter: true,
                    color: _kAccent.withValues(alpha: 0.07),
                    borderColor: _kAccent,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            // User location under job pins so stacked jobs stay visible.
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
            // One teardrop pin per job. Pending / awaiting = yellow; others blue.
            MarkerLayer(
              markers: [
                for (final job in jobs) _jobMarker(job, jobs),
              ],
            ),
          ],
              );
            },
          ),
        ),

        // Full-screen catcher so the map cannot steal Add Attempt taps
        // (flutter_map competes in the gesture arena with overlays).
        if (_selectedJob != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedJob = null);
              },
            ),
          ),

        // ── Top: search + filter ───────────────────────────────────────
        Positioned(
          top: topPad + 10,
          left: 14,
          right: 14,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SearchBar(controller: widget.searchCtrl),
                  ),
                  const SizedBox(width: 8),
                  const AiSparkButton(),
                ],
              ),
              if (ref.watch(aiSmartSuggestionsProvider))
                _nextUpChip(jobs),
            ],
          ),
        ),

        // ── Filter dock ────────────────────────────────────────────────
          if (_selectedJob == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MapFilterDock(
              moreFiltersActive: _todayOnly || _distanceMode != null,
              onMoreFilters: _showFilterSheet,
            ),
          ),

        // ── Map FABs: fit / locate ─────────────────────────────────────
        Positioned(
          right: 14,
          bottom: _selectedJob != null
              ? 380
              : 86,
          child: Material(
            color: Colors.transparent,
            child: _ZoomControls(
              onFitTap: () =>
                  widget.onFitAll(jobs.map((j) => j.point).toList()),
              userPosition: widget.userPosition,
              loading: widget.fetchingLocation,
              onLocateTap: () {
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

        // Pin card last so map, dock, and FABs cannot steal button taps.
        if (_selectedJob != null)
          Positioned(
            left: 14,
            right: 14,
            bottom: _selectedJob != null ? 16 : 86,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: _JobPreviewCard(
                  key: ValueKey(_selectedJob!.jobId),
                  attempts: _selectedJob!.attemptCount,
                  photos: _selectedJob!.photos,
                  atCap: _selectedJob!.attemptCount >=
                      AttemptDraftController.kMaxAttemptsPerJob,
                  distance: _distanceLabelFor(
                      _selectedJob!.lat, _selectedJob!.lng),
                  address: _selectedJob!.address,
                  title: _selectedJob!.pinSummaryTitle,
                  pending: _selectedJob!.isPending,
                  onNewAttempt: () {
                    unawaited(_startAttemptFromPin(context, job: _selectedJob));
                  },
                  onPreviewPhoto: (index) {
                    final photos = _selectedJob?.photos ?? const <PhotoModel>[];
                    if (photos.isEmpty || !context.mounted) return;
                    PhotoPreviewGallery.open(
                      context,
                      photos: photos,
                      initialIndex: index,
                    );
                  },
                ),
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
                    style: TextStyle(color: _kAccent),
                  ),
                  TextSpan(
                    text: 'Tag',
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
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kSep),
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
                hintText: 'Say a profile or ZIP',
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
        color: _kFab,
        shape: BoxShape.circle,
        border: Border.all(color: _kSep),
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
              color: userPosition != null ? _kInk : _kSubtle,
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
    required this.title,
    required this.onNewAttempt,
    required this.onPreviewPhoto,
    this.photos = const [],
    this.distance,
    this.atCap = false,
    this.pending = false,
  });

  final int attempts;
  final bool atCap;
  final bool pending;
  final String? distance;
  final String address;
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
          Text(
            widget.address,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _kAccent,
              height: 1.3,
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
                icon: widget.atCap ? Icons.block_rounded : Icons.add_rounded,
                label: widget.atCap ? 'Max attempts' : 'Add Attempt',
                onTap: widget.atCap ? null : widget.onNewAttempt,
                filled: !widget.atCap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom filter dock — pills only, no profile list. ────────────────────────
class _MapFilterDock extends StatelessWidget {
  const _MapFilterDock({
    required this.moreFiltersActive,
    required this.onMoreFilters,
  });

  final bool moreFiltersActive;
  final VoidCallback onMoreFilters;

  void _openFromSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -240) onMoreFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 16,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: _openFromSwipe,
          onTap: onMoreFilters,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _kInk,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: moreFiltersActive ? _kAccent : const Color(0xFFF2F4F7),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: moreFiltersActive ? _kAccent : _kSep,
                      ),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: moreFiltersActive ? Colors.white : _kInkMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
class _PinMarker extends StatelessWidget {
  const _PinMarker({
    required this.color,
    required this.selected,
    this.label,
  });

  final Color color;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final head = selected ? 26.0 : 22.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        SizedBox(
          width: head,
          height: head + 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: head,
                height: head,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: selected ? 0.5 : 0.32),
                      blurRadius: selected ? 10 : 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              CustomPaint(
                size: Size(head * 0.42, 9),
                painter: _PinTipPainter(color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PinTipPainter extends CustomPainter {
  _PinTipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final tip = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(tip, paint);
  }

  @override
  bool shouldRepaint(covariant _PinTipPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Quick-filter pill row (All / Standard / ASAP / Today) — a faster-access
// layer on top of the existing _levels/_todayOnly state; the full filter
// sheet (profile + distance/ZIP + priority) is still reachable via the
// search bar's tune icon. ──
class _FilterPillRow extends StatelessWidget {
  const _FilterPillRow({
    required this.levels,
    required this.todayOnly,
    required this.onLevelsChanged,
    required this.onTodayChanged,
  });
  final Set<String> levels;
  final bool todayOnly;
  final ValueChanged<Set<String>> onLevelsChanged;
  final ValueChanged<bool> onTodayChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _pill(
          label: 'All',
          selected: levels.isEmpty,
          color: _kAccent,
          onTap: () => onLevelsChanged({}),
        ),
        const SizedBox(width: 8),
        _pill(
          label: 'Standard',
          selected: levels.length == 1 && levels.contains('standard'),
          color: categoryOf('standard').color,
          onTap: () => onLevelsChanged({'standard'}),
        ),
        const SizedBox(width: 8),
        _pill(
          label: 'ASAP',
          selected: levels.length == 1 && levels.contains('asap'),
          color: categoryOf('asap').color,
          onTap: () => onLevelsChanged({'asap'}),
        ),
        const SizedBox(width: 8),
        _pill(
          label: 'Special',
          selected: levels.length == 1 && levels.contains('special'),
          color: categoryOf('special').color,
          onTap: () => onLevelsChanged({'special'}),
        ),
        const SizedBox(width: 8),
        _pill(
          label: 'Next Day',
          selected: levels.length == 1 && levels.contains('next_day'),
          color: categoryOf('next_day').color,
          onTap: () => onLevelsChanged({'next_day'}),
        ),
        const SizedBox(width: 8),
        _pill(
          label: 'Today',
          selected: todayOnly,
          color: _kAccent,
          onTap: () => onTodayChanged(!todayOnly),
          icon: Icons.calendar_today_rounded,
        ),
      ],
    ),
  );

  Widget _pill({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    IconData? icon,
  }) => GestureDetector(
    onTap: () {
      HapticFeedback.selectionClick();
      onTap();
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? color : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : _kSep,
        ),
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: selected ? Colors.white : _kInkMuted),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : _kInkMuted,
            ),
          ),
        ],
      ),
    ),
  );
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

// ── Vertical zoom-control stack: [+] [-] [locate]. Replaces the standalone
// _LocationFab Positioned block; the locate button is that exact same
// widget/behavior, just relocated into this stack. ──
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.onFitTap,
    required this.userPosition,
    required this.loading,
    required this.onLocateTap,
  });
  final VoidCallback onFitTap;
  final Position? userPosition;
  final bool loading;
  final VoidCallback onLocateTap;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _fabBtn(icon: Icons.crop_free_rounded, onTap: onFitTap),
      const SizedBox(height: 8),
      _LocationFab(
        userPosition: userPosition,
        loading: loading,
        onTap: onLocateTap,
      ),
    ],
  );

  Widget _fabBtn({required IconData icon, required VoidCallback onTap}) =>
      Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _kFab,
              shape: BoxShape.circle,
              border: Border.all(color: _kSep),
            ),
            child: Icon(icon, size: 20, color: _kInk),
          ),
        ),
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
