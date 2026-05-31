import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>(
  (ref) => ThemeNotifier(),
);

class ThemeState {
  ThemeState({
    this.mode = ThemeMode.light,
    this.accentColor = const Color(0xFF7C3AED),
  });
  final ThemeMode mode;
  final Color accentColor;

  ThemeState copyWith({
    ThemeMode? mode,
    Color? accentColor,
  }) =>
      ThemeState(
        mode: mode ?? this.mode,
        accentColor: accentColor ?? this.accentColor,
      );
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(ThemeState()) {
    _loadTheme();
  }

  static const Map<String, Color> accentColors = {
    'purple': Color(0xFF7C3AED),
    'violet': Color(0xFF8B5CF6),
    'indigo': Color(0xFF6366F1),
    'black': Color(0xFF1F1F1F),
    'plum': Color(0xFFA21CAF),
    'slate': Color(0xFF475569),
  };

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('isDarkMode') ?? false;
      final accentColorName = prefs.getString('accentColor') ?? 'purple';
      final accentColor =
          accentColors[accentColorName] ?? accentColors['purple']!;

      state = ThemeState(
        mode: isDark ? ThemeMode.dark : ThemeMode.light,
        accentColor: accentColor,
      );
    } on Exception {
      // Use default theme
    }
  }

  Future<void> toggleTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = state.mode == ThemeMode.dark;
      await prefs.setBool('isDarkMode', !isDark);
      state = state.copyWith(
        mode: isDark ? ThemeMode.light : ThemeMode.dark,
      );
    } on Exception {
      // Ignore errors
    }
  }

  Future<void> setAccentColor(String colorName) async {
    try {
      final color = accentColors[colorName];
      if (color != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('accentColor', colorName);
        state = state.copyWith(accentColor: color);
      }
    } on Exception {
      // Ignore errors
    }
  }
}
