// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_entry_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LogEntryModel _$LogEntryModelFromJson(Map<String, dynamic> json) =>
    LogEntryModel(
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
      category: json['category'] as String?,
      fileNumber: json['file_number'] as String?,
      profiles: (json['profiles'] as List<dynamic>?)
          ?.map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      attemptStatus: json['attempt_status'] as String? ?? 'pending',
    );

Map<String, dynamic> _$LogEntryModelToJson(LogEntryModel instance) =>
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
      'category': instance.category,
      'file_number': instance.fileNumber,
      'profiles': instance.profiles,
      'attempt_status': instance.attemptStatus,
    };
