// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileModel _$ProfileModelFromJson(Map<String, dynamic> json) => ProfileModel(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      serviceType: json['service_type'] as String,
      note: json['note'] as String?,
      payRate: (json['pay_rate'] as num?)?.toInt(),
      company: json['company'] as String?,
      companyName: json['company_name'] as String?,
      status: json['status'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      postalCode: json['postal_code'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      attemptsCount: (json['attempts_count'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ProfileModelToJson(ProfileModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'service_type': instance.serviceType,
      'note': instance.note,
      'pay_rate': instance.payRate,
      'company': instance.company,
      'company_name': instance.companyName,
      'status': instance.status,
      'address': instance.address,
      'city': instance.city,
      'state': instance.state,
      'postal_code': instance.postalCode,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'attempts_count': instance.attemptsCount,
    };
