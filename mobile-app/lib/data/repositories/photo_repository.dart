import 'package:dio/dio.dart';

import '../models/photo_model.dart';

class PhotoRepository {

  PhotoRepository(this._dio);
  final Dio _dio;

  /// Get all photos
  Future<List<PhotoModel>> getPhotos() async {
    try {
      final response = await _dio.get('/api/photos');
      if (response.data is List) {
        return (response.data as List)
            .map((p) => PhotoModel.fromJson(p as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Upload a photo / pin attempt
  Future<PhotoModel> uploadPhoto({
    required String filePath,
    required int profileId,
    required double latitude,
    required double longitude,
    String? zipCode,
    String? address,
    String? note,
    String? category,
    String? completionType,    // e.g. Substitute | Personal
    String? servedTo,          // who service was served to
    int? payRate,              // F7
    String? takenAt,           // F6 device capture time (ISO)
    int? locationGroupId,      // F1 append to existing master pin
    int? userId,               // F8/F9
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'profile_id': profileId,
        'latitude': latitude,
        'longitude': longitude,
        if (zipCode != null && zipCode.isNotEmpty) 'zip_code': zipCode,
        if (address != null && address.isNotEmpty) 'address': address,
        if (note != null && note.isNotEmpty) 'note': note,
        if (category != null && category.isNotEmpty) 'category': category,
        if (completionType != null && completionType.isNotEmpty)
          'completion_type': completionType,
        if (servedTo != null && servedTo.isNotEmpty) 'served_to': servedTo,
        if (payRate != null) 'pay_rate': payRate,
        // F6: lock timestamp to device capture time
        'taken_at': takenAt ?? DateTime.now().toUtc().toIso8601String(),
        if (locationGroupId != null) 'location_group_id': locationGroupId,
        if (userId != null) 'user_id': userId,
      });

      final response = await _dio.post('/api/upload', data: formData);
      return PhotoModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update photo location
  Future<void> updatePhotoLocation({
    required int photoId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _dio.patch(
        '/api/photos/$photoId/location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update photo note
  Future<void> updatePhotoNote({
    required int photoId,
    required String note,
  }) async {
    try {
      await _dio.patch(
        '/api/photos/$photoId/note',
        data: {'note': note},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update photo zip code
  Future<void> updatePhotoZip({
    required int photoId,
    required String zipCode,
  }) async {
    try {
      await _dio.patch(
        '/api/photos/$photoId/zip',
        data: {'zip_code': zipCode},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update photo address and zip together
  Future<void> updatePhotoAddress({
    required int photoId,
    required String address,
    required String zipCode,
  }) async {
    try {
      await _dio.patch(
        '/api/photos/$photoId/address',
        data: {
          'address': address,
          if (zipCode.isNotEmpty) 'zip_code': zipCode,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update photo category (standard | special | next_day | asap)
  Future<void> updatePhotoCategory({
    required int photoId,
    required String category,
  }) async {
    try {
      await _dio.patch(
        '/api/photos/$photoId/category',
        data: {'category': category},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update photo profiles
  Future<void> updatePhotoProfiles({
    required int photoId,
    required List<int> profileIds,
  }) async {
    try {
      await _dio.patch(
        '/api/photos/$photoId/profiles',
        data: {'profile_ids': profileIds},
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Replace photo image
  Future<PhotoModel> replacePhotoImage({
    required int photoId,
    required String filePath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await _dio.patch(
        '/api/photos/$photoId/image',
        data: formData,
      );
      return PhotoModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Toggle favorite — returns the new is_favorited value
  Future<bool> toggleFavorite(int photoId) async {
    try {
      final response = await _dio.patch('/api/photos/$photoId/favorite');
      return response.data['is_favorited'] as bool? ?? false;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete a photo
  Future<void> deletePhoto(int photoId) async {
    try {
      await _dio.delete('/api/photos/$photoId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// F6 — edit the capture timestamp (server enforces the 10-min window with 423)
  Future<void> editTimestamp(int photoId, String isoTimestamp) async {
    try {
      await _dio.patch('/api/photos/$photoId/timestamp',
          data: {'timestamp': isoTimestamp});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// F10 — move a job through the lifecycle:
  /// open -> in_progress -> completed -> archived
  Future<void> updateStatus(int photoId, String status) async {
    try {
      await _dio.patch('/api/photos/$photoId/status',
          data: {'status': status});
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Exception _handleError(DioException e) {
    // Never expose raw DioException or technical strings to the user.
    if (e.response != null) {
      final statusCode = e.response!.statusCode ?? 0;
      // Try to get the backend's human-readable detail first
      final detail = e.response!.data is Map
          ? (e.response!.data['detail'] as String?)
          : null;

      switch (statusCode) {
        case 400:
          return Exception(detail ?? 'Invalid request. Please check your input.');
        case 401:
          return Exception('Session expired. Please log in again.');
        case 403:
          return Exception('You don\'t have permission to do that.');
        case 404:
          return Exception(detail ?? 'Not found. It may have been deleted.');
        case 408:
          return Exception('Request timed out. Check your connection and try again.');
        case 413:
          return Exception('Photo is too large. Please choose a smaller image.');
        case 422:
          return Exception(detail ?? 'Upload failed — missing required information.');
        case 423:
          return Exception(
              detail ?? 'Timestamp locked — the 10-minute edit window has passed.');
        case 429:
          return Exception('Too many requests. Please wait a moment and try again.');
        case 500:
        case 502:
        case 503:
          return Exception('Server error. Please try again in a moment.');
        default:
          return Exception(detail ?? 'Something went wrong (code $statusCode). Please try again.');
      }
    }

    // Network-level errors — no response received
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return Exception('Connection timed out. Check your signal and try again.');
      case DioExceptionType.connectionError:
        return Exception('No internet connection. Please check your network.');
      case DioExceptionType.cancel:
        return Exception('Upload was cancelled.');
      default:
        return Exception('Network error. Please check your connection and try again.');
    }
  }
}
