import 'package:dio/dio.dart';

import '../models/log_entry_model.dart';

class LogRepository {

  LogRepository(this._dio);
  final Dio _dio;

  /// Get activity log with filters
  Future<List<LogEntryModel>> getLog({
    String? date,
    String? startTime,
    String? endTime,
    String? zipCode,
    String? status,
    String? search,
  }) async {
    try {
      final response = await _dio.get(
        '/api/log',
        queryParameters: {
          if (date != null) 'date': date,
          if (startTime != null) 'start_time': startTime,
          if (endTime != null) 'end_time': endTime,
          if (zipCode != null) 'zip_code': zipCode,
          if (status != null) 'status': status,
          if (search != null) 'search': search,
        },
      );
      if (response.data is List) {
        return (response.data as List)
            .map((p) => LogEntryModel.fromJson(p as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Export log to email
  Future<void> exportLogEmail({
    required String email,
    required List<Map<String, dynamic>> records,
  }) async {
    try {
      await _dio.post(
        '/api/export/email',
        data: {
          'to': email,
          'records': records,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode ?? 0;
      final detail = e.response!.data is Map
          ? (e.response!.data['detail'] as String?)
          : null;
      switch (statusCode) {
        case 401: return Exception('Session expired. Please log in again.');
        case 403: return Exception('You don\'t have permission to do that.');
        case 404: return Exception(detail ?? 'Not found.');
        case 422: return Exception(detail ?? 'Invalid data. Please check your input.');
        case 500:
        case 502:
        case 503: return Exception('Server error. Please try again in a moment.');
        default:  return Exception(detail ?? 'Something went wrong. Please try again.');
      }
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timed out. Check your signal and try again.');
      case DioExceptionType.connectionError:
        return Exception('No internet connection. Please check your network.');
      default:
        return Exception('Network error. Please check your connection and try again.');
    }
  }
}
