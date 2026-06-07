/// Application configuration
/// Centralized configuration for API, timeouts, and feature flags
class AppConfig {
  // API Configuration
  // Local dev: iOS simulator reaches the Mac's backend via localhost.
  // (Production remote was 'http://24.199.85.230'.)
  static const String apiBaseUrl = 'http://localhost:5001';
  static const int apiTimeout = 30; // seconds
  static const int apiRetryCount = 3;

  // App Configuration
  static const String appName = 'Geo Tag';
  static const String appVersion = '1.0.0';

  // Feature Flags
  static const bool enableDarkMode = true;
  static const bool enableOfflineMode = true;
  static const bool enableAnalytics = false;
  static const bool enableCrashReporting = false;

  // Location Configuration
  static const int locationAccuracyThreshold = 50; // meters
  static const int locationUpdateInterval = 5000; // milliseconds

  // Cache Configuration
  static const int photoCacheDuration = 300; // seconds (5 minutes)
  static const int profileCacheDuration = 300; // seconds
  static const int maxCacheSize = 100; // MB

  // UI Configuration
  static const int animationDuration = 300; // milliseconds
  static const int pageTransitionDuration = 250; // milliseconds

  // Logging
  static const bool enableLogging = true;
  static const String logLevel = 'debug'; // debug, info, warning, error

  /// Get API base URL with fallback
  static String getApiBaseUrl() => apiBaseUrl;

  /// Check if running in debug mode
  static bool isDebugMode() => true; // Set to false in production
}
