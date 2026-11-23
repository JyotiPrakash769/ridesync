import 'geo.dart';
import '../models/rider.dart';

/// "just now", "12s ago", "4m ago", "2h ago".
String formatAgo(DateTime? t, DateTime now) {
  if (t == null) return 'never';
  final d = now.difference(t);
  if (d.inSeconds < 3) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}

/// Status-sheet subtitle. Offline riders read "Last seen Xm ago".
String lastUpdateLabel(Rider r, DateTime now) {
  if (r.lastSeenAt == null) return 'Waiting for first update';
  final ago = formatAgo(r.lastSeenAt, now);
  return r.status == RiderStatus.offline ? 'Last seen $ago' : 'Updated $ago';
}

String statusLabel(RiderStatus s) => switch (s) {
      RiderStatus.online => 'Online',
      RiderStatus.weak => 'Weak signal',
      RiderStatus.offline => 'Offline',
    };

/// "650 m" / "1.2 km".
String formatDistance(double meters) =>
    meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';

/// Member's straight-line distance to the leader ("650 m behind"), "Leading"
/// for the leader, null when either position is unknown.
String? leaderGapLabel(Rider r, Rider? leader) {
  if (r.isLeader) return 'Leading';
  if (leader == null || !leader.hasPosition || !r.hasPosition) return null;
  return '${formatDistance(haversineM(leader.lat!, leader.lng!, r.lat!, r.lng!))} behind';
}

/// "42 km/h" when moving, null when stopped/unknown.
String? speedLabel(Rider r) {
  final v = r.speedKph;
  if (v == null || v < 1) return null;
  return '${v.round()} km/h';
}
