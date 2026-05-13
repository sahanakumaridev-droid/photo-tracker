import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import 'interceptors.dart';

/// Dio HTTP client provider
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

/// API Service provider
final apiServiceProvider = Provider<ApiService>((ref) {
  final dio = ref.watch(dioProvider);
  return ApiService(dio);
});

/// API Service class
class ApiService {

  ApiService(this._dio);
  final Dio _dio;

  // ─── Profile Endpoints ───────────────────────────────────────────────────

  /// Get all profiles
  Future<List<ProfileResponse>> getProfiles() async {
    try {
      final response = await _dio.get('/api/profiles');
      if (response.data is List) {
        return (response.data as List)
            .map((p) => ProfileResponse.fromJson(p as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('data') && data['data'] is List) {
          return (data['data'] as List)
              .map((p) => ProfileResponse.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Create a new profile
  Future<ProfileResponse> createProfile({
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
      return ProfileResponse.fromJson(response.data);
    } catch (e) {
      rethrow;
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
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a profile
  Future<void> deleteProfile(int profileId) async {
    try {
      await _dio.delete('/api/profiles/$profileId');
    } catch (e) {
      rethrow;
    }
  }

  /// Get photos for a profile
  Future<ProfilePhotosResponse> getProfilePhotos(int profileId) async {
    try {
      final response = await _dio.get('/api/profiles/$profileId/photos');
      return ProfilePhotosResponse.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // ─── Photo Endpoints ─────────────────────────────────────────────────────

  /// Get all photos
  Future<List<PhotoResponse>> getPhotos() async {
    try {
      final response = await _dio.get('/api/photos');
      if (response.data is List) {
        return (response.data as List)
            .map((p) => PhotoResponse.fromJson(p as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('data') && data['data'] is List) {
          return (data['data'] as List)
              .map((p) => PhotoResponse.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  /// Upload a photo
  Future<PhotoResponse> uploadPhoto({
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
      return PhotoResponse.fromJson(response.data);
    } catch (e) {
      rethrow;
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
    } catch (e) {
      rethrow;
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
    } catch (e) {
      rethrow;
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
    } catch (e) {
      rethrow;
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
    } catch (e) {
      rethrow;
    }
  }

  /// Replace photo image
  Future<PhotoResponse> replacePhotoImage({
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
      return PhotoResponse.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a photo
  Future<void> deletePhoto(int photoId) async {
    try {
      await _dio.delete('/api/photos/$photoId');
    } catch (e) {
      rethrow;
    }
  }

  // ─── Log Endpoints ──────────────────────────────────────────────────────

  /// Get activity log with filters
  Future<List<PhotoResponse>> getLog({
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
            .map((p) => PhotoResponse.fromJson(p as Map<String, dynamic>))
            .toList();
      } else if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('data') && data['data'] is List) {
          return (data['data'] as List)
              .map((p) => PhotoResponse.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      rethrow;
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
    } catch (e) {
      rethrow;
    }
  }
}

// ─── Response Models ────────────────────────────────────────────────────────

class ProfileResponse {

  ProfileResponse({
    required this.id,
    required this.name,
    required this.serviceType,
    this.note,
  });

  factory ProfileResponse.fromJson(Map<String, dynamic> json) =>
      ProfileResponse(
        id: json['id'] as int,
        name: json['name'] as String,
        serviceType: json['service_type'] as String? ?? 'standard',
        note: json['note'] as String?,
      );
  final int id;
  final String name;
  final String serviceType;
  final String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'service_type': serviceType,
        'note': note,
      };
}

class PhotoResponse {

  PhotoResponse({
    required this.id,
    required this.imageUrl,
    required this.latitude, required this.longitude, this.timestamp,
    this.zipCode,
    this.note,
    this.profileId,
    this.profileName,
    this.serviceType,
    this.profiles,
  });

  factory PhotoResponse.fromJson(Map<String, dynamic> json) =>
      PhotoResponse(
        id: json['id'] as int,
        imageUrl: json['image_url'] as String,
        timestamp: json['timestamp'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        zipCode: json['zip_code'] as String?,
        note: json['note'] as String?,
        profileId: json['profile_id'] as int?,
        profileName: json['profile_name'] as String?,
        serviceType: json['service_type'] as String?,
        profiles: (json['profiles'] as List?)
            ?.map((p) => ProfileResponse.fromJson(p))
            .toList(),
      );
  final int id;
  final String imageUrl;
  final String? timestamp;
  final double latitude;
  final double longitude;
  final String? zipCode;
  final String? note;
  final int? profileId;
  final String? profileName;
  final String? serviceType;
  final List<ProfileResponse>? profiles;

  Map<String, dynamic> toJson() => {
        'id': id,
        'image_url': imageUrl,
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
        'zip_code': zipCode,
        'note': note,
        'profile_id': profileId,
        'profile_name': profileName,
        'service_type': serviceType,
        'profiles': profiles?.map((p) => p.toJson()).toList(),
      };
}

class ProfilePhotosResponse {

  ProfilePhotosResponse({
    required this.profile,
    required this.photos,
  });

  factory ProfilePhotosResponse.fromJson(Map<String, dynamic> json) =>
      ProfilePhotosResponse(
        profile: ProfileResponse.fromJson(json['profile']),
        photos: (json['photos'] as List)
            .map((p) => PhotoResponse.fromJson(p))
            .toList(),
      );
  final ProfileResponse profile;
  final List<PhotoResponse> photos;
}
