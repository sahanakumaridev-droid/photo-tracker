import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user-selected app language. A `null` locale means "follow the
/// device" — MaterialApp then resolves against the supported locales.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(null) {
    _loadLocale();
  }

  static const String _prefsKey = 'appLocale';

  /// Languages the user can choose, keyed by language code. Must stay a
  /// subset of AppLocalizations.supportedLocales.
  static const Map<String, String> languages = {
    'system': 'System default',
    'en': 'English',
    'es': 'Español',
  };

  Future<void> _loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      if (code != null && code != 'system' && languages.containsKey(code)) {
        state = Locale(code);
      }
    } on Exception {
      // Fall back to system locale.
    }
  }

  /// [code] is a language code ('en', 'es') or 'system' to follow the device.
  Future<void> setLocale(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
      state = (code == 'system') ? null : Locale(code);
    } on Exception {
      // Ignore errors.
    }
  }
}
