import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:photo_tracker/data/models/company.dart' show Company;

import '../../core/storage/api_cache.dart';
import '../../core/storage/local_storage.dart';
import '../../core/utils/file_number.dart';
import '../models/attempt.dart';
import '../models/photo_model.dart';
import '../models/profile_model.dart';

class ProfileRepository {

  ProfileRepository(this._dio);
  final Dio _dio;
  static const _cacheKey = 'profiles';

  /// Get all profiles. On a poor/dropped connection, falls back to the last
  /// successfully cached list instead of surfacing a network error.
  Future<List<ProfileModel>> getProfiles() async {
    try {
      final response = await _dio.get('/api/profiles');
      if (response.data is List) {
        final list = response.data as List;
        unawaited(ApiCache.write(_cacheKey, jsonEncode(list)));
        return list
            .map((p) => _hydrateFileNumber(
                ProfileModel.fromJson(p as Map<String, dynamic>)))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      final cached = ApiCache.read(_cacheKey);
      if (cached != null) {
        return (jsonDecode(cached) as List)
            .map((p) => _hydrateFileNumber(
                ProfileModel.fromJson(p as Map<String, dynamic>)))
            .toList();
      }
      throw _handleError(e);
    }
  }

  /// Create a new profile. Profile Location + [status] are entirely
  /// optional and independent of any attempt/upload — a profile can be
  /// created with only a name. [company] is the process-serving company
  /// slug (see [Company.id]).
  Future<ProfileModel> createProfile({
    required String name,
    required String serviceType,
    String? company,
    int? payRate,
    String? deliveryStyle,
    String? fileNumber,
    String? status,
    String? address,
    String? city,
    String? state,
    String? postalCode,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await _dio.post(
        '/api/profiles',
        data: {
          'name': name,
          'service_type': serviceType,
          if (company != null && company.isNotEmpty) 'company': company,
          if (payRate != null) 'pay_rate': payRate,
          if (deliveryStyle != null && deliveryStyle.isNotEmpty)
            'delivery_style': deliveryStyle,
          if (fileNumber != null && fileNumber.isNotEmpty)
            'file_number': fileNumber,
          'status': status,
          'address': address,
          'city': city,
          'state': state,
          'postal_code': postalCode,
          'latitude': latitude,
          'longitude': longitude,
        },
      );
      var profile = ProfileModel.fromJson(
        response.data as Map<String, dynamic>,
      );
      final submitted = (fileNumber ?? '').trim();
      if (submitted.isNotEmpty && (profile.fileNumber ?? '').trim().isEmpty) {
        try {
          await _dio.patch(
            '/api/profiles/${profile.id}',
            data: {'file_number': submitted},
          );
        } catch (_) {}
        profile = profile.copyWith(fileNumber: submitted);
      }
      final stored = (profile.fileNumber ?? submitted).trim();
      if (stored.isNotEmpty) {
        unawaited(LocalStorage.saveProfileFileNumber(profile.id, stored));
      }
      return _hydrateFileNumber(profile, submitted: submitted);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update a profile. Profile Location fields are always sent (even when
  /// null) so "Clear Location" can actually null them out on the server —
  /// this never touches Photo/Attempt rows.
  Future<void> updateProfile({
    required int profileId,
    required String name,
    required String serviceType,
    String? company,
    String? note,
    int? payRate,
    String? deliveryStyle,
    String? fileNumber,
    String? status,
    String? address,
    String? city,
    String? state,
    String? postalCode,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _dio.patch(
        '/api/profiles/$profileId',
        data: {
          'name': name,
          'service_type': serviceType,
          if (company != null && company.isNotEmpty) 'company': company,
          if (note != null) 'note': note,
          if (payRate != null) 'pay_rate': payRate,
          if (deliveryStyle != null) 'delivery_style': deliveryStyle,
          if (fileNumber != null) 'file_number': fileNumber,
          if (status != null) 'status': status,
          'address': address,
          'city': city,
          'state': state,
          'postal_code': postalCode,
          'latitude': latitude,
          'longitude': longitude,
        },
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> setProfileStatus({
    required int profileId,
    required String status,
  }) async {
    try {
      await _dio.patch(
        '/api/profiles/$profileId',
        data: {'status': status},
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

  /// Get photos for a profile (legacy).
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

  /// Attempts for a profile (newest first) — Profile → Attempt → Photos.
  Future<List<Attempt>> getProfileAttempts(int profileId) async {
    try {
      final response = await _dio.get('/api/profiles/$profileId/attempts');
      if (response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final rows = data['attempts'];
        if (rows is List) {
          var attempts = attemptsFromJsonList(rows);
          final rawProfile = data['profile'];
          if (rawProfile is Map<String, dynamic>) {
            final profile = _hydrateFileNumber(
              ProfileModel.fromJson(rawProfile),
            );
            final pfn = (profile.fileNumber ?? '').trim();
            if (pfn.isNotEmpty) {
              attempts = [
                for (final a in attempts)
                  isAbsentFileNumber(a.fileNumber)
                      ? Attempt(
                          id: a.id,
                          photos: a.photos,
                          profileId: a.profileId,
                          profileName: a.profileName,
                          attemptStatus: a.attemptStatus,
                          completionType: a.completionType,
                          note: a.note,
                          takenAt: a.takenAt,
                          timestamp: a.timestamp,
                          address: a.address,
                          category: a.category,
                          fileNumber: pfn,
                          status: a.status,
                          latitude: a.latitude,
                          longitude: a.longitude,
                          servedTo: a.servedTo,
                          relationTo: a.relationTo,
                          payRate: a.payRate,
                        )
                      : a,
              ];
            }
          }
          return attempts;
        }
      }
      // Fallback to legacy photos endpoint.
      final photos = await getProfilePhotos(profileId);
      return attemptsFromPhotos(photos);
    } on DioException catch (e) {
      try {
        final photos = await getProfilePhotos(profileId);
        return attemptsFromPhotos(photos);
      } catch (_) {
        throw _handleError(e);
      }
    }
  }

  /// Duplicate an attempt onto other profiles (distinct DB rows).
  Future<int> duplicateAttempt({
    required int attemptId,
    required List<int> profileIds,
  }) async {
    try {
      final response = await _dio.post(
        '/api/attempts/$attemptId/duplicate',
        data: {'profile_ids': profileIds},
      );
      if (response.data is Map) {
        return (response.data['duplicated'] as num?)?.toInt() ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ProfileModel _hydrateFileNumber(ProfileModel p, {String? submitted}) {
    var fn = (p.fileNumber ?? '').trim();
    if (fn.isEmpty) fn = (submitted ?? '').trim();
    if (fn.isEmpty) {
      fn = LocalStorage.fileNumberForProfile(p.id) ?? '';
    }
    if (fn.isEmpty) return p;
    unawaited(LocalStorage.saveProfileFileNumber(p.id, fn));
    if (fn == (p.fileNumber ?? '').trim()) return p;
    return p.copyWith(fileNumber: fn);
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
        case 404: return Exception(detail ?? 'Profile not found.');
        case 409: return Exception(detail ?? 'This file number already exists');
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
