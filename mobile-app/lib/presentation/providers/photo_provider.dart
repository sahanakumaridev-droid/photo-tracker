import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/photo_model.dart';
import 'repository_providers.dart';

/// Get all photos
final photosProvider = FutureProvider<List<PhotoModel>>((ref) async {
  final repository = ref.watch(photoRepositoryProvider);
  return repository.getPhotos();
});

/// Upload photo
final uploadPhotoProvider =
    FutureProvider.family<PhotoModel, Map<String, dynamic>>(
  (ref, params) async {
    final repository = ref.watch(photoRepositoryProvider);
    final photo = await repository.uploadPhoto(
      filePath: params['filePath'] as String,
      profileId: params['profileId'] as int,
      latitude: params['latitude'] as double,
      longitude: params['longitude'] as double,
      zipCode: params['zipCode'] as String?,
      address: params['address'] as String?,
      note: params['note'] as String?,
      category: params['category'] as String?,
      payRate: params['payRate'] as int?,
      takenAt: params['takenAt'] as String?,
      locationGroupId: params['locationGroupId'] as int?,
      userId: params['userId'] as int?,
    );
    ref.invalidate(photosProvider);
    return photo;
  },
);

/// Update photo location
final updatePhotoLocationProvider =
    FutureProvider.family<void, (int, double, double)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.updatePhotoLocation(
    photoId: args.$1,
    latitude: args.$2,
    longitude: args.$3,
  );
  ref.invalidate(photosProvider);
});

/// Update photo note
final updatePhotoNoteProvider =
    FutureProvider.family<void, (int, String)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.updatePhotoNote(
    photoId: args.$1,
    note: args.$2,
  );
  ref.invalidate(photosProvider);
});

/// Update photo zip code
final updatePhotoZipProvider =
    FutureProvider.family<void, (int, String)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.updatePhotoZip(
    photoId: args.$1,
    zipCode: args.$2,
  );
  ref.invalidate(photosProvider);
});

/// Update photo address + zip together
final updatePhotoAddressProvider =
    FutureProvider.family<void, (int, String, String)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.updatePhotoAddress(
    photoId: args.$1,
    address: args.$2,
    zipCode: args.$3,
  );
  ref.invalidate(photosProvider);
});

/// Update photo profiles
final updatePhotoProfilesProvider =
    FutureProvider.family<void, (int, List<int>)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.updatePhotoProfiles(
    photoId: args.$1,
    profileIds: args.$2,
  );
  ref.invalidate(photosProvider);
});

/// Update photo category (standard | special | next_day | asap)
final updatePhotoCategoryProvider =
    FutureProvider.family<void, (int, String)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.updatePhotoCategory(
    photoId: args.$1,
    category: args.$2,
  );
  ref.invalidate(photosProvider);
});

/// Replace photo image
final replacePhotoImageProvider =
    FutureProvider.family<PhotoModel, (int, String)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  final photo = await repository.replacePhotoImage(
    photoId: args.$1,
    filePath: args.$2,
  );
  ref.invalidate(photosProvider);
  return photo;
});

/// Delete photo
final deletePhotoProvider = FutureProvider.family<void, int>((ref, photoId) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.deletePhoto(photoId);
  ref.invalidate(photosProvider);
});

/// Toggle favorite — returns updated is_favorited bool
final toggleFavoriteProvider =
    FutureProvider.family<bool, int>((ref, photoId) async {
  final repository = ref.watch(photoRepositoryProvider);
  final result = await repository.toggleFavorite(photoId);
  ref.invalidate(photosProvider);
  return result;
});

/// F6 — edit capture timestamp (server enforces 10-min window)
final editTimestampProvider =
    FutureProvider.family<void, (int, String)>((ref, args) async {
  final repository = ref.watch(photoRepositoryProvider);
  await repository.editTimestamp(args.$1, args.$2);
  ref.invalidate(photosProvider);
});
