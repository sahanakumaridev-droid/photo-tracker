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
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/map_tiles.dart';
import '../../../core/utils/attempt_status.dart';
import '../../../core/utils/profile_lifecycle.dart';
import '../../../core/utils/category.dart';
import '../../../core/utils/location_service.dart';
import '../../../core/utils/maps_launcher.dart';
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
import 'photo_detail_screen.dart';
import '../upload/attempt_limits.dart';
import '../upload/resume_attempt_screen.dart';
import '../../../core/mileage/mileage_tracker.dart';
import '../../../core/network/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/create_profile_dialog.dart';

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

/// Camera limit covering CONUS, Alaska, Hawaii, and Puerto Rico.
final LatLngBounds _kUsaCameraBounds = LatLngBounds(
  const LatLng(17.8, -179.5),
  const LatLng(71.6, -65.2),
);

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

  bool get isHotRoute =>
      profile != null && (profile!.deliveryStyle ?? '').trim().isEmpty;

  bool get diligenceComplete {
    if (profile == null) return false;
    return attemptCount >= attemptCapForProfile(profile);
  }

  bool get hasAttempts =>
      attemptCount > 0 || (profile?.attemptsCount ?? 0) > 0;

  Color get pinColor {
    if (diligenceComplete) return const Color(0xFF16A34A);
    if (hasAttempts) return _kPending;
    return const Color(0xFFEA580C);
  }

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
  StreamSubscription<Position>? _locSub;
  bool _followUser = false;
  double _userHeading = 0;
  bool _hasHeading = false;
  List<LatLng> _lastPinPoints = const [];
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
  /// The first view is Close: 500 ft across, centered on the user.
  void _onMapReady() {
    _followUser = true;
    _fetchUserLocation(moveCamera: true);
    _startWatching();
  }

  void _startWatching() {
    _locSub ??= LocationService.watchMapLocation().listen(_onLiveGps);
  }

  void _onLiveGps(Position pos) {
    if (!mounted) return;
    if (pos.heading.isFinite && pos.heading >= 0) {
      _userHeading = pos.heading;
      _hasHeading = true;
    }
    setState(() => _userPosition = pos);
    if (!_followUser) return;
    try {
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        _mapController.camera.zoom,
      );
    } catch (_) {}
  }

  bool _closeAfterFetch = false;

  Future<void> _fetchUserLocation({bool moveCamera = false}) async {
    if (moveCamera) {
      _closeAfterFetch = true;
      ref.invalidate(photosProvider);
      ref.invalidate(profilesProvider);
    }
    if (_fetchingLocation) return;
    setState(() => _fetchingLocation = true);
    try {
      final pos = await LocationService.getCurrentLocation();
      if (pos != null && mounted) {
        setState(() => _userPosition = pos);
        if (_closeAfterFetch) {
          _closeAfterFetch = false;
          _fitCloseToUser(pos);
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
    _locSub?.cancel();
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
    _fetchUserLocation(moveCamera: false);
  }

  /// Close: street-level zoom so the user's current location marker and
  /// surrounding 500-ft area are clearly visible.
  void _fitCloseToUser(Position pos) {
    if (!_mapHasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitCloseToUser(pos);
      });
      return;
    }
    final widthPx = _mapController.camera.size.x;
    final cosLat =
        math.cos(pos.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
    const feetAcross = 900.0;
    const ftPerDegLat = 364000.0;
    final degAcross = feetAcross / (ftPerDegLat * cosLat);
    final zoom = (math.log(360 * widthPx / (256 * degAcross)) / math.ln2)
        .clamp(17.2, 18.5);
    _mapController.move(LatLng(pos.latitude, pos.longitude), zoom);
  }

  void _fitAll(List<LatLng> points) {
    if (!_mapHasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAll(points);
      });
      return;
    }

    var core = [
      for (final p in points)
        if (p.latitude.abs() > 0.0001 &&
            p.longitude.abs() > 0.0001 &&
            LocationService.isInUnitedStates(p.latitude, p.longitude))
          p,
    ];
    if (core.isEmpty) {
      if (_userPosition != null) {
        _fitCloseToUser(_userPosition!);
      } else {
        _mapController.move(const LatLng(32.7157, -117.1611), 10);
      }
      return;
    }

    // Cluster around the jobs themselves, not GPS. Locate me is the
    // street-level view; Fit all is the metro job map.
    if (core.length > 2) {
      final lats = core.map((p) => p.latitude).toList()..sort();
      final lngs = core.map((p) => p.longitude).toList()..sort();
      final midLat = lats[lats.length ~/ 2];
      final midLng = lngs[lngs.length ~/ 2];
      final clustered = [
        for (final p in core)
          if (LocationService.calculateDistance(
                      midLat, midLng, p.latitude, p.longitude) *
                  0.621371 <=
              80)
            p,
      ];
      if (clustered.isNotEmpty) core = clustered;
    }

    var minLat = core.first.latitude;
    var maxLat = core.first.latitude;
    var minLng = core.first.longitude;
    var maxLng = core.first.longitude;
    for (final p in core) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Never collapse to a few city blocks. Fit all stays a metro window.
    const minSpanDeg = 0.22;
    if (maxLat - minLat < minSpanDeg) {
      final mid = (minLat + maxLat) / 2;
      minLat = mid - minSpanDeg / 2;
      maxLat = mid + minSpanDeg / 2;
    }
    if (maxLng - minLng < minSpanDeg) {
      final mid = (minLng + maxLng) / 2;
      minLng = mid - minSpanDeg / 2;
      maxLng = mid + minSpanDeg / 2;
    }

    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: EdgeInsets.fromLTRB(20, topInset + 72, 20, bottomInset + 88),
        maxZoom: 12,
      ),
    );
  }

  /// Default window: my GPS + the closest job pin, same viewport.
  void _fitMeAndNearest(List<LatLng> points) {
    if (!mounted) return;
    if (points.isNotEmpty) _lastPinPoints = List<LatLng>.from(points);
    if (!_mapHasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitMeAndNearest(points);
      });
      return;
    }
    final user = _userPosition;
    final pins = _mainClusterPoints(points.isEmpty ? _lastPinPoints : points);
    if (user == null) {
      _fitAll(pins);
      return;
    }
    if (pins.isEmpty) {
      _fitCloseToUser(user);
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

  // Pins farther than this from the user (or San Diego if GPS is missing)
  // are ignored by Fit all so a stray job cannot yank the camera.
  static const double _outlierThresholdMi = 40;

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
    final originLat = _userPosition?.latitude ?? 32.7157;
    final originLng = _userPosition?.longitude ?? -117.1611;

    final core = base.where((p) {
      final km = LocationService.calculateDistance(
          originLat, originLng, p.latitude, p.longitude);
      return km * 0.621371 <= _outlierThresholdMi;
    }).toList();

    return core;
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
        userHeading: _userHeading,
        hasHeading: _hasHeading,
        followingUser: _followUser,
        fetchingLocation: _fetchingLocation,
        locationAttemptDone: _locationAttemptDone,
        onMapReady: _onMapReady,
        onFitAll: (pts) {
          _followUser = false;
          _fitAll(pts);
        },
        onFitClose: () {
          final pos = _userPosition;
          if (pos != null) _fitCloseToUser(pos);
        },
        onFitMeAndNearest: _fitMeAndNearest,
        onRefresh: _refresh,
        onUserPanned: () {
          if (_followUser && mounted) setState(() => _followUser = false);
        },
        onMyLocation: () async {
          setState(() => _followUser = true);
          if (_userPosition != null) {
            _fitCloseToUser(_userPosition!);
          }
          _startWatching();
          await _fetchUserLocation(moveCamera: true);
        },
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
    required this.onFitClose,
    required this.onFitMeAndNearest,
    required this.onRefresh,
    required this.onMyLocation,
    required this.onUserPanned,
    this.userPosition,
    this.userHeading = 0,
    this.hasHeading = false,
    this.followingUser = false,
    this.fetchingLocation = false,
    this.locationAttemptDone = false,
  });

  final List<PhotoModel>               photos;
  final TextEditingController          searchCtrl;
  final MapController                  mapController;
  final VoidCallback                   onMapReady;
  final ValueChanged<List<LatLng>> onFitAll;
  final VoidCallback onFitClose;
  final ValueChanged<List<LatLng>> onFitMeAndNearest;
  final VoidCallback                   onRefresh;
  final VoidCallback                   onMyLocation;
  final VoidCallback                   onUserPanned;
  final Position?                      userPosition;
  final double                         userHeading;
  final bool                           hasHeading;
  final bool                           followingUser;
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
  final int _fittedCount = -1;
  bool _fittedWithGps = false;
  final bool _showedNearbyPins = false;
  bool _userPinnedCamera = false;
  bool _glowNearby = false;
  // Distance filter — a radius from the user (0–100 mi).
  double _distanceMi = 100;
  String? _distanceMode; // 'distance' | null
  // Debounces the camera fit while the distance slider is being dragged, so
  // it flies once the user settles instead of on every intermediate tick.
  Timer? _filterFitDebounce;
  _MapJob? _selectedJob;
  int? _focusProfileId;
  LatLng? _hotRouteAt;
  int _hotRouteShiftGen = 0;
  DateTime? _usaSnackAt;
  LatLng _lastUsaCenter = const LatLng(32.7157, -117.1611);
  bool _clampingUsa = false;
  Timer? _usaClampTimer;
  Timer? _searchFly;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    widget.searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
    _searchFly?.cancel();
    final q = _placeQuery(widget.searchCtrl.text);
    if (q.length < 3) return;
    _userPinnedCamera = true;
    _searchFly = Timer(const Duration(milliseconds: 450), () {
      unawaited(_flyToSpokenPlace(q));
    });
  }

  /// "Take me to Union Square." → "union square"
  String _placeQuery(String raw) {
    var q = raw.trim().toLowerCase();
    q = q.replaceAll(RegExp(r'[.?!,"]+'), ' ');
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    q = q.replaceFirst(
      RegExp(
        r'^(please\s+)?(can you\s+|could you\s+)?'
        r'(take me to|take me|go to|navigate to|show me|find me|'
        r'look up|search for|search|find|locate|where is|zoom to)\s+',
      ),
      '',
    );
    return q.trim();
  }

  void _moveTo(LatLng pin) {
    _userPinnedCamera = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        widget.mapController.move(pin, 16);
      } catch (_) {}
    });
  }

  Future<void> _flyToSpokenPlace(String query) async {
    final token = ++_searchToken;
    final q = _placeQuery(query);
    if (q.length < 3) return;
    for (final job in _mapJobs()) {
      final name = job.recipient.toLowerCase();
      if (name.length < 3 || !job.hasPoint) continue;
      final named = name == q || name.startsWith('$q ') || q.startsWith('$name ');
      if (!named) continue;
      if (!mounted || token != _searchToken) return;
      _moveTo(LatLng(job.lat, job.lng));
      return;
    }
    final hit = await LocationService.searchPlace(q);
    if (!mounted || token != _searchToken) return;
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find that place in the United States.'),
        ),
      );
      return;
    }
    _moveTo(LatLng(hit.lat, hit.lng));
  }

  void _showUsaOnlySnack() {
    final now = DateTime.now();
    if (_usaSnackAt != null &&
        now.difference(_usaSnackAt!) < const Duration(seconds: 2)) {
      return;
    }
    _usaSnackAt = now;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Only USA'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onMapPositionChanged(MapPosition pos, bool hasGesture) {
    final center = pos.center;
    if (center == null) return;
    if (LocationService.isInUnitedStates(center.latitude, center.longitude)) {
      _lastUsaCenter = center;
      if (hasGesture) {
        widget.onUserPanned();
      }
      return;
    }
    // Layout/maxBounds can fire this without a gesture. Moving the camera
    // then (or during the hot-route overlay) leaves InheritedWidgets with
    // dependents and crashes: `_dependents.isEmpty`.
    if (!hasGesture || _hotRouteAt != null || _clampingUsa) return;
    _showUsaOnlySnack();
    _clampingUsa = true;
    final zoom = (pos.zoom ?? 13).clamp(4.0, 18.0);
    final target = _lastUsaCenter;
    _usaClampTimer?.cancel();
    _usaClampTimer = Timer(Duration.zero, () {
      _clampingUsa = false;
      if (!mounted || _hotRouteAt != null) return;
      try {
        widget.mapController.move(target, zoom);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_onSearchChanged);
    _filterFitDebounce?.cancel();
    _usaClampTimer?.cancel();
    _searchFly?.cancel();
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
        'stake_out' => 'Surveillance-style jobs that sit on a location.',
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

  Future<bool> _gpsIsOnSite(
    BuildContext context,
    double jobLat,
    double jobLng, {
    bool notify = true,
  }) async {
    final gps = await LocationService.getFreshFix() ??
        await LocationService.getLastKnownLocation();
    if (!context.mounted) return false;
    if (gps == null) {
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read GPS for this attempt.')),
        );
      }
      return false;
    }
    final err = LocationService.attemptTooFarMessage(
      gpsLat: gps.latitude,
      gpsLng: gps.longitude,
      jobLat: jobLat,
      jobLng: jobLng,
      gpsAccuracyMeters: gps.accuracy,
    );
    if (err != null) {
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
      return false;
    }
    return true;
  }

  Future<void> _openAttemptFromGps(double lat, double lng) async {
    final profiles = ref.read(profilesProvider).valueOrNull ?? [];
    ProfileModel? nearest;
    var nearestFt = LocationService.kAttemptProximityFt;
    for (final p in profiles) {
      if (!p.hasLocation) continue;
      final d = LocationService.distanceFeet(lat, lng, p.latitude!, p.longitude!);
      if (d <= nearestFt) {
        nearestFt = d;
        nearest = p;
      }
    }
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeAttemptScreen(
          initialProfileId: nearest?.id,
          initialProfile: nearest,
        ),
      ),
    );
    widget.onRefresh();
  }

  void _openHotRouteBubbles(LatLng latLng) {
    if (!LocationService.isInUnitedStates(latLng.latitude, latLng.longitude)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hot routes can only be added in the United States.'),
        ),
      );
      return;
    }
    _userPinnedCamera = true;
    setState(() {
      _selectedJob = null;
      _hotRouteAt = latLng;
    });
    // One nudge only. Repeating it sends the pin away from the tap.
    // A corner tap needs the point pulled in just far enough for the menu.
    final generation = ++_hotRouteShiftGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _hotRouteShiftGen) return;
      final camera = widget.mapController.camera;
      final screen = camera.latLngToScreenPoint(latLng);
      final size = camera.size;
      const marginX = 150.0;
      const marginTop = 190.0;
      const marginBottom = 200.0;
      if (size.x < 32 || size.y < 32) return;
      final targetX =
          screen.x.clamp(marginX, math.max(marginX, size.x - marginX));
      final targetY = screen.y.clamp(
        marginTop,
        math.max(marginTop, size.y - marginBottom),
      );
      final dx = screen.x - targetX;
      final dy = screen.y - targetY;
      if (dx.abs() <= 2 && dy.abs() <= 2) return;
      final centerPx = camera.latLngToScreenPoint(camera.center);
      final shifted = camera.pointToLatLng(
        math.Point(centerPx.x + dx, centerPx.y + dy),
      );
      widget.mapController.move(shifted, camera.zoom);
    });
  }

  bool _attemptInRange(LatLng pin) {
    final gps = widget.userPosition;
    if (gps == null) return false;
    return LocationService.distanceFeet(
          gps.latitude,
          gps.longitude,
          pin.latitude,
          pin.longitude,
        ) <=
        LocationService.kAttemptProximityFt;
  }

  Offset _screenOffsetFor(LatLng latLng) {
    try {
      final p = widget.mapController.camera.latLngToScreenPoint(latLng);
      return Offset(p.x, p.y);
    } catch (_) {
      return Offset.zero;
    }
  }

  Future<void> _openAttemptForProfile(ProfileModel created) async {
    widget.onRefresh();
    if (!mounted || created.id == 0) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeAttemptScreen(
          initialProfileId: created.id,
          initialProfile: created,
        ),
      ),
    );
  }

  Future<void> _onHotRouteChoice(String choice, LatLng latLng) async {
    setState(() => _hotRouteAt = null);
    if (choice == 'hot') {
      if (!LocationService.isInUnitedStates(
          latLng.latitude, latLng.longitude)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A hot route can only be created in the United States.'),
          ),
        );
        return;
      }
      String? address;
      try {
        address = await LocationService.reverseGeocode(
          latLng.latitude,
          latLng.longitude,
        );
      } catch (_) {}
      if (!context.mounted) return;
      final created = await showCreateProfileDialog(
        context,
        latitude: latLng.latitude,
        longitude: latLng.longitude,
        address: address,
        hotRoute: true,
      );
      if (created != null) {
        final pinLat = created.latitude ?? latLng.latitude;
        final pinLng = created.longitude ?? latLng.longitude;
        _focusProfileId = created.id;
        widget.onRefresh();
        widget.mapController.move(LatLng(pinLat, pinLng), 17);
      }
      return;
    }
    if (choice == 'attempt') {
      final gps = widget.userPosition;
      if (gps == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turn on location to add an attempt.')),
        );
        return;
      }
      setState(() => _glowNearby = true);
      _pullCameraToRadius();
      var eligible = 0;
      var completeNearby = false;
      for (final job in _mapJobs()) {
        if (!job.hasPoint || job.profile == null) continue;
        if (!_inAttemptRange(job)) continue;
        if (!_jobAcceptsAttempt(job)) {
          completeNearby = true;
          continue;
        }
        eligible++;
      }
      if (eligible == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completeNearby
                  ? 'Nearby green pins are already complete. Use a yellow or orange pin within 500 ft.'
                  : 'Move within 500 feet of a profile, then tap Attempt again.',
            ),
          ),
        );
      }
      return;
    }
    if (choice == 'camera') {
      try {
        await ImagePicker().pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
          preferredCameraDevice: CameraDevice.rear,
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the camera.')),
          );
        }
      }
      return;
    }
    if (choice == 'mileage') {
      final container = ProviderScope.containerOf(context);
      final dio = container.read(dioProvider);
      final email = container.read(authProvider).email;
      await MileageTracker.instance.toggle(dio, email: email);
    }
  }

  // Filter sheet: same dock categories (with details) plus distance.
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
    // Pins with attempts stay yellow (or green if complete) even when tapped.
    // Only first-time orange pins use the selected/map-card highlight.
    final selected = !job.hasAttempts && _isSelectedJob(job);
    final glow =
        _glowNearby && _inAttemptRange(job) && _jobAcceptsAttempt(job);
    return Marker(
      point: _spreadPoint(job, all),
      width: glow ? 56 : 48,
      height: glow ? 68 : 58,
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          unawaited(_openJobFromPin(job));
        },
        child: _PinMarker(
          color: job.pinColor,
          selected: selected,
          glow: glow,
          label: null,
        ),
      ),
    );
  }

  /// Prefer a pin tap over the empty-map hot-wheel. Stacked jobs sit on the
  /// GPS puck, so flutter_map often delivers the tap to the map instead.
  _MapJob? _jobNearTap(LatLng tap, List<_MapJob> jobs) {
    final tapPx = _screenOffsetFor(tap);
    if (tapPx == Offset.zero && jobs.isEmpty) return null;
    _MapJob? best;
    var bestPx = 56.0;
    for (final job in jobs) {
      if (!job.hasPoint) continue;
      final pinPx = _screenOffsetFor(_spreadPoint(job, jobs));
      final d = (pinPx - tapPx).distance;
      if (d < bestPx) {
        bestPx = d;
        best = job;
      }
    }
    return best;
  }

  bool _inAttemptRange(_MapJob job) {
    final gps = widget.userPosition;
    if (gps == null || !job.hasPoint) return false;
    return LocationService.distanceFeet(
          gps.latitude,
          gps.longitude,
          job.lat,
          job.lng,
        ) <=
        LocationService.kAttemptProximityFt;
  }

  /// Green / completed / archived pins cannot take a new attempt.
  bool _jobAcceptsAttempt(_MapJob job) {
    if (job.diligenceComplete) return false;
    final profile = job.profile;
    if (profile != null && !profile.canAddAttempts) return false;
    return true;
  }

  void _pullCameraToRadius() {
    final gps = widget.userPosition;
    if (gps == null) return;
    const meters = 152.4;
    const dLat = meters / 111320;
    final dLng =
        meters / (111320 * math.cos(gps.latitude * math.pi / 180).abs());
    _userPinnedCamera = true;
    widget.mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(gps.latitude - dLat, gps.longitude - dLng),
          LatLng(gps.latitude + dLat, gps.longitude + dLng),
        ),
        padding: const EdgeInsets.fromLTRB(36, 150, 36, 160),
        maxZoom: 18,
      ),
    );
    if (mounted) setState(() {});
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
    // ~20 m base so stacked jobs stay near the real address (the old 250 m
    // ring put the pin outside the 500 ft attempt radius).
    final d = 0.00032 + n * 0.00005;
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

  PhotoModel? _photoForJob(_MapJob job) {
    if (job.photos.isNotEmpty) return job.photos.first;
    final pid = job.profile?.id ?? job.latest?.profileId;
    if (pid == null || pid == 0) return job.latest;
    final all = ref.read(photosProvider).valueOrNull ?? const <PhotoModel>[];
    final matches = all
        .where((ph) =>
            ph.profileId == pid ||
            (ph.profiles?.any((p) => p.id == pid) ?? false))
        .toList()
      ..sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _openJobFromPin(_MapJob job) async {
    if (!mounted) return;
    // Attempt on the hot wheel: only glowing pins within 500 ft open
    // Add Attempt. Regular pin taps still go to the photo screen.
    if (_glowNearby) {
      if (_inAttemptRange(job) && _jobAcceptsAttempt(job)) {
        await _startAttemptFromPin(context, job: job);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pick a glowing pin within 500 feet to add an attempt.',
          ),
        ),
      );
      return;
    }
    final photo = _photoForJob(job);
    final pid = job.profile?.id ??
        job.latest?.profileId ??
        photo?.profileId;
    // Yellow / green pins with an attempt open the attempt photo screen,
    // not the Service Attempts list.
    if (job.hasAttempts) {
      var photoId = (photo != null && photo.id != 0) ? photo.id : 0;
      if (photoId == 0 && pid != null && pid != 0) {
        final attempts =
            ref.read(profileAttemptsProvider(pid)).valueOrNull;
        if (attempts != null && attempts.isNotEmpty) {
          photoId = attempts.first.photoId;
        }
      }
      if (photoId != 0) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoDetailScreen(photoId: photoId),
          ),
        );
        return;
      }
      setState(() => _selectedJob = job);
      return;
    }
    setState(() => _selectedJob = job);
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
    final gps = widget.userPosition;
    if (gps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on location to add an attempt.')),
      );
      return;
    }
    final feet = LocationService.distanceFeet(
      gps.latitude,
      gps.longitude,
      selected.lat,
      selected.lng,
    );
    if (feet > LocationService.kAttemptProximityFt) {
      setState(() => _glowNearby = true);
      _pullCameraToRadius();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You are ${feet.round()} ft from this pin. An attempt is only allowed within 500 feet, and it uses your current location.',
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
    if (mounted) setState(() => _glowNearby = false);
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

  String _latestJobLabel(List<_MapJob> jobs) {
    _MapJob? latest;
    for (final job in jobs) {
      if (latest == null) {
        latest = job;
        continue;
      }
      final stamp = job.latest?.timestamp ?? '';
      final other = latest.latest?.timestamp ?? '';
      if (stamp.compareTo(other) > 0) {
        latest = job;
      } else if (stamp == other &&
          (job.profile?.id ?? 0) > (latest.profile?.id ?? 0)) {
        latest = job;
      }
    }
    if (latest == null) return 'No recent profile';
    final hot = (latest.profile?.deliveryStyle ?? '').trim().isEmpty &&
        latest.profile != null;
    return hot ? '${latest.recipient}\nHot route' : latest.recipient;
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
            !_levels.contains(profile.serviceType.toLowerCase())) {
          continue;
        }
        if (!profile.hasLocation) continue;
        if (!_profilePassesDistanceAndSearch(profile)) continue;
      }
      final job = _MapJob(profile: profile, photos: pPhotos);
      if (job.hasPoint &&
          LocationService.isInUnitedStates(job.lat, job.lng)) {
        jobs.add(job);
      }
    }

    final leftover = photos.where((p) => !used.contains(p.id)).toList();
    for (final g in _groupByLocation(leftover).values) {
      g.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
      final job = _MapJob(profile: null, photos: g);
      if (job.hasPoint &&
          LocationService.isInUnitedStates(job.lat, job.lng)) {
        jobs.add(job);
      }
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
    final open = [
      for (final j in jobs)
        if (j.profile == null || j.profile!.canAddAttempts) j,
    ];
    if (open.isEmpty) return const SizedBox.shrink();

    const sd = LatLng(32.7157, -117.1611);
    final pos = widget.userPosition;
    final originLat = pos?.latitude ?? sd.latitude;
    final originLng = pos?.longitude ?? sd.longitude;

    _MapJob next = open.first;
    var best = double.infinity;
    for (final j in open) {
      if (!j.hasPoint) continue;
      final d = Geolocator.distanceBetween(
        originLat, originLng, j.lat, j.lng,
      );
      if (d < best) {
        best = d;
        next = j;
      }
    }

    final name = next.recipient;
    double? miles;
    if (next.hasPoint) {
      miles = best.isFinite ? best / 1609.34 : null;
    }

    final dist = miles == null
        ? null
        : miles < 0.1
            ? 'Nearby'
            : miles < 10
                ? '${miles.toStringAsFixed(1)} mi'
                : '${miles.round()} mi';
    final pay = next.profile?.payRate;
    final jobLine = (next.profile?.displayCompanyName ?? next.address).trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          unawaited(_openJobFromPin(next));
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  size: 18, color: _kAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        'Next up',
                        name,
                        if (dist != null) dist,
                        if (pay != null) '\$$pay',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                      ),
                    ),
                    if (miles != null || jobLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (miles != null)
                            miles < 0.1
                                ? 'Nearby'
                                : '${miles.toStringAsFixed(1)} mi away',
                          if (jobLine.isNotEmpty) jobLine,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _kInkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: _kSubtle),
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
    final focusId = _focusProfileId;
    if (focusId != null) {
      for (final job in jobs) {
        if (job.profile?.id == focusId &&
            _selectedJob?.profile?.id != focusId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _focusProfileId != focusId) return;
            setState(() {
              _selectedJob = job;
              _focusProfileId = null;
            });
            widget.mapController.move(job.point, 17);
          });
          break;
        }
      }
    }

    if (!_userPinnedCamera && !_fittedWithGps) {
      final pos = widget.userPosition;
      if (pos != null) {
        _fittedWithGps = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _userPinnedCamera) return;
          _userPinnedCamera = true;
          widget.onFitClose();
        });
      }
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
              initialCenter: widget.userPosition != null
                  ? LatLng(
                      widget.userPosition!.latitude,
                      widget.userPosition!.longitude,
                    )
                  : const LatLng(39.8, -98.6),
              initialZoom: widget.userPosition != null ? 17.5 : 5,
              minZoom: 4,
              maxZoom: 19,
              // contain keeps the whole screen inside the US. containCenter
              // only holds the center, which still shows Europe and Asia.
              cameraConstraint: CameraConstraint.containCenter(
                bounds: _kUsaCameraBounds,
              ),
              keepAlive: false,
              interactionOptions: InteractionOptions(
                flags: _hotRouteAt != null
                    ? InteractiveFlag.none
                    : InteractiveFlag.all,
              ),
              backgroundColor: const Color(0xFFF2F4F7),
              onMapReady: widget.onMapReady,
              onPositionChanged: _onMapPositionChanged,
              onTap: _selectedJob != null || _hotRouteAt != null
                  ? null
                  : (_, latLng) {
                      final hit = _jobNearTap(latLng, jobs);
                      if (hit != null) {
                        HapticFeedback.mediumImpact();
                        unawaited(_openJobFromPin(hit));
                        return;
                      }
                      HapticFeedback.lightImpact();
                      _openHotRouteBubbles(latLng);
                    },
              onLongPress: (_, latLng) {
                HapticFeedback.mediumImpact();
                _openHotRouteBubbles(latLng);
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
            if (widget.userPosition != null) ...[
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(
                      widget.userPosition!.latitude,
                      widget.userPosition!.longitude,
                    ),
                    // GPS accuracy only — grows on zoom-in like Google Maps,
                    // never the old 500-ft radar.
                    radius: widget.userPosition!.accuracy.clamp(8.0, 28.0),
                    useRadiusInMeter: true,
                    color: const Color(0xFF4285F4).withValues(alpha: 0.18),
                    borderStrokeWidth: 0,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      widget.userPosition!.latitude,
                      widget.userPosition!.longitude,
                    ),
                    width: 92,
                    height: 92,
                    child: IgnorePointer(
                      child: _GoogleBlueDot(
                        headingDeg: widget.userHeading,
                        showCone: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // New profiles and hot routes are orange. In-progress jobs stay
            // yellow until diligence is complete, then the pin turns green.
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
                  const SizedBox(width: 10),
                  const AiSparkButton(),
                ],
              ),
              _nextUpChip(jobs),
            ],
          ),
        ),

        // ── Map FABs: fit / close / filter / mileage ───────────────────
        Positioned(
          right: 14,
          bottom: _selectedJob != null ? 380 : 108,
          child: Material(
            color: Colors.transparent,
            child: _ZoomControls(
              onFitTap: () {
                _userPinnedCamera = true;
                widget.onFitAll(jobs.map((j) => j.point).toList());
              },
              userPosition: widget.userPosition,
              followingUser: widget.followingUser,
              loading: widget.fetchingLocation,
              filterActive:
                  _todayOnly || _distanceMode != null || _levels.isNotEmpty,
              onFilterTap: _showFilterSheet,
              onLocateTap: () {
                HapticFeedback.lightImpact();
                _userPinnedCamera = true;
                widget.onMyLocation();
              },
            ),
          ),
        ),

        if (_hotRouteAt != null)
          Positioned.fill(
            child: ListenableBuilder(
              listenable: MileageTracker.instance,
              builder: (context, _) => _HotRouteBubbles(
                origin: _screenOffsetFor(_hotRouteAt!),
                mileageOn: MileageTracker.instance.tracking,
                attemptEnabled: _attemptInRange(_hotRouteAt!),
                centerLabel: _latestJobLabel(jobs),
                onDismiss: () => setState(() => _hotRouteAt = null),
                onChoice: (choice) =>
                    unawaited(_onHotRouteChoice(choice, _hotRouteAt!)),
              ),
            ),
          ),

        // Pin card last so map, dock, and FABs cannot steal button taps.
        if (_selectedJob != null)
          Positioned(
            left: 14,
            right: 14,
            bottom: 100,
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
                  lat: _selectedJob!.lat,
                  lng: _selectedJob!.lng,
                  title: _selectedJob!.pinSummaryTitle,
                  pending: _selectedJob!.isPending,
                  attemptEnabled: _inAttemptRange(_selectedJob!),
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

