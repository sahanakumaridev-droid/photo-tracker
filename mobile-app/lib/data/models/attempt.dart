import 'package:intl/intl.dart';

import '../../core/utils/attempt_status.dart';
import 'photo_model.dart';

/// A service attempt belonging to a profile.
///
/// Wire shape: Profile 1──* Attempt 1──* Photo. Legacy clients still wrap a
/// single [PhotoModel]; prefer [Attempt.fromJson] when the attempts API is
/// available.
class Attempt {
  const Attempt({
    required this.id,
    required this.photos,
    this.profileId,
    this.profileName,
    this.attemptStatus = kDefaultAttemptStatus,
    this.completionType,
    this.note,
    this.takenAt,
    this.timestamp,
    this.address,
    this.category,
    this.fileNumber,
    this.status,
    this.latitude,
    this.longitude,
    this.servedTo,
    this.relationTo,
    this.payRate,
  });

  /// Legacy: one photo == one attempt.
  factory Attempt.fromPhoto(PhotoModel photo) => Attempt(
        id: photo.attemptId ?? photo.id,
        photos: [photo],
        profileId: photo.profileId,
        profileName: photo.profileName,
        attemptStatus: attemptStatusFromLegacy(
          attemptStatus: photo.attemptStatus,
          successful: photo.successful,
        ),
        completionType: photo.completionType,
        note: photo.note,
        takenAt: photo.takenAt,
        timestamp: photo.timestamp,
        address: photo.address,
        category: photo.category,
        fileNumber: photo.fileNumber,
        status: photo.status,
        latitude: photo.latitude,
        longitude: photo.longitude,
        servedTo: photo.servedTo,
        relationTo: photo.relationTo,
        payRate: photo.payRate,
      );

  factory Attempt.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    final photos = <PhotoModel>[];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        if (p is Map<String, dynamic>) {
          // Nested media may omit lat/lng — fill from attempt.
          final merged = {
            'id': p['id'] ?? 0,
            'image_url': p['image_url'] ?? json['image_url'] ?? '',
            'latitude': p['latitude'] ?? json['latitude'] ?? 0,
            'longitude': p['longitude'] ?? json['longitude'] ?? 0,
            'taken_at': p['taken_at'] ?? json['taken_at'],
            'timestamp': p['timestamp'] ?? json['timestamp'],
            'attempt_id': json['id'],
            'attempt_status': json['attempt_status'],
            'successful': json['successful'],
            'note': json['note'],
            'address': json['address'],
            'category': json['category'],
            'completion_type': json['completion_type'],
            'file_number': json['file_number'],
            'profile_id': json['profile_id'],
            'profile_name': json['profile_name'],
            'served_to': json['served_to'],
            'relation_to': json['relation_to'],
            'pay_rate': json['pay_rate'],
            'status': json['status'],
            'is_favorited': p['is_favorited'] ?? false,
          };
          photos.add(PhotoModel.fromJson(merged));
        }
      }
    }
    if (photos.isEmpty && json['image_url'] != null) {
      photos.add(PhotoModel.fromJson({
        'id': json['photo_id'] ?? json['id'] ?? 0,
        'image_url': json['image_url'],
        'latitude': json['latitude'] ?? 0,
        'longitude': json['longitude'] ?? 0,
        'taken_at': json['taken_at'],
        'timestamp': json['timestamp'],
        'attempt_id': json['id'],
        'attempt_status': json['attempt_status'],
        'successful': json['successful'],
        'note': json['note'],
        'address': json['address'],
        'category': json['category'],
        'completion_type': json['completion_type'],
        'file_number': json['file_number'],
        'profile_id': json['profile_id'],
        'profile_name': json['profile_name'],
        'status': json['status'],
      }));
    }
    return Attempt(
      id: (json['id'] as num).toInt(),
      photos: photos,
      profileId: (json['profile_id'] as num?)?.toInt(),
      profileName: json['profile_name'] as String?,
      attemptStatus: attemptStatusFromLegacy(
        attemptStatus: json['attempt_status'] as String?,
        successful: json['successful'] as bool?,
      ),
      completionType: json['completion_type'] as String?,
      note: json['note'] as String?,
      takenAt: json['taken_at'] as String?,
      timestamp: json['timestamp'] as String?,
      address: json['address'] as String?,
      category: json['category'] as String?,
      fileNumber: json['file_number'] as String?,
      status: json['status'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      servedTo: json['served_to'] as String?,
      relationTo: json['relation_to'] as String?,
      payRate: (json['pay_rate'] as num?)?.toInt(),
    );
  }

  final int id;
  final List<PhotoModel> photos;
  final int? profileId;
  final String? profileName;
  final String attemptStatus;
  final String? completionType;
  final String? note;
  final String? takenAt;
  final String? timestamp;
  final String? address;
  final String? category;
  final String? fileNumber;
  final String? status;
  final double? latitude;
  final double? longitude;
  final String? servedTo;
  final String? relationTo;
  final int? payRate;

  /// Primary photo for navigation / thumbnail.
  PhotoModel? get primaryPhoto => photos.isEmpty ? null : photos.first;

  int get photoId => primaryPhoto?.id ?? id;

  AttemptStatusOption get statusOption =>
      attemptStatusByValue(attemptStatus) ?? kAttemptStatuses.first;

  String get title {
    final style = (completionType ?? '').trim();
    if (style.isNotEmpty) return style;
    switch (attemptStatus) {
      case kAttemptStatusSuccessful:
        return 'Successful Attempt';
      case kAttemptStatusUnsuccessful:
        final n = (note ?? '').toLowerCase();
        if (n.contains('bad address')) return 'Bad Address';
        return 'Unsuccessful Attempt';
      default:
        return 'Pending Attempt';
    }
  }

  String get noteSnippet {
    final n = (note ?? '').trim();
    if (n.isEmpty) {
      final count = photos.length;
      return count > 1 ? '$count photos' : 'No notes';
    }
    if (n.length <= 90) return n;
    return '${n.substring(0, 87).trimRight()}...';
  }

  String? get rawTimestamp => takenAt ?? timestamp;

  DateTime? get occurredAt {
    final raw = rawTimestamp;
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  String get displayTimestamp {
    final dt = occurredAt;
    if (dt == null) return '';
    return DateFormat('MMM d, yyyy, h:mm a').format(dt);
  }

  bool get successful => attemptStatus == kAttemptStatusSuccessful;

  String get sortKey => rawTimestamp ?? '';
}

/// Convert attempt API rows → sorted newest → oldest.
List<Attempt> attemptsFromJsonList(Iterable<dynamic> rows) {
  final list = <Attempt>[];
  for (final row in rows) {
    if (row is Map<String, dynamic>) {
      list.add(Attempt.fromJson(row));
    }
  }
  list.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return list;
}

/// Legacy: photos → attempts (one photo each), newest first.
List<Attempt> attemptsFromPhotos(Iterable<PhotoModel> photos) {
  final list = photos.map(Attempt.fromPhoto).toList(growable: false);
  return List<Attempt>.from(list)
    ..sort((a, b) => b.sortKey.compareTo(a.sortKey));
}
