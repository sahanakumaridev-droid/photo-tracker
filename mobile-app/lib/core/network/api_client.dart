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

  /// Get all photos, optionally sorted by distance from [userLat]/[userLng]
  Future<List<PhotoResponse>> getPhotos({
    double? userLat,
    double? userLng,
  }) async {
    try {
      final response = await _dio.get('/api/photos', queryParameters: {
        if (userLat != null) 'user_lat': userLat,
        if (userLng != null) 'user_lng': userLng,
      });
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

  /// Upload a photo / pin attempt
  Future<PhotoResponse> uploadPhoto({
    required String filePath,
    required int profileId,
    required double latitude,
    required double longitude,
    String? zipCode,
    String? note,
    String? address,
    String? category,          // F2/F4 service level
    int? payRate,              // F7 pay rate (whole dollars)
    String? takenAt,           // F6 device capture time (ISO)
    int? locationGroupId,      // F1 append to existing master pin
    int? userId,               // F8/F9 attribution
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'profile_id': profileId,
        'latitude': latitude,
        'longitude': longitude,
        if (zipCode != null && zipCode.isNotEmpty) 'zip_code': zipCode,
        if (note != null && note.isNotEmpty) 'note': note,
        if (address != null && address.isNotEmpty) 'address': address,
        if (category != null && category.isNotEmpty) 'category': category,
        if (payRate != null) 'pay_rate': payRate,
        // F6: lock timestamp to capture time; default to now if not supplied
        'taken_at': takenAt ?? DateTime.now().toUtc().toIso8601String(),
        if (locationGroupId != null) 'location_group_id': locationGroupId,
        if (userId != null) 'user_id': userId,
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

  // ─── F1: nearby detection + attempt history ───────────────────────────────

  /// Existing master pins within [radiusFt] feet of a coordinate.
  Future<List<Map<String, dynamic>>> getNearby({
    required double latitude,
    required double longitude,
    double radiusFt = 100,
  }) async {
    final response = await _dio.get('/api/locations/nearby', queryParameters: {
      'lat': latitude, 'lng': longitude, 'radius_ft': radiusFt,
    });
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  /// Master pins, optionally filtered by service levels / status.
  Future<List<Map<String, dynamic>>> getLocations({
    List<String>? serviceLevels,
    String? status,
  }) async {
    final response = await _dio.get('/api/locations', queryParameters: {
      if (serviceLevels != null && serviceLevels.isNotEmpty)
        'service_levels': serviceLevels.join(','),
      if (status != null) 'status': status,
    });
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  /// Full attempt history for one master pin.
  Future<Map<String, dynamic>> getAttempts(int groupId) async {
    final response = await _dio.get('/api/locations/$groupId/attempts');
    return response.data as Map<String, dynamic>;
  }

  // ─── F4: scheduling queues ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSchedule({
    String? queue,
    double? userLat,
    double? userLng,
  }) async {
    final response = await _dio.get('/api/schedule', queryParameters: {
      if (queue != null) 'queue': queue,
      if (userLat != null) 'user_lat': userLat,
      if (userLng != null) 'user_lng': userLng,
    });
    return response.data as Map<String, dynamic>;
  }

  // ─── F6: timestamp edit (10-min window) + audit ───────────────────────────

  Future<void> editTimestamp({
    required int photoId,
    required String timestamp,
    int? userId,
  }) async {
    await _dio.patch('/api/photos/$photoId/timestamp',
        data: {'timestamp': timestamp, if (userId != null) 'user_id': userId});
  }

  Future<Map<String, dynamic>> getTimestampHistory(int photoId) async {
    final response = await _dio.get('/api/photos/$photoId/timestamp-history');
    return response.data as Map<String, dynamic>;
  }

  // ─── F7: pay rate ─────────────────────────────────────────────────────────

  Future<void> updatePayRate({required int photoId, required int payRate}) async {
    await _dio.patch('/api/photos/$photoId/pay-rate', data: {'pay_rate': payRate});
  }

  // ─── F10: archive / status workflow ───────────────────────────────────────

  Future<void> updateStatus({required int photoId, required String status}) async {
    await _dio.patch('/api/photos/$photoId/status', data: {'status': status});
  }

  /// Job list for the Archive screen.
  /// [status] ∈ active (open + in_progress) | open | in_progress | completed | archived
  Future<List<Map<String, dynamic>>> getArchive(
      {String? search, String? serviceLevel, String status = 'archived'}) async {
    final response = await _dio.get('/api/archive', queryParameters: {
      if (search != null) 'search': search,
      if (serviceLevel != null) 'service_level': serviceLevel,
      'status': status,
    });
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  // ─── F8 / F9: earnings + payouts ──────────────────────────────────────────

  /// F9 — earnings summary. Pass [startDate]/[endDate] (YYYY-MM-DD) for a
  /// custom range; this overrides [period] on the server.
  Future<Map<String, dynamic>> getEarnings({
    String period = 'today',
    int? userId,
    String? startDate,
    String? endDate,
  }) async {
    final response = await _dio.get('/api/earnings/summary', queryParameters: {
      'period': period,
      if (userId != null) 'user_id': userId,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPayouts({int? userId}) async {
    final response = await _dio.get('/api/payouts',
        queryParameters: {if (userId != null) 'user_id': userId});
    return response.data as Map<String, dynamic>;
  }

  // ─── F5: draft auto-save ──────────────────────────────────────────────────

  Future<String> saveDraft({
    required String id,
    required Map<String, dynamic> payload,
    int? userId,
  }) async {
    final response = await _dio.put('/api/drafts',
        data: {'id': id, 'payload': payload, if (userId != null) 'user_id': userId});
    return (response.data as Map<String, dynamic>)['id'] as String;
  }

  Future<List<Map<String, dynamic>>> getDrafts({int? userId}) async {
    final response = await _dio.get('/api/drafts',
        queryParameters: {if (userId != null) 'user_id': userId});
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteDraft(String id) async {
    await _dio.delete('/api/drafts/$id');
  }

  // ─── F11: saved recipients + Excel export ─────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecipients({int? userId}) async {
    final response = await _dio.get('/api/recipients',
        queryParameters: {if (userId != null) 'user_id': userId});
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> addRecipient({required String email, String? label, int? userId}) async {
    final response = await _dio.post('/api/recipients', data: {
      'email': email, if (label != null) 'label': label, if (userId != null) 'user_id': userId,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> editRecipient(int id,
      {String? email, String? label}) async {
    final response = await _dio.patch('/api/recipients/$id', data: {
      if (email != null) 'email': email,
      if (label != null) 'label': label,
    });
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteRecipient(int id) async {
    await _dio.delete('/api/recipients/$id');
  }

  /// F11: generate an Excel file server-side and email to recipients.
  Future<Map<String, dynamic>> exportExcel({
    required List<String> recipients,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _dio.post('/api/export/excel',
        data: {'recipients': recipients, 'records': records});
    return response.data as Map<String, dynamic>;
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
