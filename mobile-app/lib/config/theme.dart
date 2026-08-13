import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Field-app dark UI — navy surfaces, blue actions, magenta alerts.
/// Tokens match the mobile reference screens (map, job, attempt).
class AppTheme {
  // ── Brand / accent ──
  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryLight = Color(0xFF64B5F6);
  static const Color primaryDark = Color(0xFF1E88E5);
  static const Color primarySoft = Color(0x1F4A90E2);

  static const Color black = Color(0xFF0A0C10);
  static const Color white = Color(0xFFFFFFFF);
  static const Color nearBlack = Color(0xFF0F1219);
  static const Color offWhite = Color(0xFFF8FAFC);

  static const Color success = Color(0xFF10b981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFef4444);
  static const Color info = Color(0xFF4A90E2);
  static const Color alert = Color(0xFFC2185B);
  static const Color badge = Color(0xFFEF4444);

  static const Color serviceRush = Color(0xFFef4444);
  static const Color serviceStandard = Color(0xFF4A90E2);
  static const Color serviceAirport = Color(0xFF0ea5e9);

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  // ── Dark field palette (primary product theme) ──
  static const Color darkBg = Color(0xFF0F1219);
  static const Color darkSurface = Color(0xFF1C222E);
  static const Color darkElevated = Color(0xFF242B38);
  static const Color darkNav = Color(0xFF0A0C10);
  static const Color darkBorder = Color(0xFF2A3340);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF6B7A8D);

  // Aliases used by screens that still name tokens "light*"
  static const Color lightBg = darkBg;
  static const Color lightSurface = darkSurface;
  static const Color lightBorder = darkBorder;
  static const Color lightText = darkText;
  static const Color lightTextSecondary = darkTextSecondary;
  static const Color lightTextTertiary = darkTextTertiary;

  static const SystemUiOverlayStyle overlayDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: darkNav,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData lightTheme(Color accentColor) => darkTheme(accentColor);

  static ThemeData darkTheme(Color accentColor) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: null,
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          onPrimary: white,
          secondary: darkElevated,
          onSecondary: darkText,
          surface: darkSurface,
          onSurface: darkText,
          error: error,
          onError: white,
          outline: darkBorder,
        ),
        scaffoldBackgroundColor: darkBg,
        canvasColor: darkBg,
        dividerColor: darkBorder,
        splashFactory: InkRipple.splashFactory,
        appBarTheme: AppBarTheme(
          backgroundColor: darkBg,
          foregroundColor: darkText,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          systemOverlayStyle: overlayDark,
          titleTextStyle: const TextStyle(
            color: darkText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: const IconThemeData(color: darkText),
        ),
        cardTheme: CardThemeData(
          color: darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: darkBorder, width: 1),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: darkSurface,
          modalBackgroundColor: darkSurface,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: darkSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: darkElevated,
          contentTextStyle: const TextStyle(color: darkText),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkElevated,
          prefixIconColor: darkTextSecondary,
          suffixIconColor: darkTextSecondary,
          hintStyle: const TextStyle(color: darkTextTertiary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accentColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 0,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Colors.white.withValues(alpha: 0.12);
              }
              return null;
            }),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accentColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accentColor,
          foregroundColor: white,
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(
          color: darkBorder,
          thickness: 1,
          space: 1,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: darkText,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: darkText,
            letterSpacing: -0.5,
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: darkText,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: darkText,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: darkText,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: darkText,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: darkTextSecondary,
          ),
        ),
      );
}
