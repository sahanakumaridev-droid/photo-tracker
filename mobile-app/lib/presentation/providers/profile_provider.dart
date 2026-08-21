import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/attempt.dart';
import '../../data/models/photo_model.dart';
import '../../data/models/profile_model.dart';
import 'photo_provider.dart';
import 'repository_providers.dart';

/// Get all profiles
final profilesProvider = FutureProvider<List<ProfileModel>>((ref) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getProfiles();
});

/// Get profile details with photos
final profileDetailProvider =
    FutureProvider.family<List<PhotoModel>, int>((ref, profileId) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getProfilePhotos(profileId);
});

/// Attempts for a profile — newest first (Profile → Attempt → Photos).
final profileAttemptsProvider =
    FutureProvider.family<List<Attempt>, int>((ref, profileId) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getProfileAttempts(profileId);
});

/// Drop cached profile/attempt lists so Service Attempts updates after
/// an upload completes.
void refreshProfileWork(dynamic ref, {int? profileId}) {
  ref.invalidate(photosProvider);
  ref.invalidate(profilesProvider);
  if (profileId != null) {
    ref.invalidate(profileAttemptsProvider(profileId));
  } else {
    ref.invalidate(profileAttemptsProvider);
  }
}

/// Args for [createProfileProvider]. Profile Location + status are
/// optional — a profile can be created with only a name. [company] is the
/// process-serving company slug.
typedef CreateProfileArgs = ({
  String name,
  String serviceType,
  String? company,
  int? payRate,
  String? deliveryStyle,
  String? status,
  String? address,
  String? city,
  String? state,
  String? postalCode,
  double? latitude,
  double? longitude,
});

/// Create profile
final createProfileProvider =
    FutureProvider.family<ProfileModel, CreateProfileArgs>(
  (ref, args) async {
    final repository = ref.watch(profileRepositoryProvider);
    return repository.createProfile(
      name: args.name,
      serviceType: args.serviceType,
      company: args.company,
      payRate: args.payRate,
      deliveryStyle: args.deliveryStyle,
      status: args.status,
      address: args.address,
      city: args.city,
      state: args.state,
      postalCode: args.postalCode,
      latitude: args.latitude,
      longitude: args.longitude,
    );
  },
);

/// Args for [updateProfileProvider].
typedef UpdateProfileArgs = ({
  int profileId,
  String name,
  String serviceType,
  String? company,
  String? note,
  int? payRate,
  String? deliveryStyle,
  String? status,
  String? address,
  String? city,
  String? state,
  String? postalCode,
  double? latitude,
  double? longitude,
});

/// Update profile
final updateProfileProvider =
    FutureProvider.family<void, UpdateProfileArgs>(
  (ref, args) async {
    final repository = ref.watch(profileRepositoryProvider);
    await repository.updateProfile(
      profileId: args.profileId,
      name: args.name,
      serviceType: args.serviceType,
      company: args.company,
      note: args.note,
      payRate: args.payRate,
      deliveryStyle: args.deliveryStyle,
      status: args.status,
      address: args.address,
      city: args.city,
      state: args.state,
      postalCode: args.postalCode,
      latitude: args.latitude,
      longitude: args.longitude,
    );
  },
);

/// Delete profile
final deleteProfileProvider = FutureProvider.family<void, int>(
  (ref, profileId) async {
    final repository = ref.watch(profileRepositoryProvider);
    await repository.deleteProfile(profileId);
  },
);
