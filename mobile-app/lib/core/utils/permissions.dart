import 'package:permission_handler/permission_handler.dart';

import '../storage/local_storage.dart';

/// Requests every permission the app needs — camera, photo library and
/// location — in a single batch on the user's first successful login.
///
/// The OS only surfaces each system dialog once, so calling this again is
/// harmless; the [onlyFirstTime] guard simply skips the work entirely after
/// it has run once on this install.
Future<void> requestAppPermissions({bool onlyFirstTime = true}) async {
  if (onlyFirstTime && LocalStorage.getPermissionsRequested()) return;

  // Requested together so the user is walked through every prompt up front,
  // before they reach a screen that needs one.
  await [
    Permission.camera,
    Permission.photos,
    Permission.locationWhenInUse,
  ].request();

  await LocalStorage.setPermissionsRequested();
}
