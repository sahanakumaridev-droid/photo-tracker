// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PhotoModel _$PhotoModelFromJson(Map<String, dynamic> json) => PhotoModel(
      id: json['id'] is int
          ? json['id'] as int
          : int.parse(json['id'].toString()),
      imageUrl: json['image_url'] as String,
      timestamp: json['timestamp'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      zipCode: json['zip_code'] as String?,
      note: json['note'] as String?,
      profileId: json['profile_id'] == null
          ? null
          : (json['profile_id'] is int
              ? json['profile_id'] as int
              : int.tryParse(json['profile_id'].toString())),
      profileName: json['profile_name'] as String?,
      serviceType: json['service_type'] as String?,
      profiles: (json['profiles'] as List<dynamic>?)
          ?.map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PhotoModelToJson(PhotoModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'image_url': instance.imageUrl,
      'timestamp': instance.timestamp,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'zip_code': instance.zipCode,
      'note': instance.note,
      'profile_id': instance.profileId,
      'profile_name': instance.profileName,
      'service_type': instance.serviceType,
      'profiles': instance.profiles,
    };
