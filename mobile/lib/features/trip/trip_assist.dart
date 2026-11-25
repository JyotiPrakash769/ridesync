

import '../../models/trip_plan.dart';
import 'trip_progress.dart';

/// A stretch longer than this without a stop gets a break suggestion.
const int breakEveryS = 90 * 60;

/// Legs riding longer than [maxS] without a stop.
List<int> longLegs(TripPlan plan, {int maxS = breakEveryS}) => [
      for (var i = 0; i < plan.legs.length; i++)
        if (plan.legs[i].durationS > maxS) i,
    ];

/// Legs longer than the fuel range.
List<int> fuelGaps(TripPlan plan, int? rangeKm) => rangeKm == null
    ? const []
    : [
        for (var i = 0; i < plan.legs.length; i++)
          if (plan.legs[i].distanceM > rangeKm * 1000) i,
      ];

/// Name of where a leg ends ("Fuel" / destination label).
String legEndLabel(TripPlan plan, int leg) => leg < plan.stops.length
    ? (plan.stops[leg].label.isEmpty ? 'stop ${leg + 1}' : plan.stops[leg].label)
    : (plan.destination.label.isEmpty ? 'the destination' : plan.destination.label);

/// Point on the route halfway along [leg] (for "Add a break here").
TripPlace legMidpoint(TripPlan plan, int leg) {
  final waypoints = [plan.origin, ...plan.stops, plan.destination];
  final total = routeLengthM(plan.route);
  double along(TripPlace p) => projectOnRoute(plan.route, p.lat, p.lng).$1;
  final a = leg == 0 ? 0.0 : along(waypoints[leg]);
  final b = leg + 1 >= waypoints.length - 1 ? total : along(waypoints[leg + 1]);
  final (lat, lng) = pointAlong(plan.route, (a + b) / 2);
  return TripPlace(lat: lat, lng: lng, label: 'Break');
}

/// The coordinate [dist] metres along the route.
(double, double) pointAlong(List<(double, double)> route, double dist) {
  if (route.isEmpty) return (0, 0);
  var walked = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final seg = routeLengthM([route[i], route[i + 1]]);
    if (walked + seg >= dist && seg > 0) {
      final t = (dist - walked) / seg;
      return (
        route[i].$1 + (route[i + 1].$1 - route[i].$1) * t,
        route[i].$2 + (route[i + 1].$2 - route[i].$2) * t,
      );
    }
    walked += seg;
  }
  return route.last;
}

/// Stops still ahead of (lat,lng) along the route (for "re-route from here").
List<TripPlace> stopsAhead(TripPlan plan, double lat, double lng) {
  final (here, _) = projectOnRoute(plan.route, lat, lng);
  return [
    for (final s in plan.stops)
      if (projectOnRoute(plan.route, s.lat, s.lng).$1 > here + 50) s,
  ];
}

/// Clock time of arrival: departure (if still ahead) or now + remaining.
DateTime arrivalTime(TripPlan plan, {required DateTime now, int? remainingS}) {
  final dep = plan.departureAt;
  final start = dep != null && dep.isAfter(now) ? dep : now;
  return start.add(Duration(seconds: remainingS ?? plan.durationS));
}

/// "6:05 AM".
String formatClock(DateTime t) {
  final local = t.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m ${local.hour < 12 ? 'AM' : 'PM'}';
}

