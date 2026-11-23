import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationAccess { denied, deniedForever, serviceOff, foregroundOnly, always }

/// Thin wrapper over geolocator. The two-step permission UI lives in
/// features/convoy_map/tracking_permission_flow.dart and the foreground
/// service in background_task.dart.
class LocationService {
  /// High-accuracy fixes; the convoy controller throttles sends to ~4s.
  Stream<Position> positions() => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 2),
        ),
      );
}
