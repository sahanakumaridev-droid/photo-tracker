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
    String? note,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'profile_id': profileId,
        'latitude': latitude,
        'longitude': longitude,
        if (zipCode != null && zipCode.isNotEmpty) 'zip_code': zipCode,
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
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final message = e.response!.data?['detail'] ?? 'Unknown error';
      return Exception('Error $statusCode: $message');
    }
    return Exception(e.message ?? 'Network error');
  }
}
