// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PhotoModel _$PhotoModelFromJson(Map<String, dynamic> json) => PhotoModel(
      id: (json['id'] as num).toInt(),
      imageUrl: json['image_url'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: json['timestamp'] as String?,
      zipCode: json['zip_code'] as String?,
      address: json['address'] as String?,
      note: json['note'] as String?,
      profileId: (json['profile_id'] as num?)?.toInt(),
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
      'address': instance.address,
      'note': instance.note,
      'profile_id': instance.profileId,
      'profile_name': instance.profileName,
      'service_type': instance.serviceType,
      'profiles': instance.profiles,
    };
