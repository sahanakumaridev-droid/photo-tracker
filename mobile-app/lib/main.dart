import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/network/network_quality.dart';
import 'core/storage/api_cache.dart';
import 'core/storage/local_storage.dart';
import 'core/storage/upload_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize local storage
  await LocalStorage.init();

  // Cache for list-endpoint responses (photos/profiles) — lets the app show
  // last-known data on a poor or dropped connection instead of a blank screen.
  await ApiCache.init();

  // Offline upload queue — opens its Hive box and starts the auto-retry loop.
  // The actual network uploader is attached once Riverpod providers are ready
  // (see _QueueAttacher in app.dart).
  await UploadQueueService.instance.init();

  // Latency / offline detector for continual attempt snapshots under poor signal.
  await NetworkQualityService.instance.init();

  // Permissions (camera, photos, location) are requested on the user's first
  // successful login — see requestAppPermissions() in core/utils/permissions.dart.

  runApp(
    const ProviderScope(
      child: PhotoTrackerApp(),
    ),
  );
}
