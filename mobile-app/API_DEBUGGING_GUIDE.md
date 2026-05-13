# API Debugging Guide

## Issues Fixed

### 1. **Error Handling in Repositories** ✅
**Problem**: Repositories were throwing `String` instead of `Exception`
**Solution**: Updated all repositories to throw proper `Exception` objects

**Files Fixed**:
- `lib/data/repositories/profile_repository.dart`
- `lib/data/repositories/photo_repository.dart`
- `lib/data/repositories/log_repository.dart`

**Before**:
```dart
String _handleError(DioException e) {
  return 'Error: $message';  // ❌ Throwing String
}
```

**After**:
```dart
Exception _handleError(DioException e) {
  return Exception('Error: $message');  // ✅ Throwing Exception
}
```

---

## API Configuration

### Server URL
```
Base URL: http://24.199.85.230
```

### Configuration File
**Location**: `lib/config/app_config.dart`

```dart
class AppConfig {
  static const String apiBaseUrl = 'http://24.199.85.230';
  static const int apiTimeout = 30; // seconds
  static const int apiRetryCount = 3;
}
```

### Dio Setup
**Location**: `lib/core/network/api_client.dart`

```dart
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.getApiBaseUrl(),
      connectTimeout: const Duration(seconds: AppConfig.apiTimeout),
      receiveTimeout: const Duration(seconds: AppConfig.apiTimeout),
      contentType: 'application/json',
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  // Add interceptors
  dio.interceptors.add(LoggingInterceptor());
  dio.interceptors.add(AuthInterceptor());
  dio.interceptors.add(ErrorInterceptor());

  return dio;
});
```

---

## API Endpoints

### Profile Endpoints
```
GET    /profiles              - Get all profiles
POST   /profiles              - Create new profile
GET    /profiles/{id}/photos  - Get profile photos
PATCH  /profiles/{id}         - Update profile
DELETE /profiles/{id}         - Delete profile
```

### Photo Endpoints
```
GET    /photos                - Get all photos
POST   /upload                - Upload photo
PATCH  /photos/{id}/location  - Update location
PATCH  /photos/{id}/note      - Update note
PATCH  /photos/{id}/zip       - Update zip code
PATCH  /photos/{id}/profiles  - Update profiles
PATCH  /photos/{id}/image     - Replace image
DELETE /photos/{id}           - Delete photo
```

### Log Endpoints
```
GET    /log                   - Get activity log
POST   /export/email          - Export log to email
```

---

## Testing API Connectivity

### Quick Test Script
Run the test script to verify API connectivity:

```bash
dart test_api.dart
```

This will test:
- Server connection
- GET /profiles
- POST /profiles (create)
- GET /photos

### Expected Output
```
🔍 Testing API Connection...

📡 Testing GET /profiles...
✅ SUCCESS - Status: 200
   Response: [...]

📡 Testing POST /profiles (Create)...
✅ SUCCESS - Status: 201
   Response: {...}

📡 Testing GET /photos...
✅ SUCCESS - Status: 200
   Response: [...]

✅ API Test Complete
```

---

## Interceptors

### 1. LoggingInterceptor
Logs all API requests and responses

```dart
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.info('→ ${options.method} ${options.path}');
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    AppLogger.info('← ${response.statusCode} ${response.requestOptions.path}');
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.error('✗ ${err.requestOptions.method} ${err.requestOptions.path}');
    super.onError(err, handler);
  }
}
```

### 2. AuthInterceptor
Adds authentication token to requests

```dart
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await LocalStorage.getAuthToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      AppLogger.warning('Unauthorized - clearing auth token');
      await LocalStorage.clearAuthToken();
    }
    super.onError(err, handler);
  }
}
```

### 3. ErrorInterceptor
Handles and transforms API errors

```dart
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final exception = _handleError(err);
    super.onError(exception, handler);
  }

  DioException _handleError(DioException error) {
    var message = 'An error occurred';

    if (error.type == DioExceptionType.connectionTimeout) {
      message = 'Connection timeout';
    } else if (error.type == DioExceptionType.receiveTimeout) {
      message = 'Receive timeout';
    } else if (error.type == DioExceptionType.badResponse) {
      final statusCode = error.response?.statusCode;
      // Handle different status codes
      if (statusCode == 400) message = 'Bad request';
      else if (statusCode == 401) message = 'Unauthorized';
      else if (statusCode == 404) message = 'Not found';
      else if (statusCode == 500) message = 'Server error';
    }

    return error.copyWith(message: message);
  }
}
```

---

## Common API Errors

### 400 Bad Request
**Cause**: Invalid request data
**Solution**: Check request parameters and data format

### 401 Unauthorized
**Cause**: Missing or invalid authentication token
**Solution**: Login again to get a new token

### 404 Not Found
**Cause**: Resource doesn't exist
**Solution**: Check the resource ID and endpoint

### 422 Validation Error
**Cause**: Invalid data format
**Solution**: Check field types and required fields

### 500 Server Error
**Cause**: Server-side error
**Solution**: Check server logs and retry

### Connection Timeout
**Cause**: Server not responding
**Solution**: Check server is running and network connection

---

## Debugging Tips

### 1. Enable Logging
Check `lib/core/utils/logger.dart` to enable debug logging

### 2. Check Network Interceptors
Verify interceptors are added in correct order:
1. LoggingInterceptor (first)
2. AuthInterceptor
3. ErrorInterceptor (last)

### 3. Verify Server URL
Make sure server URL is correct in `app_config.dart`:
```dart
static const String apiBaseUrl = 'http://24.199.85.230';
```

### 4. Check Request/Response Format
Use logging to see exact request and response data

### 5. Test with curl
Test endpoints directly with curl:
```bash
# Get profiles
curl -X GET http://24.199.85.230/profiles

# Create profile
curl -X POST http://24.199.85.230/profiles \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","service_type":"standard"}'
```

---

## Repository Pattern

### Profile Repository
```dart
class ProfileRepository {
  final Dio _dio;

  ProfileRepository(this._dio);

  Future<List<ProfileModel>> getProfiles() async {
    try {
      final response = await _dio.get('/profiles');
      // Parse response
      return profiles;
    } on DioException catch (e) {
      throw _handleError(e);  // ✅ Throws Exception
    }
  }

  Exception _handleError(DioException e) {
    // Handle error and return Exception
    return Exception('Error: $message');
  }
}
```

### Provider Pattern
```dart
final profilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getProfiles();
});
```

---

## Testing Checklist

- [ ] Server is running at http://24.199.85.230
- [ ] Network connection is active
- [ ] API base URL is correct in app_config.dart
- [ ] Interceptors are properly configured
- [ ] Error handling returns Exception objects
- [ ] Repositories are properly initialized
- [ ] Providers are watching repositories correctly
- [ ] Screens are watching providers correctly
- [ ] Test API connectivity with test_api.dart
- [ ] Check logs for API requests/responses

---

## Files Modified

1. `lib/data/repositories/profile_repository.dart` - Fixed error handling
2. `lib/data/repositories/photo_repository.dart` - Fixed error handling
3. `lib/data/repositories/log_repository.dart` - Fixed error handling

---

## Next Steps

1. Run `dart test_api.dart` to verify connectivity
2. Check logs for any API errors
3. Test each endpoint individually
4. Verify data is being parsed correctly
5. Test on actual device/emulator

---

**Status**: ✅ API Error Handling Fixed
**Date**: May 12, 2026
