# Flutter Mobile App Architecture

## Overview

This Flutter application follows **Clean Architecture** principles combined with a **feature-based folder structure**. The architecture is designed for scalability, maintainability, and testability.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│                  Presentation Layer                      │
│  (Screens, Widgets, Providers, Router)                  │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   State Management                       │
│  (Riverpod Providers)                                   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                  Repository Layer                        │
│  (Data Access Abstraction)                              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│                   Data Layer                             │
│  (Remote API, Local Storage)                            │
└─────────────────────────────────────────────────────────┘
```

## Folder Structure

### `/lib/config`
Application-wide configuration and theme setup.

```
config/
├── app_config.dart      # Environment variables, feature flags
├── theme.dart           # Material theme, colors, typography
└── constants.dart       # App-wide constants
```

### `/lib/core`
Core utilities and services used across the app.

```
core/
├── network/
│   ├── api_client.dart      # Dio setup, API endpoints
│   ├── interceptors.dart    # Auth, logging, error handling
│   └── exceptions.dart      # Custom exceptions
├── storage/
│   ├── local_storage.dart   # SharedPreferences wrapper
│   └── secure_storage.dart  # Secure token storage
├── location/
│   └── location_service.dart # Geolocation service
└── utils/
    ├── logger.dart          # Logging utility
    ├── validators.dart      # Input validation
    └── extensions.dart      # Dart extensions
```

### `/lib/data`
Data layer - models, repositories, and data sources.

```
data/
├── models/
│   ├── photo.dart           # Photo data model
│   ├── profile.dart         # Profile data model
│   └── responses.dart       # API response models
├── repositories/
│   ├── photo_repository.dart
│   ├── profile_repository.dart
│   └── auth_repository.dart
└── datasources/
    ├── remote_datasource.dart
    └── local_datasource.dart
```

### `/lib/domain`
Domain layer - business logic and entities (optional for this app).

```
domain/
├── entities/
├── repositories/
└── usecases/
```

### `/lib/presentation`
Presentation layer - UI, state management, and routing.

```
presentation/
├── providers/               # Riverpod providers
│   ├── auth_provider.dart
│   ├── photo_provider.dart
│   ├── profile_provider.dart
│   ├── location_provider.dart
│   └── theme_provider.dart
├── screens/                 # Feature screens
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── splash_screen.dart
│   ├── home/
│   │   ├── dashboard_screen.dart
│   │   ├── map_screen.dart
│   │   └── widgets/
│   ├── upload/
│   │   ├── upload_screen.dart
│   │   └── widgets/
│   ├── profiles/
│   │   ├── profiles_screen.dart
│   │   ├── profile_detail_screen.dart
│   │   └── widgets/
│   ├── log/
│   │   ├── log_screen.dart
│   │   └── widgets/
│   └── settings/
│       └── settings_screen.dart
├── widgets/                 # Reusable widgets
│   ├── common/
│   │   ├── app_bar.dart
│   │   ├── bottom_nav.dart
│   │   ├── loading_skeleton.dart
│   │   └── error_widget.dart
│   ├── cards/
│   │   ├── photo_card.dart
│   │   ├── profile_card.dart
│   │   └── stat_card.dart
│   └── dialogs/
│       ├── confirm_dialog.dart
│       └── edit_dialog.dart
└── router/
    └── app_router.dart      # GoRouter configuration
```

## State Management with Riverpod

### Provider Types

#### 1. **Simple Providers** (Read-only)
```dart
final configProvider = Provider((ref) {
  return AppConfig();
});
```

#### 2. **Future Providers** (Async data)
```dart
final photosProvider = FutureProvider<List<Photo>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  return api.getPhotos();
});
```

#### 3. **State Notifier Providers** (Mutable state)
```dart
final themeProvider = StateNotifierProvider<ThemeNotifier, bool>((ref) {
  return ThemeNotifier();
});
```

#### 4. **Family Providers** (Parameterized)
```dart
final photoProvider = FutureProvider.family<Photo, int>((ref, photoId) async {
  final api = ref.watch(apiServiceProvider);
  return api.getPhoto(photoId);
});
```

### Provider Invalidation

Invalidate providers to trigger refetch:

```dart
// Invalidate single provider
ref.invalidate(photosProvider);

// Invalidate and wait for refresh
await ref.refresh(photosProvider.future);

// Invalidate multiple providers
ref.invalidate(photosProvider);
ref.invalidate(profilesProvider);
```

## API Integration

### Request Flow

```
UI (Widget)
    ↓
Riverpod Provider
    ↓
API Service
    ↓
Dio HTTP Client
    ↓
Interceptors (Auth, Logging, Error)
    ↓
Backend API
```

### Error Handling

```dart
try {
  final photos = await apiService.getPhotos();
} on DioException catch (e) {
  if (e.response?.statusCode == 401) {
    // Handle unauthorized
  } else if (e.type == DioExceptionType.connectionTimeout) {
    // Handle timeout
  }
} catch (e) {
  // Handle other errors
}
```

## Data Flow Example: Fetching Photos

```
1. User navigates to Dashboard
   ↓
2. Dashboard builds with photosProvider
   ↓
3. Riverpod calls FutureProvider
   ↓
4. Provider calls apiService.getPhotos()
   ↓
5. API Service makes HTTP request via Dio
   ↓
6. Interceptors add auth token, log request
   ↓
7. Backend returns photo list
   ↓
8. Response is cached in Riverpod
   ↓
9. UI rebuilds with photo data
```

## Caching Strategy

### In-Memory Cache (Riverpod)
- Automatic caching of provider results
- Invalidate to force refresh
- Configurable cache duration

### Local Storage (SharedPreferences)
- User preferences
- Auth tokens
- Last sync timestamp

### Hive (Optional)
- Offline photo cache
- Complex data structures
- Persistent storage

## Authentication Flow

```
1. User enters credentials
   ↓
2. API returns access token
   ↓
3. Token stored in secure storage
   ↓
4. AuthInterceptor adds token to requests
   ↓
5. On 401 response:
   - Clear token
   - Redirect to login
```

## Navigation with GoRouter

### Route Definition
```dart
GoRoute(
  path: '/photos/:id',
  name: 'photo_detail',
  builder: (context, state) {
    final id = state.pathParameters['id'];
    return PhotoDetailScreen(id: id);
  },
)
```

### Navigation
```dart
// Named route
context.goNamed('photo_detail', pathParameters: {'id': '123'});

// Path-based
context.go('/photos/123');

// Push (with back button)
context.push('/photos/123');
```

## Testing Strategy

### Unit Tests
- Test providers in isolation
- Mock API responses
- Test business logic

### Widget Tests
- Test UI components
- Test user interactions
- Test state updates

### Integration Tests
- Test full user flows
- Test API integration
- Test navigation

## Performance Optimization

### 1. **Lazy Loading**
```dart
ListView.builder(
  itemBuilder: (context, index) => PhotoCard(photo: photos[index]),
)
```

### 2. **Image Caching**
```dart
CachedNetworkImage(
  imageUrl: photo.imageUrl,
  cacheManager: customCacheManager,
)
```

### 3. **Provider Caching**
```dart
// Automatic caching with TTL
final photosProvider = FutureProvider((ref) async {
  // Results cached until invalidated
});
```

### 4. **Efficient Rebuilds**
- Use `ConsumerWidget` instead of `Consumer`
- Watch only needed providers
- Use `select` for partial updates

```dart
// Only rebuild when specific field changes
final userName = ref.watch(
  userProvider.select((user) => user.name),
);
```

## Best Practices

### 1. **Separation of Concerns**
- Keep UI logic in widgets
- Keep business logic in providers
- Keep data access in repositories

### 2. **Error Handling**
- Always handle errors in providers
- Show user-friendly error messages
- Log errors for debugging

### 3. **Code Organization**
- One feature per folder
- Group related files
- Use meaningful names

### 4. **Null Safety**
- Enable null safety
- Use `?` for nullable types
- Use `!` sparingly

### 5. **Documentation**
- Document complex logic
- Add comments for non-obvious code
- Keep README updated

## Debugging

### Enable Logging
```dart
// In main.dart
AppLogger.info('App started');
AppLogger.error('Error occurred', error);
```

### Riverpod DevTools
```bash
flutter pub add riverpod_generator
flutter pub run build_runner watch
```

### Network Logging
- Dio interceptors log all requests/responses
- Check console for API calls

## Deployment

### Android
```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
flutter build ipa --release
```

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Riverpod Documentation](https://riverpod.dev)
- [GoRouter Documentation](https://pub.dev/packages/go_router)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
