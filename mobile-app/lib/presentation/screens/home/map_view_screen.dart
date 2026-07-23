import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/storage/upload_queue.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/photo_model.dart';
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

// Used for the "enable GPS" hint in the filter sheet. (Category colours now
// come from categoryOf() in category.dart.)
const _kAsap     = Color(0xFFEF4444);

// ── Static category definitions ───────────────────────────────────────────────
const List<List<String>> _kCats = [
  ['asap',     'ASAP'],
  ['next_day', 'Next Day'],
  ['standard', 'Standard'],
  ['special',  'Special'],
];

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

// Highest-priority category among a group of photos (asap > next_day >
// special > standard), used to colour a multi-photo pin.
const List<String> _kCategoryPriority = [
  'asap', 'next_day', 'special', 'standard',
];
String _topCategory(List<PhotoModel> photos) {
  for (final c in _kCategoryPriority) {
    if (photos.any((p) => categoryOf(p.category).value == c)) return c;
  }
  return 'standard';
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

    // Fit to the main cluster, not the raw extent of every pin — a single
    // wildly-distant outlier (bad GPS fix, a test upload made from another
    // continent, etc.) would otherwise force the whole view out to a
    // world-scale zoom. Outlier pins still render as markers; they just
    // don't drive the camera fit.
    final core = _mainCluster(photos);

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

    // Guard against _mainCluster's fallback still producing a world-scale
    // box (e.g. every pin gets excluded as an outlier of every other pin,
    // or several bad GPS fixes skew the median). Centre on the most recent
    // pin instead of zooming out to show everything — this is the actual
    // "shows the entire Milky Way" failure mode.
    final spanMi = LocationService.calculateDistance(
            minLat, minLng, maxLat, maxLng) *
        0.621371;
    if (spanMi > 500) {
      final mostRecent = photos.reduce((a, b) =>
          (a.timestamp ?? '').compareTo(b.timestamp ?? '') >= 0 ? a : b);
      _mapController.move(
          LatLng(mostRecent.latitude, mostRecent.longitude), 12);
      return;
    }

    // All pins at (nearly) the same spot → bounds have ~zero area and
    // fitCamera would slam to maxZoom. Just centre on it at a sane zoom.
    if ((maxLat - minLat).abs() < 1e-4 && (maxLng - minLng).abs() < 1e-4) {
      _mapController.move(LatLng(minLat, minLng), 14);
      return;
    }
    // A uniform padding isn't enough here: the floating header + filter
    // pills + search bar + hint pill overlay the top of the screen, the
    // stats card overlays the bottom, and the zoom/locate button column
    // (46px wide, 14px from the edge) overlays the right — all far
    // exceeding a small uniform inset. Without accounting for them, pins
    // near the edge of the fitted bounds land at the correct geo-coordinate
    // but render UNDER that UI instead of in the visible map area.
    final topInset = MediaQuery.of(context).padding.top;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: EdgeInsets.fromLTRB(40, topInset + 230, 90, 220),
      ),
    );
  }

  // Excludes pins farther than [_outlierThresholdMi] from the median position
  // of the group, so a single stray outlier can't force "Fit All" out to a
  // world-scale zoom. Falls back to the full list if that would exclude
  // everything (e.g. the group is small or evenly spread out).
  static const double _outlierThresholdMi = 50;

  // (0,0) "null island" or out-of-range values from a bad GPS fix — dropped
  // before computing the median/bounds so a handful of them can't skew the
  // median enough to defeat the outlier filter below.
  bool _isValidCoord(PhotoModel p) =>
      p.latitude.abs() > 0.0001 &&
      p.longitude.abs() > 0.0001 &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180;

  List<PhotoModel> _mainCluster(List<PhotoModel> photos) {
    final valid = photos.where(_isValidCoord).toList();
    final base = valid.isEmpty ? photos : valid;
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
      backgroundColor: const Color(0xFFF0F0F0),
      body: _MapBody(
        photos: photos,
        searchCtrl: _searchCtrl,
        mapController: _mapController,
        userPosition: _userPosition,
        fetchingLocation: _fetchingLocation,
        locationAttemptDone: _locationAttemptDone,
        onMapReady: _onMapReady,
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
    required this.searchCtrl,
    required this.mapController,
    required this.onMapReady,
    required this.onFitAll,
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
  // Quick-filter pill: only today's pins. Independent of _levels so "All" +
  // "Today" can combine (e.g. every priority, today only).
  bool _todayOnly = false;
  bool _didInitialFit = false;
  // Distance filter — a radius from the user (0–100 mi) OR a ZIP match. Only
  // the most recently touched control applies (_distanceMode).
  double _distanceMi = 100;
  String _zip = '';
  String? _distanceMode; // 'distance' | 'zip' | null
  bool _zipBusy = false;
  // Debounces the camera fit while the distance slider is being dragged, so
  // it flies once the user settles instead of on every intermediate tick.
  Timer? _filterFitDebounce;

  @override
  void dispose() {
    _filterFitDebounce?.cancel();
    super.dispose();
  }

  // Frames the map around whatever the distance/ZIP filter implies:
  //  - distance mode: the full radius circle around the user's location
  //  - zip mode (or cleared): the bounding box of the currently visible pins
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
    widget.onFitAll(_visiblePhotos());
  }

  void _scheduleFilterFit() {
    _filterFitDebounce?.cancel();
    _filterFitDebounce =
        Timer(const Duration(milliseconds: 300), _fitToActiveFilter);
  }

  bool get _anyFilterActive =>
      _levels.isNotEmpty || _todayOnly || _distanceMode != null;

  // Resets every active filter (priority level, today, distance/ZIP) from
  // outside the filter sheet — used by the "no pins match" empty state so a
  // narrow filter never strands the user without a way back.
  void _clearAllFilters() {
    setState(() {
      _levels.clear();
      _todayOnly = false;
      _distanceMode = null;
      _zip = '';
      _distanceMi = 100;
    });
    _scheduleFilterFit();
  }

  // A tappable "or"-filter bubble. [color] present → a service-level chip
  // (soft tint + colour dot); null → a neutral action chip (select all/clear).
  Widget _bubble(String label, bool active, Color? color, VoidCallback onTap) {
    final c = color ?? _kAccent;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: active ? c : c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: active ? c : c.withValues(alpha: 0.30), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Colors.white : c),
              ),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : c)),
          ],
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
          color: const Color(0xFFF7F5FF),
          borderRadius: BorderRadius.circular(16),
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

  // Filter popup: Distance (slider 0–100 mi OR ZIP / "my zip", most-recent
  // wins) + Priority-level bubbles with Select all / Clear selection. Changes
  // apply live to the map behind the sheet.
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
          final anyActive = _levels.isNotEmpty || _distanceMode != null;
          final resultCount = _visiblePhotos().length;

          Widget modeChip(String text, bool on) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: on ? _kAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.white : _kInkMuted)),
              );

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
            ),
            decoration: const BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                              _distanceMode = null;
                              _zip = '';
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
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                    child: Container(
                                        height: 1, color: _kSep)),
                                const Padding(
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 10),
                                  child: Text('OR',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: _kInkMuted)),
                                ),
                                Expanded(
                                    child: Container(
                                        height: 1, color: _kSep)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Text('ZIP code',
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: _kInk)),
                                const SizedBox(width: 8),
                                modeChip('Active', _distanceMode == 'zip'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: _zip,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      hintText: 'e.g. 92101',
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: _kSep)),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: _kAccent, width: 1.5)),
                                    ),
                                    onChanged: (v) {
                                      refresh(() {
                                        _zip = v;
                                        _distanceMode = 'zip';
                                      });
                                      _scheduleFilterFit();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 46,
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          _kAccent.withValues(alpha: 0.10),
                                      foregroundColor: _kAccent,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    onPressed: (hasLoc && !_zipBusy)
                                        ? () async {
                                            ssheet(() => _zipBusy = true);
                                            final addr = await LocationService
                                                .reverseGeocode(
                                                    widget.userPosition!
                                                        .latitude,
                                                    widget.userPosition!
                                                        .longitude);
                                            final m = RegExp(r'\b\d{5}\b')
                                                .firstMatch(addr ?? '');
                                            refresh(() {
                                              _zipBusy = false;
                                              if (m != null) {
                                                _zip = m.group(0)!;
                                                _distanceMode = 'zip';
                                              }
                                            });
                                            if (m != null) _scheduleFilterFit();
                                          }
                                        : null,
                                    icon: _zipBusy
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.my_location,
                                            size: 16),
                                    label: const Text('My zip'),
                                  ),
                                ),
                              ],
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
                                      _zip = '';
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
                        // ── Priority level ──
                        _sheetCard(
                          title: 'Priority Level',
                          children: [
                            Wrap(
                              spacing: 9,
                              runSpacing: 9,
                              children: [
                                for (final c in _kCats)
                                  _bubble(c[1], _levels.contains(c[0]),
                                      categoryOf(c[0]).color, () {
                                    refresh(() {
                                      _levels.contains(c[0])
                                          ? _levels.remove(c[0])
                                          : _levels.add(c[0]);
                                    });
                                  }),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _bubble(
                                    'Select all',
                                    _levels.length == _kCats.length,
                                    null,
                                    () => refresh(() {
                                          _levels
                                            ..clear()
                                            ..addAll(
                                                _kCats.map((c) => c[0]));
                                        })),
                                const SizedBox(width: 9),
                                _bubble('Clear', _levels.isEmpty, null,
                                    () => refresh(_levels.clear)),
                              ],
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

  // The photos visible on the map after all active filters (service level,
  // distance/zip) + a valid geotag. Shared by build() and the filter sheet's
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

    // Distance / ZIP filter (mutually exclusive; most-recent control wins).
    if (_distanceMode == 'distance' && widget.userPosition != null) {
      final ulat = widget.userPosition!.latitude;
      final ulng = widget.userPosition!.longitude;
      filtered = filtered.where((p) {
        final km = LocationService.calculateDistance(
            ulat, ulng, p.latitude, p.longitude);
        return km * 0.621371 <= _distanceMi; // km → miles
      }).toList();
    } else if (_distanceMode == 'zip' && _zip.trim().isNotEmpty) {
      final z = _zip.trim();
      filtered = filtered.where((p) {
        final pz = (p.zipCode ?? '').trim();
        return pz.isNotEmpty ? pz == z : (p.address ?? '').contains(z);
      }).toList();
    }

    return filtered
        .where((p) => p.latitude != 0 || p.longitude != 0)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    final geotagged = _visiblePhotos();
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
            // Photo pin markers — clustered by screen proximity so nearby-
            // but-distinct pins don't overlap into an unreadable blob when
            // zoomed out to fit a wide spread (see Fit All). Pins already
            // sharing a location (see _groupByLocation) still bundle into a
            // single numbered marker via _PinMarker as before; this layer
            // additionally clusters separate markers that are simply close
            // together on screen at the current zoom.
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 50,
                size: const Size(44, 44),
                markers: groups.entries.map((entry) {
                  final sorted = [...entry.value]
                    ..sort((a, b) =>
                        (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
                  final latest  = sorted.first;
                  final color   = categoryOf(_topCategory(sorted)).color;
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
                builder: (context, markers) =>
                    _ClusterMarker(count: markers.length),
              ),
            ),
            // ── Awaiting Attempt profile pins — placeholders for a job at
            // its Profile Location, independent of any Attempt/Photo. Only
            // profiles with zero attempts show here; the moment a photo
            // exists for one it's covered by the photo pins above instead. ──
            MarkerLayer(
              markers: (ref.watch(profilesProvider).valueOrNull ?? [])
                  .where((p) => p.isAwaitingAttempt && p.hasLocation)
                  .map((p) => Marker(
                        point: LatLng(p.latitude!, p.longitude!),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            context.push('/profile/${p.id}');
                          },
                          child: const _AwaitingAttemptMarker(),
                        ),
                      ))
                  .toList(),
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
              const SizedBox(height: 12),
              // Quick filter pills + Map/List toggle
              Row(
                children: [
                  Expanded(
                    child: _FilterPillRow(
                      levels: _levels,
                      todayOnly: _todayOnly,
                      onLevelsChanged: (next) => setState(() {
                        _levels
                          ..clear()
                          ..addAll(next);
                        _scheduleFilterFit();
                      }),
                      onTodayChanged: (next) => setState(() {
                        _todayOnly = next;
                        _scheduleFilterFit();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MapListToggle(onListTap: () => context.push('/home')),
                ],
              ),
              const SizedBox(height: 10),
              // Search bar — the tune icon opens the single filter sheet
              // (distance/ZIP + service level).
              _SearchBar(
                controller: widget.searchCtrl,
                activeCount: _levels.length +
                    (_todayOnly ? 1 : 0) +
                    (_distanceMode != null ? 1 : 0),
                onFilterTap: _showFilterSheet,
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
              onViewList: () => context.push('/home'),
            ),
          )
        // A narrow filter can legitimately match zero pins — don't just
        // vanish the whole bottom card (and Fit All with it). Give the user
        // a way back instead of stranding them.
        else if (_anyFilterActive)
          Positioned(
            bottom: 16,
            left: 14,
            right: 14,
            child: _EmptyFilterCard(onClearFilters: _clearAllFilters),
          ),

        // ── Zoom controls: [+] [-] [locate] (must be LAST in Stack for
        // highest z-index). Locate keeps the exact previous _LocationFab
        // behavior, just relocated into this vertical stack. ─────────────
        Positioned(
          right: 14,
          bottom: (hasData || _anyFilterActive) ? 204 : 28,
          child: Material(
            color: Colors.transparent,
            child: _ZoomControls(
              mapController: widget.mapController,
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
    required this.activeCount,
    required this.onFilterTap,
  });
  final TextEditingController controller;
  final int                  activeCount;
  final VoidCallback         onFilterTap;

  @override
  Widget build(BuildContext context) {
    final filtered = activeCount > 0;
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
          // Single filter entry point — opens the filter sheet (profile +
          // distance/ZIP + service level).
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onFilterTap();
            },
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
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _kAccent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$activeCount',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
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
                      final color = categoryOf(e.key).color;
                      final label = categoryOf(e.key).label;
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
                                      color: categoryOf(e.key).color),
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
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: color.withValues(alpha: 0.15),
                  child: const Center(
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
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

/// Placeholder pin for a Profile marked Awaiting Attempt with a Profile
/// Location but zero photos yet — deliberately grey/outline so it never
/// reads as a real logged Attempt.
class _AwaitingAttemptMarker extends StatelessWidget {
  const _AwaitingAttemptMarker();

  static const Color _grey = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: _grey, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.schedule_rounded, color: _grey, size: 18),
      );
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
        color: selected ? color : _kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : Colors.black.withValues(alpha: 0.08),
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
      color: _kSurface,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
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
    required this.mapController,
    required this.userPosition,
    required this.loading,
    required this.onLocateTap,
  });
  final MapController mapController;
  final Position? userPosition;
  final bool loading;
  final VoidCallback onLocateTap;

  void _zoom(double delta) {
    final camera = mapController.camera;
    final next = (camera.zoom + delta).clamp(2.0, 18.0);
    mapController.move(camera.center, next);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _zoomBtn(icon: Icons.add_rounded, onTap: () => _zoom(1)),
      const SizedBox(height: 8),
      _zoomBtn(icon: Icons.remove_rounded, onTap: () => _zoom(-1)),
      const SizedBox(height: 12),
      _LocationFab(
        userPosition: userPosition,
        loading: loading,
        onTap: onLocateTap,
      ),
    ],
  );

  Widget _zoomBtn({required IconData icon, required VoidCallback onTap}) =>
      Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            width: 40,
            height: 40,
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
            child: Icon(icon, size: 20, color: _kInkMuted),
          ),
        ),
      );
}

// ── Cluster bubble — groups screen-close pins so they don't visually
// overlap when the map is zoomed out (e.g. after Fit All spans a wide
// area). Tapping it zooms in, per flutter_map_marker_cluster's default. ──
class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: _kAccent,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: [
        BoxShadow(
          color: _kAccent.withValues(alpha: 0.45),
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
    child: Center(
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
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
