import 'package:shared_preferences/shared_preferences.dart';

/// Local storage service using SharedPreferences
class LocalStorage {
  static late SharedPreferences _prefs;

  // Keys
  static const String _authTokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _themeKey = 'theme_mode';
  static const String _lastSyncKey = 'last_sync';

  /// Initialize local storage
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ─── Auth Token ─────────────────────────────────────────────────────────

  /// Save auth token
  static Future<bool> saveAuthToken(String token) async => _prefs.setString(_authTokenKey, token);

  /// Get auth token
  static Future<String?> getAuthToken() async => _prefs.getString(_authTokenKey);

  /// Clear auth token
  static Future<bool> clearAuthToken() async => _prefs.remove(_authTokenKey);

  // ─── User Data ──────────────────────────────────────────────────────────

  /// Save user data
  static Future<bool> saveUserData(String userData) async => _prefs.setString(_userKey, userData);

  /// Get user data
  static Future<String?> getUserData() async => _prefs.getString(_userKey);

  /// Clear user data
  static Future<bool> clearUserData() async => _prefs.remove(_userKey);

  // ─── Theme ──────────────────────────────────────────────────────────────

  /// Save theme mode
  static Future<bool> saveThemeMode(bool isDarkMode) async => _prefs.setBool(_themeKey, isDarkMode);

  /// Get theme mode
  static bool getThemeMode() => _prefs.getBool(_themeKey) ?? false;

  // ─── Sync ───────────────────────────────────────────────────────────────

  /// Save last sync timestamp
  static Future<bool> saveLastSync(DateTime dateTime) async => _prefs.setInt(_lastSyncKey, dateTime.millisecondsSinceEpoch);

  /// Get last sync timestamp
  static DateTime? getLastSync() {
    final timestamp = _prefs.getInt(_lastSyncKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  // ─── General ────────────────────────────────────────────────────────────

  /// Clear all data
  static Future<bool> clearAll() async => _prefs.clear();

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }
}
