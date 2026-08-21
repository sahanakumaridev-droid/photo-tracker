import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Field-app light UI — white surfaces, dark ink, blue actions.
/// The product theme is light; `dark*` names are kept as aliases.
class AppTheme {
  // ── Brand / accent ──
  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryLight = Color(0xFF64B5F6);
  static const Color primaryDark = Color(0xFF1E88E5);
  static const Color primarySoft = Color(0x1F4A90E2);

  static const Color black = Color(0xFF1A2130);
  static const Color white = Color(0xFFFFFFFF);
  static const Color nearBlack = Color(0xFF1A2130);
  static const Color offWhite = Color(0xFFF2F4F7);

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

  // ── Light field palette ──
  static const Color lightBg = Color(0xFFF2F4F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFEEF1F5);
  static const Color lightNav = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE3E7EE);
  static const Color lightText = Color(0xFF1A2130);
  static const Color lightTextSecondary = Color(0xFF5C6778);
  static const Color lightTextTertiary = Color(0xFF8B95A5);

  // Aliases — screens historically named these `dark*`
  static const Color darkBg = lightBg;
  static const Color darkSurface = lightSurface;
  static const Color darkElevated = lightElevated;
  static const Color darkNav = lightNav;
  static const Color darkBorder = lightBorder;
  static const Color darkText = lightText;
  static const Color darkTextSecondary = lightTextSecondary;
  static const Color darkTextTertiary = lightTextTertiary;

  static const SystemUiOverlayStyle overlayDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: lightNav,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static ThemeData lightTheme(Color accentColor) => _theme(accentColor);

  static ThemeData darkTheme(Color accentColor) => _theme(accentColor);

  static ThemeData _theme(Color accentColor) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: null,
        colorScheme: ColorScheme.light(
          primary: accentColor,
          onPrimary: white,
          secondary: lightElevated,
          onSecondary: lightText,
          surface: lightSurface,
          onSurface: lightText,
          error: error,
          onError: white,
          outline: lightBorder,
        ),
        scaffoldBackgroundColor: lightBg,
        canvasColor: lightBg,
        dividerColor: lightBorder,
        splashFactory: InkRipple.splashFactory,
        appBarTheme: AppBarTheme(
          backgroundColor: lightBg,
          foregroundColor: lightText,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          systemOverlayStyle: overlayDark,
          titleTextStyle: const TextStyle(
            color: lightText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: const IconThemeData(color: lightText),
        ),
        cardTheme: CardThemeData(
          color: lightSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: lightBorder, width: 1),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: lightSurface,
          modalBackgroundColor: lightSurface,
          surfaceTintColor: Colors.transparent,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: lightSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: lightText,
          contentTextStyle: const TextStyle(color: white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: lightElevated,
          prefixIconColor: lightTextSecondary,
          suffixIconColor: lightTextSecondary,
          hintStyle: const TextStyle(color: lightTextTertiary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: lightBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: lightBorder),
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
                return Colors.black.withValues(alpha: 0.08);
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
          color: lightBorder,
          thickness: 1,
          space: 1,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: lightText,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: lightText,
            letterSpacing: -0.5,
          ),
          headlineSmall: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: lightText,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: lightText,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: lightText,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: lightText,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: lightTextSecondary,
          ),
        ),
      );
}
