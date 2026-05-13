import 'package:dio/dio.dart';
import '../storage/local_storage.dart';
import '../utils/logger.dart';

/// Logging interceptor for debugging
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.info('→ ${options.method} ${options.path}');
    if (options.data != null) {
      AppLogger.debug('  Data: ${options.data}');
    }
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
    AppLogger.error('  Error: ${err.message}');
    super.onError(err, handler);
  }
}

/// Authentication interceptor
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Add auth token if available
    final token = await LocalStorage.getAuthToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Handle 401 Unauthorized
    if (err.response?.statusCode == 401) {
      AppLogger.warning('Unauthorized - clearing auth token');
      await LocalStorage.clearAuthToken();
    }
    super.onError(err, handler);
  }
}

/// Error handling interceptor
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Transform DioException to custom exception
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
      final responseData = error.response?.data;

      if (statusCode == 400) {
        message = 'Bad request';
      } else if (statusCode == 401) {
        message = 'Unauthorized';
      } else if (statusCode == 403) {
        message = 'Forbidden';
      } else if (statusCode == 404) {
        message = 'Not found';
      } else if (statusCode == 422) {
        message = 'Validation error';
      } else if (statusCode == 500) {
        message = 'Server error';
      } else {
        message = 'Error: $statusCode';
      }

      // Try to extract error message from response
      if (responseData is Map && responseData.containsKey('detail')) {
        message = responseData['detail'];
      }
    } else if (error.type == DioExceptionType.unknown) {
      message = 'Network error';
    }

    AppLogger.error('API Error: $message');
    return error.copyWith(message: message);
  }
}
