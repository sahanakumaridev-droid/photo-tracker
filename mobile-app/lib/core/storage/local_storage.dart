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

  // ─── F5: Pin draft auto-save ──────────────────────────────────────────────
  static const String _draftKey = 'pin_draft';

  /// Save the in-progress pin draft (JSON string).
  static Future<bool> savePinDraft(String json) async =>
      _prefs.setString(_draftKey, json);

  /// Get the saved pin draft, or null if none.
  static String? getPinDraft() => _prefs.getString(_draftKey);

  /// Clear the saved pin draft.
  static Future<bool> clearPinDraft() async => _prefs.remove(_draftKey);

  // ─── Served To — custom names ──────────────────────────────────────────────
  static const String _servedToCustomNamesKey = 'served_to_custom_names';

  /// Custom "Served To" names the user has created, most-recent first.
  static List<String> getServedToCustomNames() =>
      _prefs.getStringList(_servedToCustomNamesKey) ?? [];

  /// Remember a custom "Served To" name for reuse (most-recent first, deduped).
  static Future<bool> addServedToCustomName(String name) async {
    final names = getServedToCustomNames()
      ..remove(name)
      ..insert(0, name);
    return _prefs.setStringList(_servedToCustomNamesKey, names);
  }

  // ─── Permissions ──────────────────────────────────────────────────────────
  static const String _permissionsRequestedKey = 'permissions_requested';

  /// Whether the one-time permission batch (camera/photos/location) has already
  /// been requested on this install.
  static bool getPermissionsRequested() =>
      _prefs.getBool(_permissionsRequestedKey) ?? false;

  /// Mark the one-time permission batch as requested.
  static Future<bool> setPermissionsRequested() async =>
      _prefs.setBool(_permissionsRequestedKey, true);

  // ─── General ────────────────────────────────────────────────────────────

  /// Clear all data
  static Future<bool> clearAll() async => _prefs.clear();

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }
}
