import '../core/network/ws_client.dart';
import '../models/rider.dart';

/// Everything the convoy map renders. Updated only through [applyMessage].
class ConvoyState {
  const ConvoyState({
    this.riders = const {},
    this.thresholdM = 500,
    this.conn = WsConnState.connecting,
    this.ended = false,
    this.fatalCloseCode,
  });

  final Map<String, Rider> riders;
  final int thresholdM;
  final WsConnState conn;
  final bool ended;
  final int? fatalCloseCode;

  Rider? get leader => riders.values.where((r) => r.isLeader).firstOrNull;

  ConvoyState copyWith({
    Map<String, Rider>? riders,
    int? thresholdM,
    WsConnState? conn,
    bool? ended,
    int? fatalCloseCode,
  }) =>
      ConvoyState(
        riders: riders ?? this.riders,
        thresholdM: thresholdM ?? this.thresholdM,
        conn: conn ?? this.conn,
        ended: ended ?? this.ended,
        fatalCloseCode: fatalCloseCode ?? this.fatalCloseCode,
      );
}

/// Pure reducer for server -> client WS messages (foundation doc §5).
ConvoyState applyMessage(ConvoyState s, Map<String, dynamic> msg) {
  switch (msg['type']) {
    case 'rider_positions':
      final list = (msg['riders'] as List).cast<Map<String, dynamic>>();
      return s.copyWith(riders: {for (final j in list) j['rider_id'] as String: Rider.fromJson(j)});
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
      return s.copyWith(riders: Map.of(s.riders)..remove(msg['rider_id']));
    case 'ride_ended':
      return s.copyWith(ended: true);
    case 'threshold_updated':
      return s.copyWith(thresholdM: msg['threshold_m'] as int);
    default:
      return s;
  }
}
