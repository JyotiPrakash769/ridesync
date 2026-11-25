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
    this.legs = const [],
    this.departureAt,
    this.fuelRangeKm,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.routeLabel = '',
  });

  /// Per-leg distance/time (origin -> stop 1 -> ... -> destination).
  final List<({int distanceM, int durationS})> legs;
  final DateTime? departureAt;
  final int? fuelRangeKm;
  final bool avoidTolls;
  final bool avoidHighways;
  final String routeLabel;

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
      legs: [
        for (final l in (m['legs'] as List? ?? const []).cast<Map>())
          (distanceM: (l['distance_m'] as num).toInt(), durationS: (l['duration_s'] as num).toInt()),
      ],
      departureAt: m['departure_at'] is String
          ? DateTime.tryParse(m['departure_at'] as String)?.toUtc()
          : null,
      fuelRangeKm: (m['fuel_range_km'] as num?)?.toInt(),
      avoidTolls: m['avoid_tolls'] == true,
      avoidHighways: m['avoid_highways'] == true,
      routeLabel: (m['route_label'] as String?) ?? '',
    );
  }
}

/// One route option from POST /plan/preview.
class RouteOption {
  const RouteOption({
    required this.index,
    required this.label,
    required this.distanceM,
    required this.durationS,
    required this.route,
    required this.approximate,
  });

  final int index;
  final String label;
  final int distanceM;
  final int durationS;
  final List<(double, double)> route;
  final bool approximate;

  factory RouteOption.fromJson(Map<String, dynamic> j) => RouteOption(
        index: (j['index'] as num).toInt(),
        label: j['label'] as String,
        distanceM: (j['distance_m'] as num).toInt(),
        durationS: (j['duration_s'] as num).toInt(),
        route: decodePolyline(j['polyline'] as String),
        approximate: j['approximate'] == true,
      );
}

/// Forecast at a stop/destination for the estimated arrival hour.
class WeatherPoint {
  const WeatherPoint({
    required this.kind,
    required this.label,
    required this.eta,
    this.summary,
    this.tempC,
    this.rainPct,
    this.warning,
  });

  final String kind;
  final String label;
  final DateTime eta;
  final String? summary;
  final double? tempC;
  final int? rainPct;
  final String? warning;

  factory WeatherPoint.fromJson(Map<String, dynamic> j) {
    final f = (j['forecast'] as Map?)?.cast<String, dynamic>();
    return WeatherPoint(
      kind: j['kind'] as String,
      label: (j['label'] as String?) ?? '',
      eta: DateTime.parse(j['eta'] as String).toUtc(),
      summary: f?['summary'] as String?,
      tempC: (f?['temp_c'] as num?)?.toDouble(),
      rainPct: (f?['rain_pct'] as num?)?.toInt(),
      warning: j['warning'] as String?,
    );
  }
}
