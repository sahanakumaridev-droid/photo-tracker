import 'package:hive_flutter/hive_flutter.dart';

/// Local cache for list-endpoint responses (photos, profiles) so screens can
/// show last-known data instantly, and fall back to it when the network is
/// slow or unreachable instead of showing a blank/error state.
class ApiCache {
  ApiCache._();

  static const _boxName = 'api_cache';
  static Box<String>? _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// Raw cached JSON for [key], or null if nothing cached yet.
  static String? read(String key) => _box?.get(key);

  /// Persist raw JSON for [key], overwriting any previous value.
  static Future<void> write(String key, String json) async {
    await _box?.put(key, json);
  }
}
