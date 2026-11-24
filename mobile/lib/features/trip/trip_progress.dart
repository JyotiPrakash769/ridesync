import 'dart:math';

import '../../models/trip_plan.dart';
import '../../shared/geo.dart';

/// Same threshold as the server's off-route tracker.
const double offRouteThresholdM = 250;

/// Where a rider is along the planned route.
class TripProgress {
  const TripProgress({
    required this.remainingM,
    required this.remainingS,
    required this.distanceFromRouteM,
    this.nextStop,
    this.nextStopM,
  });

  final double remainingM;
  final int remainingS;

  /// Distance from the rider to the route line.
  final double distanceFromRouteM;
  final TripPlace? nextStop;
  final double? nextStopM;

  bool get isOffRoute => distanceFromRouteM > offRouteThresholdM;
  bool get arrived => remainingM < 150;
}

/// Projects (lat,lng) onto the route; returns (distance along route, distance off route).
(double along, double off) projectOnRoute(List<(double, double)> route, double lat, double lng) {
  if (route.isEmpty) return (0, double.infinity);
  if (route.length == 1) return (0, haversineM(lat, lng, route[0].$1, route[0].$2));
  final kx = cos(lat * pi / 180) * pi / 180 * earthRadiusM;
  const ky = pi / 180 * earthRadiusM;
  var best = double.infinity, bestAlong = 0.0, walked = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final (aLat, aLng) = route[i];
    final (bLat, bLng) = route[i + 1];
    final ax = (aLng - lng) * kx, ay = (aLat - lat) * ky;
    final bx = (bLng - lng) * kx, by = (bLat - lat) * ky;
    final dx = bx - ax, dy = by - ay;
    final seg2 = dx * dx + dy * dy;
    final t = seg2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / seg2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final d = sqrt(cx * cx + cy * cy);
    final segLen = sqrt(seg2);
    if (d < best) {
      best = d;
      bestAlong = walked + t * segLen;
    }
    walked += segLen;
  }
  return (bestAlong, best);
}

double routeLengthM(List<(double, double)> route) {
  var total = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    total += haversineM(route[i].$1, route[i].$2, route[i + 1].$1, route[i + 1].$2);
  }
  return total;
}

/// Remaining distance/time to the destination and the next stop ahead.
/// Time is the plan's duration scaled by the fraction left (keeps Google's
/// road-speed estimate); approximate plans assume 40 km/h.
TripProgress tripProgress(TripPlan plan, double lat, double lng) {
  final total = routeLengthM(plan.route);
  final (along, off) = projectOnRoute(plan.route, lat, lng);
  final remaining = max(0.0, total - along);
  final frac = total <= 0 ? 0.0 : remaining / total;
  final secs = plan.approximate || plan.durationS <= 0
      ? (remaining / (40 / 3.6)).round()
      : (plan.durationS * frac).round();

  TripPlace? next;
  double? nextM;
  for (final s in plan.stops) {
    final (sAlong, _) = projectOnRoute(plan.route, s.lat, s.lng);
    if (sAlong > along + 50) {
      next = s;
      nextM = sAlong - along;
      break;
    }
  }
  return TripProgress(
    remainingM: remaining,
    remainingS: secs,
    distanceFromRouteM: off,
    nextStop: next,
    nextStopM: nextM,
  );
}

/// "1h 12m" / "25 min".
String formatDuration(int seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m min';
  return '${m ~/ 60}h ${m % 60}m';
}
