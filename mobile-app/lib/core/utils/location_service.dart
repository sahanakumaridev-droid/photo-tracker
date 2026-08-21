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

  // ── Watch stream ──────────────────────────────────────────────────────────

  /// Stream of position updates. Uses high accuracy + 10 m distance filter.
  static Stream<Position> watchLocation() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 10,
        ),
      );

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
  static Future<({String? street, String? city, String? state, String? zip})>
      reverseGeocodeDetailed(double latitude, double longitude) async {
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
    return (street: null, city: null, state: null, zip: null);
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
  static ({String? street, String? city, String? state, String? zip})
      _addressComponents(Map<String, dynamic> addr) {
    final houseNumber = addr['house_number'] as String?;
    final road = addr['road'] as String?;
    final street = (road != null && road.isNotEmpty)
        ? (houseNumber != null ? '$houseNumber $road' : road)
        : null;

    final city = (addr['city'] ??
        addr['town'] ??
        addr['village'] ??
        addr['municipality']) as String?;

    // Prefer abbreviation for compact inline addresses.
    final state = (addr['state_code'] ?? addr['state']) as String?;

    final zip = addr['postcode'] as String?;

    return (street: street, city: city, state: state, zip: zip);
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
