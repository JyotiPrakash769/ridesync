import '../../models/rider.dart';

/// Provider-neutral camera targets for the convoy map.
abstract final class MapGeometry {
  static const double fallbackLat = 20.2961;
  static const double fallbackLng = 85.8245;
  static const double focusZoom = 16;
  static const double singleRiderZoom = 15;

  /// (lat, lng) of every rider with a known position.
  static List<(double, double)> points(Iterable<Rider> riders) => [
        for (final r in riders)
          if (r.hasPosition) (r.lat!, r.lng!),
      ];

  /// South-west / north-east corners, padded so a tight group (or everyone at
  /// one spot) still gets a sensible zoom. Null when nobody has a position.
  static ((double, double), (double, double))? bounds(Iterable<Rider> riders) {
    final pts = points(riders);
    if (pts.isEmpty) return null;
    var (south, west) = pts.first;
    var (north, east) = pts.first;
    for (final (lat, lng) in pts) {
      if (lat < south) south = lat;
      if (lat > north) north = lat;
      if (lng < west) west = lng;
      if (lng > east) east = lng;
    }
    const minSpan = 0.0005; // ~55 m
    if (north - south < minSpan) {
      north += minSpan / 2;
      south -= minSpan / 2;
    }
    if (east - west < minSpan) {
      east += minSpan / 2;
      west -= minSpan / 2;
    }
    return ((south, west), (north, east));
  }
}
