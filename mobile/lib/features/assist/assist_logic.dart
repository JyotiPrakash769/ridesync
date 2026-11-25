import 'dart:math';

import '../../models/rider.dart';
import '../../shared/geo.dart';

/// Group spread: the farthest online rider's distance from the leader.
class GroupSpread {
  const GroupSpread({required this.spreadM, this.lastRiderId, this.sweepGapM});

  final double spreadM;
  final String? lastRiderId;

  /// Leader <-> sweep (tail) rider distance, if a sweep is set and located.
  final double? sweepGapM;

  /// "Together": everyone within the falling-behind threshold of the leader.
  bool together(int thresholdM) => spreadM <= thresholdM;
}

GroupSpread? groupSpread(Iterable<Rider> riders, {String? sweepId}) {
  final leader = riders.where((r) => r.isLeader).firstOrNull;
  if (leader == null || !leader.hasPosition) return null;
  var worst = 0.0;
  String? last;
  double? sweepGap;
  for (final r in riders) {
    if (r.isLeader || !r.hasPosition || r.status == RiderStatus.offline) continue;
    final d = haversineM(leader.lat!, leader.lng!, r.lat!, r.lng!);
    if (d > worst) {
      worst = d;
      last = r.id;
    }
    if (r.id == sweepId) sweepGap = d;
  }
  return GroupSpread(spreadM: worst, lastRiderId: last, sweepGapM: sweepGap);
}

/// Rough time for a rider to reach a point: straight-line distance x 1.3
/// (roads aren't straight) at their speed, but never assume < 25 km/h.
int etaSeconds(Rider r, double lat, double lng) {
  if (!r.hasPosition) return -1;
  final d = haversineM(r.lat!, r.lng!, lat, lng) * 1.3;
  final kph = max(25.0, r.speedKph ?? 0);
  return (d / (kph / 3.6)).round();
}

/// Suggest regrouping once the group has been spread over 2x the threshold
/// for at least this long.
const Duration regroupHintAfter = Duration(minutes: 2);

class RegroupHint {
  DateTime? _since;

  /// Feed every positions update; returns true while a hint should show.
  bool update(GroupSpread? s, int thresholdM, DateTime now) {
    if (s == null || s.spreadM <= thresholdM * 2) {
      _since = null;
      return false;
    }
    _since ??= now;
    return now.difference(_since!) >= regroupHintAfter;
  }
}
