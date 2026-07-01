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
      category: json['category'] as String?,
      completionType: json['completion_type'] as String?,
      servedTo: json['served_to'] as String?,
      profiles: (json['profiles'] as List<dynamic>?)
          ?.map((e) => ProfileModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      isFavorited: json['is_favorited'] as bool? ?? false,
      payRate: (json['pay_rate'] as num?)?.toInt(),
      status: json['status'] as String?,
      takenAt: json['taken_at'] as String?,
      locationGroupId: (json['location_group_id'] as num?)?.toInt(),
      userId: (json['user_id'] as num?)?.toInt(),
      completedAt: json['completed_at'] as String?,
      createdAt: json['created_at'] as String?,
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
      'category': instance.category,
      'completion_type': instance.completionType,
      'served_to': instance.servedTo,
      'profiles': instance.profiles,
      'is_favorited': instance.isFavorited,
      'pay_rate': instance.payRate,
      'status': instance.status,
      'taken_at': instance.takenAt,
      'location_group_id': instance.locationGroupId,
      'user_id': instance.userId,
      'completed_at': instance.completedAt,
      'created_at': instance.createdAt,
    };
