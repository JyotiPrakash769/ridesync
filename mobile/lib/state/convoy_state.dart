import '../core/network/ws_client.dart';
import '../models/rider.dart';
import '../models/regroup_point.dart';
import '../models/trip_plan.dart';
import '../shared/geo.dart';

export '../models/regroup_point.dart';

/// A member the server flagged as over the threshold (distance_alert).
class DistanceAlert {
  const DistanceAlert({required this.riderId, required this.name, required this.distanceM});

  final String riderId;
  final String name;
  final int distanceM;

  DistanceAlert withDistance(int d) => DistanceAlert(riderId: riderId, name: name, distanceM: d);
}

/// One point of a rider's recent path (drawn as a faint trail).
class TrailPoint {
  const TrailPoint(this.lat, this.lng, this.at);

  final double lat;
  final double lng;
  final DateTime at;
}

/// Trails keep the last few minutes; tiny GPS jitter isn't recorded.
const Duration trailWindow = Duration(minutes: 5);
const double trailMinStepM = 3;
const int trailMaxPoints = 150;

/// Heading needs at least this much movement to be meaningful.
const double headingMinStepM = 5;

/// Same re-arm ratio as the backend: an alert clears once the rider is back
/// under 90% of the threshold.
const double alertClearRatio = 0.9;

/// Everything the convoy map renders. Updated only through [applyMessage].
class ConvoyState {
  const ConvoyState({
    this.riders = const {},
    this.thresholdM = 500,
    this.conn = WsConnState.connecting,
    this.ended = false,
    this.fatalCloseCode,
    this.alerts = const {},
    this.trails = const {},
    this.regroup,
    this.plan,
    this.offRoute = const {},
  });

  final Map<String, Rider> riders;
  final int thresholdM;
  final WsConnState conn;
  final bool ended;
  final int? fatalCloseCode;
  final Map<String, DistanceAlert> alerts;
  final Map<String, List<TrailPoint>> trails;
  final RegroupPoint? regroup;
  final TripPlan? plan;

  /// Riders the server reports as off the planned route: id -> metres off.
  final Map<String, int> offRoute;

  /// Direction of travel in degrees (0 = north), from the rider's last two
  /// trail points; null while they haven't moved enough to tell.
  double? headingOf(String riderId) {
    final t = trails[riderId];
    if (t == null || t.length < 2) return null;
    final a = t[t.length - 2], b = t.last;
    if (haversineM(a.lat, a.lng, b.lat, b.lng) < headingMinStepM) return null;
    return bearingDeg(a.lat, a.lng, b.lat, b.lng);
  }

  /// The alert with the largest current distance (tap target for the card).
  DistanceAlert? get worstAlert => alerts.values.isEmpty
      ? null
      : alerts.values.reduce((a, b) => b.distanceM > a.distanceM ? b : a);

  Rider? get leader => riders.values.where((r) => r.isLeader).firstOrNull;

  ConvoyState copyWith({
    Map<String, Rider>? riders,
    int? thresholdM,
    WsConnState? conn,
    bool? ended,
    int? fatalCloseCode,
    Map<String, DistanceAlert>? alerts,
    Map<String, List<TrailPoint>>? trails,
    RegroupPoint? Function()? regroup,
    TripPlan? Function()? plan,
    Map<String, int>? offRoute,
  }) =>
      ConvoyState(
        riders: riders ?? this.riders,
        thresholdM: thresholdM ?? this.thresholdM,
        conn: conn ?? this.conn,
        ended: ended ?? this.ended,
        fatalCloseCode: fatalCloseCode ?? this.fatalCloseCode,
        alerts: alerts ?? this.alerts,
        trails: trails ?? this.trails,
        regroup: regroup != null ? regroup() : this.regroup,
        plan: plan != null ? plan() : this.plan,
        offRoute: offRoute ?? this.offRoute,
      );
}

/// Same rule as the server's takeover check: the leader has been offline
/// (60 s) for at least another 3 minutes.
const Duration leaderTakeoverAfter = Duration(minutes: 4);

bool leaderGone(Rider? leader, DateTime now) {
  final seen = leader?.lastSeenAt;
  return leader != null && seen != null && now.difference(seen) > leaderTakeoverAfter;
}

/// Pure reducer for server -> client WS messages (foundation doc §5).
ConvoyState applyMessage(ConvoyState s, Map<String, dynamic> msg) {
  switch (msg['type']) {
    case 'rider_positions':
      final list = (msg['riders'] as List).cast<Map<String, dynamic>>();
      final riders = {for (final j in list) j['rider_id'] as String: Rider.fromJson(j)};
      return s.copyWith(
        riders: riders,
        alerts: _refreshAlerts(s.alerts, riders, s.thresholdM),
        trails: _extendTrails(s.trails, riders),
      );
    case 'distance_alert':
      final id = msg['rider_id'] as String;
      return s.copyWith(alerts: {
        ...s.alerts,
        id: DistanceAlert(
          riderId: id,
          name: msg['name'] as String,
          distanceM: (msg['distance_m'] as num).round(),
        ),
      });
    case 'rider_joined':
      final id = msg['rider_id'] as String;
      if (s.riders.containsKey(id)) return s;
      return s.copyWith(riders: {
        ...s.riders,
        id: Rider(
          id: id,
          name: msg['name'] as String,
          role: parseRole(msg['role'] as String?),
          status: RiderStatus.offline,
        ),
      });
    case 'rider_left':
      return s.copyWith(
        riders: Map.of(s.riders)..remove(msg['rider_id']),
        alerts: Map.of(s.alerts)..remove(msg['rider_id']),
        trails: Map.of(s.trails)..remove(msg['rider_id']),
        offRoute: Map.of(s.offRoute)..remove(msg['rider_id']),
      );
    case 'ride_ended':
      return s.copyWith(ended: true);
    case 'trip_plan':
      return s.copyWith(plan: () => TripPlan.fromJson(msg['plan']), offRoute: const {});
    case 'route_status':
      final id = msg['rider_id'] as String;
      final next = Map.of(s.offRoute);
      if (msg['off_route'] == true) {
        next[id] = (msg['distance_m'] as num).round();
      } else {
        next.remove(id);
      }
      return s.copyWith(offRoute: next);
    case 'regroup_point':
      return s.copyWith(regroup: () => RegroupPoint.fromJson(msg['point']));
    case 'leader_changed':
      final newId = msg['leader_rider_id'] as String;
      return s.copyWith(
        riders: {
          for (final e in s.riders.entries)
            e.key: e.value.withRole(e.key == newId ? RiderRole.leader : RiderRole.member),
        },
        alerts: const {}, // distances are now measured to the new leader
      );
    case 'threshold_updated':
      // The server re-evaluates everyone against the new value.
      return s.copyWith(thresholdM: msg['threshold_m'] as int, alerts: const {});
    default:
      return s;
  }
}

/// Keeps alert distances live and drops riders who caught up (or left).
Map<String, DistanceAlert> _refreshAlerts(
  Map<String, DistanceAlert> alerts,
  Map<String, Rider> riders,
  int thresholdM,
) {
  if (alerts.isEmpty) return alerts;
  final leader = riders.values.where((r) => r.isLeader).firstOrNull;
  final out = <String, DistanceAlert>{};
  for (final a in alerts.values) {
    final r = riders[a.riderId];
    if (r == null) continue;
    if (leader == null || !leader.hasPosition || !r.hasPosition) {
      out[a.riderId] = a;
      continue;
    }
    final d = haversineM(leader.lat!, leader.lng!, r.lat!, r.lng!);
    if (d > thresholdM * alertClearRatio) out[a.riderId] = a.withDistance(d.round());
  }
  return out;
}

Map<String, List<TrailPoint>> _extendTrails(
  Map<String, List<TrailPoint>> trails,
  Map<String, Rider> riders,
) {
  final out = <String, List<TrailPoint>>{};
  for (final r in riders.values) {
    final prev = trails[r.id] ?? const <TrailPoint>[];
    if (!r.hasPosition) {
      if (prev.isNotEmpty) out[r.id] = prev;
      continue;
    }
    final at = r.lastSeenAt ?? (prev.isEmpty ? DateTime.now().toUtc() : prev.last.at);
    var list = prev;
    final last = prev.isEmpty ? null : prev.last;
    if (last == null || haversineM(last.lat, last.lng, r.lat!, r.lng!) >= trailMinStepM) {
      list = [...prev, TrailPoint(r.lat!, r.lng!, at)];
    }
    final cutoff = list.last.at.subtract(trailWindow);
    list = list.where((p) => !p.at.isBefore(cutoff)).toList();
    if (list.length > trailMaxPoints) list = list.sublist(list.length - trailMaxPoints);
    out[r.id] = list;
  }
  return out;
}
