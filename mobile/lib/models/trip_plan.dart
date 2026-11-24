import '../shared/polyline.dart';

class TripPlace {
  const TripPlace({required this.lat, required this.lng, required this.label});

  final double lat;
  final double lng;
  final String label;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'label': label};

  static TripPlace fromJson(Map<String, dynamic> j) => TripPlace(
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        label: (j['label'] as String?) ?? '',
      );
}

/// The leader's planned trip (trip_plan message / GET /rides plan).
class TripPlan {
  const TripPlan({
    required this.origin,
    required this.destination,
    required this.stops,
    required this.route,
    required this.distanceM,
    required this.durationS,
    required this.approximate,
    required this.provider,
  });

  final TripPlace origin;
  final TripPlace destination;
  final List<TripPlace> stops;

  /// Decoded route line.
  final List<(double, double)> route;
  final int distanceM;
  final int durationS;

  /// Straight-line estimate (no Google key on the server): no road route,
  /// no off-route alerts.
  final bool approximate;
  final String provider;

  static TripPlan? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    return TripPlan(
      origin: TripPlace.fromJson((m['origin'] as Map).cast()),
      destination: TripPlace.fromJson((m['destination'] as Map).cast()),
      stops: [for (final s in (m['stops'] as List? ?? const [])) TripPlace.fromJson((s as Map).cast())],
      route: decodePolyline(m['polyline'] as String? ?? ''),
      distanceM: (m['distance_m'] as num?)?.toInt() ?? 0,
      durationS: (m['duration_s'] as num?)?.toInt() ?? 0,
      approximate: m['approximate'] == true,
      provider: (m['provider'] as String?) ?? '',
    );
  }
}
