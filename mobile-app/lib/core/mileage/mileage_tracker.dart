import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/location_service.dart';

/// User-level running mileage (not company/profile scoped).
class MileageTracker extends ChangeNotifier {
  MileageTracker._();
  static final MileageTracker instance = MileageTracker._();

  static const _kTracking = 'mileage_tracking';
  static const _kTotal = 'mileage_total_miles';

  bool tracking = false;
  double totalMiles = 0;
  double todayMiles = 0;
  double weekMiles = 0;
  StreamSubscription<Position>? _sub;
  DateTime? _lastPing;
  Position? _lastPos;
  Dio? _dio;
  String? _email;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    tracking = prefs.getBool(_kTracking) ?? false;
    totalMiles = prefs.getDouble(_kTotal) ?? 0;
    notifyListeners();
  }

  /// Attach the signed-in API client. Restarts the GPS stream when tracking
  /// was already on so miles are stored on that user, including after relaunch.
  Future<void> bind(Dio dio, {String? email}) async {
    _dio = dio;
    _email = email;
    if (!tracking) {
      await refresh(dio, email: email);
      return;
    }
    await start(dio: dio, email: email);
  }

  Future<void> toggle(Dio dio, {String? email}) async {
    _dio = dio;
    _email = email;
    if (tracking) {
      await stop();
    } else {
      await start(dio: dio, email: email);
    }
  }

  Future<void> start({Dio? dio, String? email}) async {
    if (dio != null) _dio = dio;
    if (email != null) _email = email;
    tracking = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTracking, true);
    notifyListeners();
    await _sub?.cancel();
    final permitted = await LocationService.requestLocationPermission();
    if (!permitted || !tracking) return;
    _sub = LocationService.watchLocation().listen((pos) {
      unawaited(_onFix(pos));
    });
    final first = await LocationService.getFreshFix();
    if (first != null && tracking) await _onFix(first);
  }

  Future<void> stop() async {
    tracking = false;
    await _sub?.cancel();
    _sub = null;
    _lastPos = null;
    _lastPing = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTracking, false);
    notifyListeners();
    final dio = _dio;
    if (dio == null) return;
    try {
      await dio.post('/api/mileage/ping', data: {
        if (_email != null && _email!.isNotEmpty) 'email': _email,
        'tracking': false,
        'day': _localDay(),
      });
    } catch (e) {
      debugPrint('[Mileage] stop ping failed: $e');
    }
  }

  String _localDay() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  Future<void> _onFix(Position pos) async {
    if (!tracking) return;
    final now = DateTime.now();
    if (_lastPing != null && now.difference(_lastPing!) < const Duration(seconds: 8)) {
      return;
    }
    _lastPing = now;
    final dio = _dio;
    if (dio == null) {
      await _addLocalMiles(pos);
      return;
    }
    try {
      final res = await dio.post('/api/mileage/ping', data: {
        if (_email != null && _email!.isNotEmpty) 'email': _email,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'tracking': true,
        'day': _localDay(),
      });
      final data = res.data;
      if (data is Map) {
        totalMiles = (data['total_miles'] as num?)?.toDouble() ?? totalMiles;
        todayMiles = (data['today_miles'] as num?)?.toDouble() ?? todayMiles;
        weekMiles = (data['week_miles'] as num?)?.toDouble() ?? weekMiles;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_kTotal, totalMiles);
        _lastPos = pos;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Mileage] ping failed: $e');
      await _addLocalMiles(pos);
    }
  }

  Future<void> _addLocalMiles(Position pos) async {
    if (_lastPos != null) {
      final miles = Geolocator.distanceBetween(
            _lastPos!.latitude,
            _lastPos!.longitude,
            pos.latitude,
            pos.longitude,
          ) /
          1609.344;
      if (miles > 0.002 && miles < 80) {
        totalMiles += miles;
        todayMiles += miles;
        weekMiles += miles;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_kTotal, totalMiles);
        notifyListeners();
      }
    }
    _lastPos = pos;
  }

  Future<void> refresh(Dio dio, {String? email}) async {
    try {
      final res = await dio.get('/api/mileage', queryParameters: {
        if (email != null) 'email': email,
        'day': _localDay(),
      });
      final data = res.data;
      if (data is Map) {
        totalMiles = (data['total_miles'] as num?)?.toDouble() ?? totalMiles;
        todayMiles = (data['today_miles'] as num?)?.toDouble() ?? todayMiles;
        weekMiles = (data['week_miles'] as num?)?.toDouble() ?? weekMiles;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Mileage] fetch failed: $e');
    }
  }
}

final mileageTrackerProvider = mileageTrackerListenable;

final mileageTrackerListenable = MileageTracker.instance;
