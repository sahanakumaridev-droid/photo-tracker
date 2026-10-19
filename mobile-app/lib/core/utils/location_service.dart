import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'constants.dart';
import 'logger.dart';

/// Accuracy threshold in metres — positions worse than this trigger a retry.
const _kAccuracyThreshold = 50.0;

/// Minimum number of stabilisation samples before we accept a GPS fix.
const _kStabilitySamples = 3;

/// How many times to retry a fresh GPS fix before giving up.
const _kMaxRetries = 3;

class LocationService {
  factory LocationService() => _instance;
  LocationService._internal();
  static final LocationService _instance = LocationService._internal();

  // ── Permission ────────────────────────────────────────────────────────────

  /// Request location permissions. Returns true when granted.
  static Future<bool> requestLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      debugPrint('[Location] Permission permanently denied');
      return false;
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  // ── Current position ──────────────────────────────────────────────────────

  /// Get the best available current position.
  ///
  /// Strategy:
  ///   1. Check permission + service enabled.
  ///   2. Fetch a fresh high-accuracy fix (up to [_kMaxRetries] attempts).
  ///   3. Wait for GPS to stabilise before returning.
  ///   4. If accuracy is still poor, return the best we got rather than null.
  static Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        debugPrint('[Location] No permission');
        return null;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[Location] Services disabled');
        return null;
      }

      Position? best;

      for (var attempt = 1; attempt <= _kMaxRetries; attempt++) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 15 + attempt * 5),
          );
          _logGpsSample('gps_fix_attempt_$attempt', pos);

          // Keep the most accurate result seen so far.
          if (best == null || pos.accuracy < best.accuracy) {
            best = pos;
          }

          // Good enough — stop retrying.
          if (pos.accuracy <= _kAccuracyThreshold) break;

          // Wait briefly before retrying so the GPS chip can stabilise.
          if (attempt < _kMaxRetries) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          debugPrint('[Location] attempt $attempt error: $e');
          if (attempt == _kMaxRetries) rethrow;
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      // ── Stabilisation ──────────────────────────────────────────────
      // Wait briefly and take a few more samples to confirm the GPS chip
      // has settled — this prevents the 100–300 ft drift described in QA.
      if (best != null && best.accuracy <= _kAccuracyThreshold) {
        await Future<void>.delayed(const Duration(seconds: 1));
        for (var i = 0; i < _kStabilitySamples; i++) {
          try {
            final sample = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.bestForNavigation,
              timeLimit: const Duration(seconds: 8),
            );
            _logGpsSample('stability_sample_${i + 1}', sample);
            if (sample.accuracy < best!.accuracy) best = sample;
            await Future<void>.delayed(const Duration(milliseconds: 500));
          } catch (_) {
            // Stability samples are best-effort — ignore errors.
          }
        }
      }

      if (best != null) _logGpsSample('gps_final', best);
      return best;
    } catch (e) {
      debugPrint('[Location] error: $e');
      return null;
    }
  }

  /// Instant, best-effort location straight from the OS cache. Used to centre
  /// the map the moment it opens — before the slower, high-accuracy
  /// [getCurrentLocation] fix lands. Returns null if there's no cached fix or
  /// no permission yet (the accurate fetch then handles centring once it
  /// resolves). Deliberately does NOT trigger a permission prompt or any GPS
  /// hardware wake — it must return immediately.
  static Future<Position?> getLastKnownLocation() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint('[Location] last-known error: $e');
      return null;
    }
  }

  /// One GPS read for attempt logging — no 3-retry / stabilize loop.
  /// Last-known is used only if it is fresher than 3 minutes.
  static Future<Position?> getFreshFix({
    Duration timeLimit = const Duration(seconds: 12),
  }) async {
    final hasPermission = await requestLocationPermission();
    if (!hasPermission) return null;
    final on = await Geolocator.isLocationServiceEnabled();
    if (!on) return null;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: timeLimit,
      );
      _logGpsSample('fresh_fix', pos);
      return pos;
    } catch (e) {
      debugPrint('[Location] fresh fix error: $e');
      final last = await getLastKnownLocation();
      if (last == null) return null;
      final age = DateTime.now().difference(last.timestamp);
      if (age > const Duration(minutes: 3)) {
        debugPrint('[Location] ignoring stale last-known (${age.inSeconds}s)');
        return null;
      }
      return last;
    }
  }

  // ── Watch stream ──────────────────────────────────────────────────────────

  /// Stream of position updates. Uses high accuracy + 10 m distance filter.
  static Stream<Position> watchLocation() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 10,
        ),
      );

  /// Frequent stream for the live Google-style map puck (walk/drive).
  static Stream<Position> watchMapLocation() {
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 1,
        pauseLocationUpdatesAutomatically: false,
      );
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(milliseconds: 800),
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  // ── Reverse geocoding ─────────────────────────────────────────────────────

  /// Reverse geocode [latitude]/[longitude] via Nominatim.
  /// Returns a human-readable address string with ZIP inline at the end.
  /// Address format: "123 Main St, Dallas, TX 75001"
  ///
  /// Uses a cache-busting timestamp to prevent stale results from being
  /// reused by the HTTP client or any intermediate proxy.
  static Future<String?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    final dio = Dio();
    final startTime = DateTime.now();

    try {
      _logGeocodeRequest(latitude, longitude);

      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/reverse',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'format': 'jsonv2',
          'addressdetails': 1,
          'extratags': 1,
          'zoom': 18,
          'accept-language': 'en',
          '_t': DateTime.now().millisecondsSinceEpoch,
        },
        options: Options(
          headers: {
            'User-Agent':
                'GeoTaggingApp/1.0 (contact: support@photo-tracker.app)',
            'Cache-Control': 'no-cache, no-store',
            'Pragma': 'no-cache',
          },
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      final elapsedMs =
          DateTime.now().difference(startTime).inMilliseconds;

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;

        if (addr == null) {
          _logGeocodeResult(latitude, longitude, null, elapsedMs, 'no_address');
          return null;
        }

        final address = _buildAddress(addr);
        final county = nominatimCounty(addr);
        String? labeled = address;
        if (county != null &&
            (labeled == null ||
                !labeled.toLowerCase().contains(county.toLowerCase()))) {
          labeled = labeled == null ? county : '$labeled, $county';
        }
        _logGeocodeResult(latitude, longitude, labeled, elapsedMs, 'ok');
        return labeled;
      }

      _logGeocodeResult(
          latitude, longitude, null, elapsedMs, 'status_${response.statusCode}');
      return null;
    } catch (e) {
      final elapsedMs =
          DateTime.now().difference(startTime).inMilliseconds;
      _logGeocodeResult(latitude, longitude, null, elapsedMs, 'error_$e');
      return null;
    }
  }

  /// Reverse geocode [latitude]/[longitude] into discrete Street/City/State/
  /// ZIP fields, for callers with their own structured address form (e.g. a
  /// Profile Location card) rather than a single joined display string.
  /// Returns all-null fields if the lookup fails.
  static Future<({
    String? street,
    String? city,
    String? state,
    String? zip,
    String? county,
  })> reverseGeocodeDetailed(double latitude, double longitude) async {
    final dio = Dio();
    try {
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/reverse',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'format': 'jsonv2',
          'addressdetails': 1,
          'zoom': 18,
          'accept-language': 'en',
          '_t': DateTime.now().millisecondsSinceEpoch,
        },
        options: Options(
          headers: {
            'User-Agent':
                'GeoTaggingApp/1.0 (contact: support@photo-tracker.app)',
            'Cache-Control': 'no-cache, no-store',
            'Pragma': 'no-cache',
          },
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr != null) return _addressComponents(addr);
      }
    } catch (_) {
      // Fall through to the all-null result below — caller keeps whatever
      // it already had (e.g. lat/lng from the map pick still apply).
    }
    return (
      street: null,
      city: null,
      state: null,
      zip: null,
      county: null,
    );
  }

  /// Build a clean, consistently formatted address string.
  /// Format: "123 Main St, San Diego, CA 92101"
  ///
  /// Rules:
  ///   - Street: house_number + road, or just road (most precise)
  ///   - City: prefer city > town > village > municipality
  ///   - State: abbreviation only (e.g. CA, TX) for consistent ZIP pairing
  ///   - ZIP: always inline at the end, never on a separate line
  ///   - County/district is intentionally excluded — it drifts accuracy
  ///     (e.g. returning the county seat instead of the actual location)
  ///   - No duplicates: if a field duplicates the city, skip it
  ///   - No empty/null segments, no trailing commas
  static String? _buildAddress(Map<String, dynamic> addr) {
    final c = _addressComponents(addr);
    final seen = <String>{};
    final parts = <String>[];
    for (final part in [c.street, c.city, c.state, c.zip]) {
      if (part == null || part.isEmpty) continue;
      if (seen.contains(part.toLowerCase())) continue;
      parts.add(part);
      seen.add(part.toLowerCase());
    }
    if (parts.isEmpty) return null;
    return parts.join(', ').replaceAll(RegExp(r',\s*,'), ',').trim();
  }

  /// Extracts street/city/state(abbreviation)/zip from a Nominatim
  /// `address` map — the same fields/priority `_buildAddress` joins into a
  /// single line, kept separate here for callers that need discrete fields
  /// (e.g. a Profile Location form with its own Address/City/State/ZIP
  /// inputs).
  static ({
    String? street,
    String? city,
    String? state,
    String? zip,
    String? county,
  }) _addressComponents(Map<String, dynamic> addr) {
    final houseNumber = addr['house_number'] as String?;
    final road = addr['road'] as String?;
    final street = (road != null && road.isNotEmpty)
        ? (houseNumber != null ? '$houseNumber $road' : road)
        : null;

    final city = (addr['city'] ??
        addr['town'] ??
        addr['village'] ??
        addr['municipality']) as String?;

    var state = addr['ISO3166-2-lvl4'] as String? ?? addr['state_code'] as String?;
    if (state != null && state.contains('-')) {
      state = state.split('-').last;
    }
    if (state == null || state.length != 2) {
      state = stateCode(addr['state'] as String?);
    }

    final zip = addr['postcode'] as String?;
    final county = nominatimCounty(addr);

    return (street: street, city: city, state: state, zip: zip, county: county);
  }

  static String? stateCode(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final trimmed = name.trim();
    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(trimmed)) return trimmed.toUpperCase();
    const codes = {
      'alabama': 'AL',
      'alaska': 'AK',
      'arizona': 'AZ',
      'arkansas': 'AR',
      'california': 'CA',
      'colorado': 'CO',
      'connecticut': 'CT',
      'delaware': 'DE',
      'district of columbia': 'DC',
      'florida': 'FL',
      'georgia': 'GA',
      'hawaii': 'HI',
      'idaho': 'ID',
      'illinois': 'IL',
      'indiana': 'IN',
      'iowa': 'IA',
      'kansas': 'KS',
      'kentucky': 'KY',
      'louisiana': 'LA',
      'maine': 'ME',
      'maryland': 'MD',
      'massachusetts': 'MA',
      'michigan': 'MI',
      'minnesota': 'MN',
      'mississippi': 'MS',
      'missouri': 'MO',
      'montana': 'MT',
      'nebraska': 'NE',
      'nevada': 'NV',
      'new hampshire': 'NH',
      'new jersey': 'NJ',
      'new mexico': 'NM',
      'new york': 'NY',
      'north carolina': 'NC',
      'north dakota': 'ND',
      'ohio': 'OH',
      'oklahoma': 'OK',
      'oregon': 'OR',
      'pennsylvania': 'PA',
      'rhode island': 'RI',
      'south carolina': 'SC',
      'south dakota': 'SD',
      'tennessee': 'TN',
      'texas': 'TX',
      'utah': 'UT',
      'vermont': 'VT',
      'virginia': 'VA',
      'washington': 'WA',
      'west virginia': 'WV',
      'wisconsin': 'WI',
      'wyoming': 'WY',
    };
    return codes[trimmed.toLowerCase()];
  }

  /// Nominatim county / district — used for search, not the display address.
  static String? nominatimCounty(Map<String, dynamic> addr) {
    final raw = (addr['county'] ?? addr['state_district']) as String?;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  // ── Debug logging ────────────────────────────────────────────────────────

  static void _logGpsSample(String label, Position pos) {
    debugPrint(
      '[GPS|$label] '
      'lat=${pos.latitude.toStringAsFixed(8)} '
      'lng=${pos.longitude.toStringAsFixed(8)} '
      'accuracy=${pos.accuracy.toStringAsFixed(1)}m '
      'altitude=${pos.altitude.toStringAsFixed(1)}m '
      'speed=${pos.speed.toStringAsFixed(2)}m/s '
      'heading=${pos.heading.toStringAsFixed(1)}° '
      'ts=${pos.timestamp.toIso8601String()}',
    );
    AppLogger.info(
      '[GPS] $label | '
      'l:${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)} '
      '±${pos.accuracy.toStringAsFixed(0)}m '
      '@${pos.timestamp.toIso8601String()}',
    );
  }

  static void _logGeocodeRequest(double lat, double lng) {
    debugPrint('[Nominatim|REQ] '
        'lat=${lat.toStringAsFixed(8)} lng=${lng.toStringAsFixed(8)}');
    AppLogger.info('[Geocode] request l:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}');
  }

  static void _logGeocodeResult(
    double lat,
    double lng,
    String? address,
    int elapsedMs,
    String status,
  ) {
    debugPrint('[Nominatim|RES] '
        'lat=${lat.toStringAsFixed(8)} lng=${lng.toStringAsFixed(8)} '
        'status=$status elapsed=${elapsedMs}ms '
        'addr="$address"');
    AppLogger.info(
      '[Geocode] result status=$status '
      'l:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)} '
      '=> "$address" '
      '(${elapsedMs}ms)',
    );
  }

  /// Reverse geocode to human-readable address string only.
  static Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    return reverseGeocode(latitude, longitude);
  }

  // ── Forward geocoding ─────────────────────────────────────────────────────

  /// Place name or address → coordinates, limited to the United States.
  static Future<({double lat, double lng})?> searchPlace(String query) async {
    final q = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.length < 3) return null;
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/search',
        queryParameters: {
          'q': q,
          'countrycodes': 'us',
          'format': 'json',
          'limit': 1,
        },
        options: Options(
          headers: {
            'User-Agent':
                'GeoTaggingApp/1.0 (contact: support@photo-tracker.app)',
          },
        ),
      );
      if (response.statusCode == 200 && response.data is List) {
        final results = response.data as List;
        if (results.isEmpty) return null;
        final result = results[0] as Map<String, dynamic>;
        final lat = double.parse(result['lat'].toString());
        final lng = double.parse(result['lon'].toString());
        if (!isInUnitedStates(lat, lng)) return null;
        return (lat: lat, lng: lng);
      }
      return null;
    } catch (e) {
      debugPrint('[Geocode] search failed: $e');
      return null;
    }
  }

  /// US place names as the user types a city, county, street, or ZIP.
  static Future<List<({String label, double lat, double lng})>> suggestPlaces(
    String query,
  ) async {
    final q = query.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.length < 3) return const [];
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/search',
        queryParameters: {
          'q': q,
          'countrycodes': 'us',
          'format': 'json',
          'addressdetails': 1,
          'limit': 5,
        },
        options: Options(
          headers: {
            'User-Agent':
                'GeoTaggingApp/1.0 (contact: support@photo-tracker.app)',
          },
        ),
      );
      if (response.statusCode != 200 || response.data is! List) {
        return const [];
      }
      final seen = <String>{};
      final hits = <({String label, double lat, double lng})>[];
      for (final raw in response.data as List) {
        if (raw is! Map) continue;
        final lat = double.tryParse(raw['lat']?.toString() ?? '');
        final lng = double.tryParse(raw['lon']?.toString() ?? '');
        if (lat == null || lng == null || !isInUnitedStates(lat, lng)) {
          continue;
        }
        final label = _suggestionLabel(raw.cast<String, dynamic>());
        if (label.isEmpty || !seen.add(label.toLowerCase())) continue;
        hits.add((label: label, lat: lat, lng: lng));
      }
      return hits;
    } catch (e) {
      debugPrint('[Geocode] suggest failed: $e');
      return const [];
    }
  }

  static String _suggestionLabel(Map<String, dynamic> result) {
    final address = result['address'];
    if (address is Map) {
      String? pick(List<String> keys) {
        for (final key in keys) {
          final value = address[key];
          if (value is String && value.trim().isNotEmpty) return value.trim();
        }
        return null;
      }

      final parts = <String>[];
      void add(String? value) {
        if (value == null) return;
        if (parts.any((p) => p.toLowerCase() == value.toLowerCase())) return;
        parts.add(value);
      }

      add(pick(['road', 'neighbourhood', 'suburb']));
      final city = pick(['city', 'town', 'village', 'hamlet']);
      final zip = pick(['postcode']);
      var state = pick(['ISO3166-2-lvl4', 'ISO3166-2-lvl6']);
      if (state != null && state.contains('-')) {
        state = state.split('-').last;
      }
      if (state != null && state.length != 2) state = null;
      final county = pick(['county']);
      if (city != null && state != null && zip != null) {
        final street = parts.isEmpty ? city : parts.join(', ');
        final countyLine = county == null ? '' : '\n$county';
        return '$street\n$city, ${state.toUpperCase()} $zip$countyLine';
      }
      add(city);
      add(pick(['county']));
      add(pick(['state']));
      add(zip);
      if (parts.isNotEmpty) return parts.join(', ');
    }
    final display = result['display_name'];
    if (display is! String) return '';
    return display
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part.toLowerCase() != 'united states')
        .take(4)
        .join(', ');
  }

  /// Get coordinates from a US ZIP code.
  static Future<({double lat, double lng})?> getCoordinatesFromZipCode(
    String zipCode,
  ) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/search',
        queryParameters: {
          'postalcode': zipCode,
          'country': 'US',
          'format': 'json',
          'limit': 1,
        },
        options: Options(
          headers: {
            'User-Agent': 'GeoTaggingApp/1.0 (contact: support@photo-tracker.app)',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final results = response.data as List;
        if (results.isNotEmpty) {
          final result = results[0] as Map<String, dynamic>;
          return (
            lat: double.parse(result['lat'].toString()),
            lng: double.parse(result['lon'].toString()),
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Nominatim] error: $e');
      return null;
    }
  }

  // ── Distance ──────────────────────────────────────────────────────────────

  static const double kAttemptProximityFt = 500;

  /// Approximate US (incl. AK, HI, PR) check for new pins / hot routes.
  static bool isInUnitedStates(double lat, double lng) {
    if (lat >= 24.396 && lat <= 49.384 && lng >= -124.849 && lng <= -66.885) {
      return true;
    }
    if (lat >= 51.2 && lat <= 71.5 && lng >= -179.2 && lng <= -129.9) {
      return true;
    }
    if (lat >= 18.9 && lat <= 22.4 && lng >= -160.4 && lng <= -154.7) {
      return true;
    }
    if (lat >= 17.8 && lat <= 18.6 && lng >= -67.3 && lng <= -65.2) {
      return true;
    }
    return false;
  }

  /// Offset [feet] east/west and north/south around a point (for Close zoom).
  static ({double minLat, double maxLat, double minLng, double maxLng})
      boxFeetAround(double lat, double lng, double feet) {
    const ftPerDegLat = 364000.0;
    final lngScale = cos(lat * pi / 180).abs().clamp(0.2, 1.0);
    final dLat = feet / ftPerDegLat;
    final dLng = feet / (ftPerDegLat * lngScale);
    return (
      minLat: lat - dLat,
      maxLat: lat + dLat,
      minLng: lng - dLng,
      maxLng: lng + dLng,
    );
  }

  static bool usableCoordinates(double? lat, double? lng) =>
      lat != null &&
      lng != null &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      (lat.abs() > 0.0001 || lng.abs() > 0.0001);

  /// Error if this GPS fix cannot prove the server is at the job.
  /// The attempt must be logged in the US and within 500 feet of the profile.
  static String? attemptTooFarMessage({
    required double gpsLat,
    required double gpsLng,
    double? jobLat,
    double? jobLng,
    double? gpsAccuracyMeters,
  }) {
    if (!isInUnitedStates(gpsLat, gpsLng)) {
      return 'Attempts can only be logged in the United States.';
    }
    if (jobLat == null || jobLng == null) {
      return null;
    }
    final slackFt = ((gpsAccuracyMeters ?? 0) * 3.28084).clamp(0, 150);
    final feet = distanceFeet(gpsLat, gpsLng, jobLat, jobLng);
    if (feet > kAttemptProximityFt + slackFt) {
      return 'You are ${feet.round()} ft from this job. '
          'An attempt can only be logged within ${kAttemptProximityFt.toInt()} ft of the profile.';
    }
    return null;
  }

  /// Haversine distance in feet.
  static double distanceFeet(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      calculateDistance(lat1, lon1, lat2, lon2) * 3280.84;

  /// Haversine distance between two points in kilometres.
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
