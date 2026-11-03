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

part 'map_view_filter_sheet.dart';
part 'map_view_jobs_and_pins.dart';
part 'map_view_overlays.dart';
part 'map_view_markers.dart';

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
  void _rebuild([VoidCallback? fn]) => setState(fn ?? () {});

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
