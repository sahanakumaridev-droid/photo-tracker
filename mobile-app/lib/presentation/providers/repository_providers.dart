import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../data/repositories/log_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/profile_repository.dart';

/// Profile Repository Provider
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ProfileRepository(dio);
});

/// Photo Repository Provider
final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return PhotoRepository(dio);
});

/// Log Repository Provider
final logRepositoryProvider = Provider<LogRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return LogRepository(dio);
});
