import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/utils/location_service.dart';

final currentLocationProvider = FutureProvider<Position?>(
  (ref) => LocationService.getCurrentLocation(),
);

final locationStreamProvider = StreamProvider<Position>(
  (ref) => LocationService.watchLocation(),
);

final addressProvider = FutureProvider.family<String?, (double, double)>(
  (ref, coords) => LocationService.getAddressFromCoordinates(
    coords.$1,
    coords.$2,
  ),
);
