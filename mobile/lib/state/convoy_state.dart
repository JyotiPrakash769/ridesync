import '../core/network/ws_client.dart';
import '../models/rider.dart';
import '../shared/geo.dart';

/// A member the server flagged as over the threshold (distance_alert).
class DistanceAlert {
  const DistanceAlert({required this.riderId, required this.name, required this.distanceM});

  final String riderId;
  final String name;
  final int distanceM;

  DistanceAlert withDistance(int d) => DistanceAlert(riderId: riderId, name: name, distanceM: d);
}

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
  });

  final Map<String, Rider> riders;
  final int thresholdM;
  final WsConnState conn;
  final bool ended;
  final int? fatalCloseCode;
  final Map<String, DistanceAlert> alerts;

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
  }) =>
      ConvoyState(
        riders: riders ?? this.riders,
        thresholdM: thresholdM ?? this.thresholdM,
        conn: conn ?? this.conn,
        ended: ended ?? this.ended,
        fatalCloseCode: fatalCloseCode ?? this.fatalCloseCode,
        alerts: alerts ?? this.alerts,
      );
}

/// Pure reducer for server -> client WS messages (foundation doc §5).
ConvoyState applyMessage(ConvoyState s, Map<String, dynamic> msg) {
  switch (msg['type']) {
    case 'rider_positions':
      final list = (msg['riders'] as List).cast<Map<String, dynamic>>();
      final riders = {for (final j in list) j['rider_id'] as String: Rider.fromJson(j)};
      return s.copyWith(riders: riders, alerts: _refreshAlerts(s.alerts, riders, s.thresholdM));
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
      );
    case 'ride_ended':
      return s.copyWith(ended: true);
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
