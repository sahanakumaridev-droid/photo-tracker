import 'package:json_annotation/json_annotation.dart';

import 'profile_model.dart';

part 'log_entry_model.g.dart';

@JsonSerializable()
class LogEntryModel {

  LogEntryModel({
    required this.id,
    required this.imageUrl,
    required this.latitude, required this.longitude, this.timestamp,
    this.zipCode,
    this.note,
    this.profileId,
    this.profileName,
    this.serviceType,
    this.profiles,
  });

  factory LogEntryModel.fromJson(Map<String, dynamic> json) =>
      _$LogEntryModelFromJson(json);
  final int id;
  @JsonKey(name: 'image_url')
  final String imageUrl;
  final String? timestamp;
  final double latitude;
  final double longitude;
  @JsonKey(name: 'zip_code')
  final String? zipCode;
  final String? note;
  @JsonKey(name: 'profile_id')
  final int? profileId;
  @JsonKey(name: 'profile_name')
  final String? profileName;
  @JsonKey(name: 'service_type')
  final String? serviceType;
  final List<ProfileModel>? profiles;

  Map<String, dynamic> toJson() => _$LogEntryModelToJson(this);
}
