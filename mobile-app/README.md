# 📍 GeoTagging Mobile App — Flutter

A production-ready Flutter mobile application for location-based photo tracking and CRM management. Replicates all features from the web application with optimized mobile UX, smooth animations, and modern design patterns.

## 🎯 Features

- **📷 Photo Upload** — Capture or select photos with automatic GPS tagging
- **🗺️ Interactive Map** — View all geotagged photos on an interactive map
- **👥 Profile Management** — Create and manage service profiles (Standard, Rush, Airport)
- **📊 Dashboard** — Real-time statistics and photo overview
- **📝 Activity Log** — Filter and search through all photos with metadata
- **🔍 Advanced Search** — Filter by date, zip code, service type, and notes
- **🌙 Dark Mode** — Full dark mode support with smooth transitions
- **📱 Responsive Design** — Optimized for phones and tablets
- **⚡ Offline Support** — Local caching and offline-safe operations
- **🎨 Modern UI** — Glassmorphism, smooth animations, premium feel

## 🚀 Quick Start

### Prerequisites

- Flutter 3.0+ ([Install Flutter](https://flutter.dev/docs/get-started/install))
- Dart 3.0+
- iOS 12.0+ or Android 5.0+
- API server running (see backend setup)

### Installation

```bash
# Navigate to mobile app directory
cd photo-tracker/mobile-app

# Get dependencies
flutter pub get

# Generate code (Riverpod, Retrofit, JSON serialization)
flutter pub run build_runner build

# Run on device/emulator
flutter run

# Run with specific flavor (if configured)
flutter run --flavor dev
```

### Environment Setup

Create `.env` file in `mobile-app/` directory:

```env
API_BASE_URL=http://24.199.85.230
API_TIMEOUT=30
LOG_LEVEL=debug
```

Or use environment-specific configs in `lib/config/`:

```dart
// lib/config/app_config.dart
const String apiBaseUrl = 'http://24.199.85.230';
const int apiTimeout = 30;
```

## 📁 Project Structure

```
mobile-app/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── config/
│   │   ├── app_config.dart         # Environment configuration
│   │   ├── theme.dart              # Theme & colors
│   │   └── constants.dart          # App constants
│   ├── core/
│   │   ├── network/
│   │   │   ├── api_client.dart     # Dio + Retrofit setup
│   │   │   ├── interceptors.dart   # Auth, logging interceptors
│   │   │   └── api_service.dart    # API endpoints
│   │   ├── storage/
│   │   │   ├── local_storage.dart  # SharedPreferences wrapper
│   │   │   └── secure_storage.dart # Secure token storage
│   │   ├── location/
│   │   │   └── location_service.dart # Geolocation service
│   │   └── utils/
│   │       ├── logger.dart         # Logging utility
│   │       ├── validators.dart     # Input validation
│   │       └── extensions.dart     # Dart extensions
│   ├── data/
│   │   ├── models/
│   │   │   ├── photo.dart          # Photo model
│   │   │   ├── profile.dart        # Profile model
│   │   │   └── responses.dart      # API response models
│   │   ├── repositories/
│   │   │   ├── photo_repository.dart
│   │   │   ├── profile_repository.dart
│   │   │   └── auth_repository.dart
│   │   └── datasources/
│   │       ├── remote_datasource.dart
│   │       └── local_datasource.dart
│   ├── domain/
│   │   ├── entities/
│   │   ├── repositories/
│   │   └── usecases/
│   ├── presentation/
│   │   ├── providers/              # Riverpod providers
│   │   │   ├── auth_provider.dart
│   │   │   ├── photo_provider.dart
│   │   │   ├── profile_provider.dart
│   │   │   └── location_provider.dart
│   │   ├── screens/
│   │   │   ├── auth/
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── splash_screen.dart
│   │   │   ├── home/
│   │   │   │   ├── dashboard_screen.dart
│   │   │   │   ├── map_screen.dart
│   │   │   │   └── widgets/
│   │   │   ├── upload/
│   │   │   │   ├── upload_screen.dart
│   │   │   │   └── widgets/
│   │   │   ├── profiles/
│   │   │   │   ├── profiles_screen.dart
│   │   │   │   ├── profile_detail_screen.dart
│   │   │   │   └── widgets/
│   │   │   ├── log/
│   │   │   │   ├── log_screen.dart
│   │   │   │   └── widgets/
│   │   │   └── settings/
│   │   │       └── settings_screen.dart
│   │   ├── widgets/
│   │   │   ├── common/
│   │   │   │   ├── app_bar.dart
│   │   │   │   ├── bottom_nav.dart
│   │   │   │   ├── loading_skeleton.dart
│   │   │   │   └── error_widget.dart
│   │   │   ├── cards/
│   │   │   │   ├── photo_card.dart
│   │   │   │   ├── profile_card.dart
│   │   │   │   └── stat_card.dart
│   │   │   └── dialogs/
│   │   │       ├── confirm_dialog.dart
│   │   │       └── edit_dialog.dart
│   │   └── router/
│   │       └── app_router.dart     # GoRouter configuration
│   └── app.dart                    # App widget
├── assets/
│   ├── images/
│   ├── animations/
│   └── icons/
├── android/
│   ├── app/
│   ├── gradle/
│   └── build.gradle
├── ios/
│   ├── Runner/
│   ├── Runner.xcodeproj/
│   └── Podfile
├── test/
│   ├── unit/
│   ├── widget/
│   └── integration/
├── pubspec.yaml
├── analysis_options.yaml
└── README.md
```

## 🏗️ Architecture

### Clean Architecture + Feature-Based Structure

```
Presentation Layer (UI)
    ↓
Riverpod Providers (State Management)
    ↓
Repository Pattern (Data Access)
    ↓
Data Sources (Remote API + Local Storage)
```

### Key Patterns

1. **Riverpod** — Reactive state management with compile-time safety
2. **Repository Pattern** — Abstraction between data sources and business logic
3. **Retrofit** — Type-safe HTTP client with automatic serialization
4. **GoRouter** — Declarative routing with deep linking support
5. **Hive** — Local caching for offline support

## 🔌 API Integration

### Base Configuration

```dart
// lib/core/network/api_client.dart
final apiClientProvider = Provider((ref) {
  final config = ref.watch(appConfigProvider);
  return ApiClient(
    baseUrl: config.apiBaseUrl,
    timeout: config.apiTimeout,
  );
});
```

### API Endpoints

All endpoints mirror the backend:

```dart
// GET /profiles
// POST /profiles
// PATCH /profiles/{id}
// DELETE /profiles/{id}

// GET /photos
// POST /upload
// PATCH /photos/{id}/location
// PATCH /photos/{id}/note
// DELETE /photos/{id}

// GET /log
// POST /export/email
```

### Error Handling

```dart
try {
  final photos = await repository.getPhotos();
} on ApiException catch (e) {
  // Handle API errors
  logger.error('API Error: ${e.message}');
} on NetworkException catch (e) {
  // Handle network errors
  logger.error('Network Error: ${e.message}');
}
```

## 🎨 UI/UX Features

### Design System

- **Color Palette** — Indigo, emerald, rose, amber
- **Typography** — Geist font family (regular, medium, bold)
- **Spacing** — 4px base unit (4, 8, 12, 16, 24, 32, 48)
- **Shadows** — Subtle elevation system
- **Animations** — 200-400ms smooth transitions

### Premium Features

- ✨ Glassmorphism cards with backdrop blur
- 🎬 Smooth page transitions with Hero animations
- 📊 Animated stat counters
- 🔄 Shimmer loading skeletons
- 🎯 Micro-interactions on buttons and inputs
- 🌈 Gradient accents
- 📱 Responsive breakpoints (phone, tablet)

## 🔐 Authentication

### Token Management

```dart
// Automatic token refresh on 401
// Secure token storage using flutter_secure_storage
// Interceptor-based auth header injection
```

### Login Flow

1. User enters credentials
2. API returns access token
3. Token stored securely
4. Subsequent requests include token in header
5. On token expiry, automatic refresh
6. On refresh failure, redirect to login

## 📍 Location Services

### Permissions

- iOS: `NSLocationWhenInUseUsageDescription`
- Android: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`

### Features

- One-time GPS grab
- Continuous location watching
- Reverse geocoding (address lookup)
- Manual coordinate entry
- Map-based location picker

## 💾 Local Storage

### SharedPreferences

```dart
// User preferences, app settings
await prefs.setString('theme_mode', 'dark');
```

### Hive

```dart
// Cached photos, profiles for offline access
final box = await Hive.openBox('photos');
box.put('photo_1', photoData);
```

### Secure Storage

```dart
// Auth tokens, sensitive data
await secureStorage.write(key: 'access_token', value: token);
```

## 🧪 Testing

### Unit Tests

```bash
flutter test test/unit/
```

### Widget Tests

```bash
flutter test test/widget/
```

### Integration Tests

```bash
flutter test integration_test/
```

## 📦 Build & Release

### Android

```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

### iOS

```bash
# Debug build
flutter build ios --debug

# Release build
flutter build ios --release

# Archive for App Store
flutter build ios --release
```

## 🔧 Configuration

### Environment Variables

Create `.env` file:

```env
API_BASE_URL=http://24.199.85.230
API_TIMEOUT=30
LOG_LEVEL=debug
ENABLE_ANALYTICS=true
```

Load in `main.dart`:

```dart
await dotenv.load(fileName: ".env");
```

### Feature Flags

```dart
// lib/config/feature_flags.dart
class FeatureFlags {
  static const bool enableDarkMode = true;
  static const bool enableOfflineMode = true;
  static const bool enableAnalytics = false;
}
```

## 🚨 Troubleshooting

### Build Issues

```bash
# Clean build
flutter clean
flutter pub get
flutter pub run build_runner clean
flutter pub run build_runner build

# Rebuild iOS pods
cd ios && rm -rf Pods Podfile.lock && cd ..
flutter pub get
```

### Location Permission Issues

- **iOS**: Check `Info.plist` for location usage descriptions
- **Android**: Check `AndroidManifest.xml` for permissions
- **Runtime**: Request permissions before accessing location

### API Connection Issues

- Verify API server is running
- Check `API_BASE_URL` in config
- Verify network connectivity
- Check firewall/CORS settings

## 📚 Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Riverpod Documentation](https://riverpod.dev)
- [GoRouter Documentation](https://pub.dev/packages/go_router)
- [Retrofit Documentation](https://pub.dev/packages/retrofit)

## 📝 License

This project is part of the GeoTagging CRM system.

## 👥 Support

For issues or questions, contact the development team.

---

**Last Updated**: May 2026
**Flutter Version**: 3.0+
**Dart Version**: 3.0+
