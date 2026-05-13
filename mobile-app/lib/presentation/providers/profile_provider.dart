import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/photo_model.dart';
import '../../data/models/profile_model.dart';
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

/// Create profile
final createProfileProvider = FutureProvider.family<ProfileModel, (String, String)>(
  (ref, args) async {
    final repository = ref.watch(profileRepositoryProvider);
    return repository.createProfile(
      name: args.$1,
      serviceType: args.$2,
    );
  },
);

/// Update profile
final updateProfileProvider =
    FutureProvider.family<void, (int, String, String, String?)>(
  (ref, args) async {
    final repository = ref.watch(profileRepositoryProvider);
    await repository.updateProfile(
      profileId: args.$1,
      name: args.$2,
      serviceType: args.$3,
      note: args.$4,
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
