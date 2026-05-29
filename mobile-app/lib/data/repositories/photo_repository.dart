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

  /// Upload a photo
  Future<PhotoModel> uploadPhoto({
    required String filePath,
    required int profileId,
    required double latitude,
    required double longitude,
    String? zipCode,
    String? address,
    String? note,
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

  /// Delete a photo
  Future<void> deletePhoto(int photoId) async {
    try {
      await _dio.delete('/api/photos/$photoId');
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
