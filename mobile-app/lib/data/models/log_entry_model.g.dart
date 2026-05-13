// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_entry_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LogEntryModel _$LogEntryModelFromJson(Map<String, dynamic> json) =>
    LogEntryModel(
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
      profiles: (json['profiles'] as List<dynamic>?)
          ?.map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$LogEntryModelToJson(LogEntryModel instance) =>
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
