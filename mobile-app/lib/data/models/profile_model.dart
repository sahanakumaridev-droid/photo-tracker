import 'package:json_annotation/json_annotation.dart';

import 'company.dart';

part 'profile_model.g.dart';

@JsonSerializable()
class ProfileModel {
  ProfileModel({
    required this.id,
    required this.name,
    required this.serviceType,
    this.note,
    this.payRate,
    this.company,
    this.companyName,
    this.status,
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.attemptsCount = 0,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) =>
      _$ProfileModelFromJson(json);

  final int id;
  final String name;
  @JsonKey(name: 'service_type')
  final String serviceType;
  final String? note;

  /// Standing pay rate (whole dollars) for this profile — summed across all
  /// profiles to produce "Total Available Earnings" on the Earnings screen.
  @JsonKey(name: 'pay_rate')
  final int? payRate;

  /// Process-serving company slug (`first_legal` | `rockstar` | `knox`).
  final String? company;

  /// Denormalized company display name from the API (optional).
  @JsonKey(name: 'company_name')
  final String? companyName;

  /// Profile-level lifecycle flag, e.g. "awaiting_attempt". Independent of
  /// any Attempt/Photo status — see Photo.status for that.
  final String? status;

  /// Profile Location — where the work is supposed to happen. Set directly
  /// on the profile, independent of any Attempt's captured GPS
  /// (PhotoModel.latitude/longitude), and settable before any photo exists.
  final String? address;
  final String? city;
  final String? state;
  @JsonKey(name: 'postal_code')
  final String? postalCode;
  final double? latitude;
  final double? longitude;

  /// Number of Attempts (Photos) logged against this profile.
  /// Full attempt rows are loaded as profile members via
  /// `attemptsFromPhotos` on the profile's photo list (newest first).
  @JsonKey(name: 'attempts_count', defaultValue: 0)
  final int attemptsCount;

  /// Resolved [Company] config for this profile (falls back to default).
  Company get companyConfig => companyOrDefault(company);

  /// True when this profile is still waiting on its first attempt — a
  /// derived display state, not a raw status check, so it naturally clears
  /// once an attempt exists without any server-side status mutation.
  bool get isAwaitingAttempt =>
      status == 'awaiting_attempt' && attemptsCount == 0;

  /// True when a Profile Location has been set.
  bool get hasLocation => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => _$ProfileModelToJson(this);

  ProfileModel copyWith({
    int? id,
    String? name,
    String? serviceType,
    String? note,
    int? payRate,
    String? company,
    String? companyName,
    String? status,
    String? address,
    String? city,
    String? state,
    String? postalCode,
    double? latitude,
    double? longitude,
    int? attemptsCount,
  }) =>
      ProfileModel(
        id: id ?? this.id,
        name: name ?? this.name,
        serviceType: serviceType ?? this.serviceType,
        note: note ?? this.note,
        payRate: payRate ?? this.payRate,
        company: company ?? this.company,
        companyName: companyName ?? this.companyName,
        status: status ?? this.status,
        address: address ?? this.address,
        city: city ?? this.city,
        state: state ?? this.state,
        postalCode: postalCode ?? this.postalCode,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        attemptsCount: attemptsCount ?? this.attemptsCount,
      );
}
