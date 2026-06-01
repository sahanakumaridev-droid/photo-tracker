import 'package:json_annotation/json_annotation.dart';

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
  });

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    final raw = _$PhotoModelFromJson(json);
    // Fix relative image_url to full URL
    final imageUrl = raw.imageUrl.startsWith('http')
        ? raw.imageUrl
        : 'http://24.199.85.230${raw.imageUrl}';
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
      );
}
