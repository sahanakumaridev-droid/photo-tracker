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
    this.address,
    this.note,
    this.profileId,
    this.profileName,
    this.serviceType,
    this.category,
    this.fileNumber,
    this.profiles,
    this.attemptStatus = 'pending',
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
  /// Dispatcher-assigned file number for this job.
  @JsonKey(name: 'file_number')
  final String? fileNumber;
  final List<ProfileModel>? profiles;

  /// Attempt outcome — pending | successful | unsuccessful.
  @JsonKey(name: 'attempt_status', defaultValue: 'pending')
  final String attemptStatus;

  Map<String, dynamic> toJson() => _$LogEntryModelToJson(this);
}
