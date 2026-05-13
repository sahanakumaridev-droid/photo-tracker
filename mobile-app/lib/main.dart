import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'core/storage/local_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize local storage
  await LocalStorage.init();

  // ── Request all required permissions on first launch ──────────────────
  // Camera is the primary feature — request it first so the dialog appears
  // before the user tries to upload anything.
  await [
    Permission.camera,
    Permission.locationWhenInUse,
    Permission.photos,
  ].request();

  runApp(
    const ProviderScope(
      child: PhotoTrackerApp(),
    ),
  );
}
