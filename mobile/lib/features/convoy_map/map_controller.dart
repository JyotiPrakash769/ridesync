import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/rider.dart';

/// Camera helpers for the convoy map.
abstract final class ConvoyCamera {
  static const LatLng fallbackCenter = LatLng(20.2961, 85.8245);

  /// Fits every rider with a known position; a single rider gets a street zoom.
  static CameraUpdate? fitGroup(Iterable<Rider> riders) {
    final pts = [
      for (final r in riders)
        if (r.hasPosition) LatLng(r.lat!, r.lng!),
    ];
    if (pts.isEmpty) return null;
    if (pts.length == 1) return CameraUpdate.newLatLngZoom(pts.single, 15);
    var south = pts.first.latitude, north = south;
    var west = pts.first.longitude, east = west;
    for (final p in pts) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    // Avoid a zero-size box when everyone is at the same spot.
    if (north - south < 0.0005) {
      north += 0.00025;
      south -= 0.00025;
    }
    if (east - west < 0.0005) {
      east += 0.00025;
      west -= 0.00025;
    }
    return CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)),
      96,
    );
  }

  static CameraUpdate? focus(Rider r) =>
      r.hasPosition ? CameraUpdate.newLatLngZoom(LatLng(r.lat!, r.lng!), 16) : null;
}
