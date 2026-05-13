import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'constants.dart';

class LocationService {

  factory LocationService() => _instance;

  LocationService._internal();
  static final LocationService _instance = LocationService._internal();

  /// Request location permissions
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

  /// Get current location
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
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      debugPrint('[Location] ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      debugPrint('[Location] error: $e');
      return null;
    }
  }

  /// Watch location updates
  static Stream<Position> watchLocation() =>
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      );

  /// Reverse geocode — returns both address string and zip in one HTTP call
  static Future<({String? address, String? zip})> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/reverse',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'format': 'json',
        },
        options: Options(
          headers: {
            'User-Agent': 'GeoTaggingApp/1.0 (mobile)',
            'Accept-Language': 'en',
          },
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      debugPrint('[Nominatim] status=${response.statusCode}');

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;

        if (addr == null) {
          debugPrint('[Nominatim] no address field in response');
          return (address: null, zip: null);
        }

        final zip = addr['postcode'] as String?;

        // Build readable address
        final parts = <String>[];
        final houseNumber = addr['house_number'] as String?;
        final road = addr['road'] as String?;
        final neighbourhood = addr['neighbourhood'] as String?;
        final suburb = addr['suburb'] as String?;
        final city = (addr['city'] ?? addr['town'] ?? addr['village'])
            as String?;
        final state = addr['state'] as String?;

        if (road != null) {
          parts.add(houseNumber != null ? '$houseNumber $road' : road);
        }
        final area = neighbourhood ?? suburb;
        if (area != null && area != city) parts.add(area);
        if (city != null) parts.add(city);
        if (state != null) parts.add(state);
        if (zip != null) parts.add(zip);

        final address = parts.isNotEmpty ? parts.join(', ') : null;
        debugPrint('[Nominatim] address=$address  zip=$zip');
        return (address: address, zip: zip);
      }

      debugPrint('[Nominatim] unexpected response: ${response.statusCode}');
      return (address: null, zip: null);
    } catch (e) {
      debugPrint('[Nominatim] error: $e');
      return (address: null, zip: null);
    }
  }

  /// Reverse geocode coordinates to zip code using Nominatim
  static Future<String?> getZipCodeFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/reverse',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'format': 'json',
        },
        options: Options(
          headers: {
            'User-Agent': 'GeoTaggingApp/1.0 (mobile)',
            'Accept-Language': 'en',
          },
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final address = response.data['address'] as Map<String, dynamic>?;
        if (address != null) {
          return address['postcode'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Nominatim] error: $e');
      return null;
    }
  }

  /// Reverse geocode coordinates to a human-readable address string
  static Future<String?> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        '${AppConstants.nominatimBaseUrl}/reverse',
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'format': 'json',
        },
        options: Options(
          headers: {
            'User-Agent': 'GeoTaggingApp/1.0 (mobile)',
            'Accept-Language': 'en',
          },
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200) {
        final addr =
            response.data['address'] as Map<String, dynamic>?;
        if (addr != null) {
          final parts = <String>[];
          final houseNumber = addr['house_number'] as String?;
          final road = addr['road'] as String?;
          final suburb = addr['suburb'] as String?;
          final neighbourhood = addr['neighbourhood'] as String?;
          final city = (addr['city'] ??
              addr['town'] ??
              addr['village']) as String?;
          final state = addr['state'] as String?;
          final postcode = addr['postcode'] as String?;

          // Build street: "1234 Mission Blvd"
          if (road != null) {
            parts.add(
              houseNumber != null ? '$houseNumber $road' : road,
            );
          }
          // Neighbourhood / suburb (skip if same as city)
          final area = neighbourhood ?? suburb;
          if (area != null && area != city) parts.add(area);
          if (city != null) parts.add(city);
          if (state != null) parts.add(state);
          if (postcode != null) parts.add(postcode);

          return parts.isNotEmpty ? parts.join(', ') : null;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Nominatim] error: $e');
      return null;
    }
  }

  /// Get coordinates from zip code using Nominatim
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

  /// Calculate distance between two points in kilometers
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371; // Earth's radius in km
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

