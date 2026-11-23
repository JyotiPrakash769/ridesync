import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum LocationAccess { denied, deniedForever, serviceOff, foregroundOnly, always }

/// Thin wrapper over geolocator. Background permission and the foreground
/// service live in background_task.dart (Phase 4).
class LocationService {
  Future<LocationAccess> ensureForegroundPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return switch (p) {
      LocationPermission.always => LocationAccess.always,
      LocationPermission.whileInUse => LocationAccess.foregroundOnly,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  /// High-accuracy fixes; the convoy controller throttles sends to ~4s.
  Stream<Position> positions() => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 2),
        ),
      );
}
