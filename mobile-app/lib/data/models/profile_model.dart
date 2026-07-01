import 'package:json_annotation/json_annotation.dart';

part 'profile_model.g.dart';

@JsonSerializable()
class ProfileModel {
  ProfileModel({
    required this.id,
    required this.name,
    required this.serviceType,
    this.note,
    this.primaryAddress,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) =>
      _$ProfileModelFromJson(json);

  final int id;
  final String name;
  @JsonKey(name: 'service_type')
  final String serviceType;
  final String? note;

  /// Primary address — returned by the API when present; null otherwise.
  /// Multiple addresses are derived client-side from associated photo data.
  @JsonKey(name: 'primary_address')
  final String? primaryAddress;

  Map<String, dynamic> toJson() => _$ProfileModelToJson(this);

  ProfileModel copyWith({
    int? id,
    String? name,
    String? serviceType,
    String? note,
    String? primaryAddress,
  }) =>
      ProfileModel(
        id: id ?? this.id,
        name: name ?? this.name,
        serviceType: serviceType ?? this.serviceType,
        note: note ?? this.note,
        primaryAddress: primaryAddress ?? this.primaryAddress,
      );
}
