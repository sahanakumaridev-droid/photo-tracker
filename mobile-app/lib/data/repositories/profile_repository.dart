import 'package:dio/dio.dart';

import '../models/photo_model.dart';
import '../models/profile_model.dart';

class ProfileRepository {

  ProfileRepository(this._dio);
  final Dio _dio;

  /// Get all profiles
  Future<List<ProfileModel>> getProfiles() async {
    try {
      final response = await _dio.get('/api/profiles');
      if (response.data is List) {
        return (response.data as List)
            .map((p) => ProfileModel.fromJson(p as Map<String, dynamic>))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Create a new profile
  Future<ProfileModel> createProfile({
    required String name,
    required String serviceType,
  }) async {
    try {
      final response = await _dio.post(
        '/api/profiles',
        data: {
          'name': name,
          'service_type': serviceType,
        },
      );
      return ProfileModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update a profile
  Future<void> updateProfile({
    required int profileId,
    required String name,
    required String serviceType,
    String? note,
  }) async {
    try {
      await _dio.patch(
        '/api/profiles/$profileId',
        data: {
          'name': name,
          'service_type': serviceType,
          if (note != null) 'note': note,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    try {
      await _dio.delete('/api/profiles/$profileId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get photos for a profile
  Future<List<PhotoModel>> getProfilePhotos(int profileId) async {
    try {
      final response = await _dio.get('/api/profiles/$profileId/photos');
      if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('photos') && data['photos'] is List) {
          return (data['photos'] as List)
              .map((p) => PhotoModel.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
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
