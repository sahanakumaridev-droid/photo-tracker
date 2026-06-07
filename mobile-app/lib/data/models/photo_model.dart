import 'package:json_annotation/json_annotation.dart';

import '../../config/app_config.dart';
import 'profile_model.dart';

part 'photo_model.g.dart';

@JsonSerializable()
class PhotoModel {

  PhotoModel({
    required this.id,
    required this.imageUrl,
    required this.latitude, required this.longitude, this.timestamp,
    this.zipCode,
    this.address,
    this.note,
    this.profileId,
    this.profileName,
    this.serviceType,
    this.category,
    this.profiles,
    this.isFavorited = false,
    this.payRate,
    this.status,
    this.takenAt,
    this.locationGroupId,
    this.userId,
    this.completedAt,
  });

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    final raw = _$PhotoModelFromJson(json);
    // Fix relative image_url to full URL
    final imageUrl = raw.imageUrl.startsWith('http')
        ? raw.imageUrl
        : '${AppConfig.apiBaseUrl}${raw.imageUrl}';
    return raw.copyWith(imageUrl: imageUrl);
  }
  final int id;
  @JsonKey(name: 'image_url')
  final String imageUrl;
  final String? timestamp;
  final double latitude;
  final double longitude;
  @JsonKey(name: 'zip_code')
  final String? zipCode;
  final String? address;
  final String? note;
  @JsonKey(name: 'profile_id')
  final int? profileId;
  @JsonKey(name: 'profile_name')
  final String? profileName;
  @JsonKey(name: 'service_type')
  final String? serviceType;
  /// Per-photo priority category: standard | special | next_day | asap
  final String? category;
  final List<ProfileModel>? profiles;
  @JsonKey(name: 'is_favorited', defaultValue: false)
  final bool isFavorited;
  // ── Enhancement fields ──
  @JsonKey(name: 'pay_rate')
  final int? payRate;                 // F7
  final String? status;               // F10: open | completed | archived
  @JsonKey(name: 'taken_at')
  final String? takenAt;              // F6: device capture time
  @JsonKey(name: 'location_group_id')
  final int? locationGroupId;         // F1: master pin group
  @JsonKey(name: 'user_id')
  final int? userId;                  // F8/F9
  @JsonKey(name: 'completed_at')
  final String? completedAt;          // F8/F9

  Map<String, dynamic> toJson() => _$PhotoModelToJson(this);

  PhotoModel copyWith({
    int? id,
    String? imageUrl,
    String? timestamp,
    double? latitude,
    double? longitude,
    String? zipCode,
    String? address,
    String? note,
    int? profileId,
    String? profileName,
    String? serviceType,
    String? category,
    List<ProfileModel>? profiles,
    bool? isFavorited,
    int? payRate,
    String? status,
    String? takenAt,
    int? locationGroupId,
    int? userId,
    String? completedAt,
  }) =>
      PhotoModel(
        id: id ?? this.id,
        imageUrl: imageUrl ?? this.imageUrl,
        timestamp: timestamp ?? this.timestamp,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        zipCode: zipCode ?? this.zipCode,
        address: address ?? this.address,
        note: note ?? this.note,
        profileId: profileId ?? this.profileId,
        profileName: profileName ?? this.profileName,
        serviceType: serviceType ?? this.serviceType,
        category: category ?? this.category,
        profiles: profiles ?? this.profiles,
        isFavorited: isFavorited ?? this.isFavorited,
        payRate: payRate ?? this.payRate,
        status: status ?? this.status,
        takenAt: takenAt ?? this.takenAt,
        locationGroupId: locationGroupId ?? this.locationGroupId,
        userId: userId ?? this.userId,
        completedAt: completedAt ?? this.completedAt,
      );
}
