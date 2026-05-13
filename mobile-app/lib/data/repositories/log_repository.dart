import 'package:dio/dio.dart';

import '../models/log_entry_model.dart';

class LogRepository {

  LogRepository(this._dio);
  final Dio _dio;

  /// Get activity log with filters
  Future<List<LogEntryModel>> getLog({
    String? date,
    String? zipCode,
    String? status,
    String? search,
  }) async {
    try {
      final response = await _dio.get(
        '/api/log',
        queryParameters: {
          if (date != null) 'date': date,
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
      final statusCode = e.response!.statusCode;
      final message = e.response!.data?['detail'] ?? 'Unknown error';
      return Exception('Error $statusCode: $message');
    }
    return Exception(e.message ?? 'Network error');
  }
}
