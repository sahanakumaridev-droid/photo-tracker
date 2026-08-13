import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>(
  (ref) => ThemeNotifier(),
);

/// Fixed brand accent — field-app blue from the mobile reference UI.
const Color kBrandAccent = Color(0xFF4A90E2);

class ThemeState {
  ThemeState({this.mode = ThemeMode.dark});
  final ThemeMode mode;

  // Kept so existing call sites (`themeState.accentColor`) keep working without
  // a sweeping rename — it's now a constant, not user-configurable.
  Color get accentColor => kBrandAccent;

  bool get isDark => mode == ThemeMode.dark;

  ThemeState copyWith({ThemeMode? mode}) =>
      ThemeState(mode: mode ?? this.mode);
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(ThemeState()) {
    _loadTheme();
  }

  static const _kDarkKey = 'isDarkMode';

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool(_kDarkKey) ?? true;
      state = ThemeState(mode: isDark ? ThemeMode.dark : ThemeMode.light);
    } on Exception {
      // Keep the default dark theme.
    }
  }

  /// Flip light/dark. The UI updates synchronously (instant) and persistence
  /// happens in the background so the toggle never feels laggy.
  void toggleTheme() {
    final nowDark = state.mode != ThemeMode.dark;
    state = state.copyWith(mode: nowDark ? ThemeMode.dark : ThemeMode.light);
    _persist(nowDark);
  }

  void setDark(bool dark) {
    if (state.isDark == dark) return;
    state = state.copyWith(mode: dark ? ThemeMode.dark : ThemeMode.light);
    _persist(dark);
  }

  Future<void> _persist(bool dark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDarkKey, dark);
    } on Exception {
      // Non-fatal: the in-memory state already reflects the user's choice.
    }
  }
}
