import 'package:json_annotation/json_annotation.dart';

part 'profile_model.g.dart';

@JsonSerializable()
class ProfileModel {

  ProfileModel({
    required this.id,
    required this.name,
    required this.serviceType,
    this.note,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) =>
      _$ProfileModelFromJson(json);
  final int id;
  final String name;
  @JsonKey(name: 'service_type')
  final String serviceType;
  final String? note;

  Map<String, dynamic> toJson() => _$ProfileModelToJson(this);

  ProfileModel copyWith({
    int? id,
    String? name,
    String? serviceType,
    String? note,
  }) =>
      ProfileModel(
        id: id ?? this.id,
        name: name ?? this.name,
        serviceType: serviceType ?? this.serviceType,
        note: note ?? this.note,
      );
}
