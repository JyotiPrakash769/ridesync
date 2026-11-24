import 'regroup_point.dart';
import 'trip_plan.dart';
import 'rider.dart';

/// GET /rides/{id} response.
class RideInfo {
  const RideInfo({
    required this.rideId,
    required this.active,
    required this.thresholdM,
    required this.leaderRiderId,
    required this.expiresAt,
    required this.riders,
    this.regroup,
    this.plan,
  });

  final RegroupPoint? regroup;
  final TripPlan? plan;
  final String rideId;
  final bool active;
  final int thresholdM;
  final String? leaderRiderId;
  final DateTime expiresAt;
  final List<Rider> riders;

  factory RideInfo.fromJson(Map<String, dynamic> j) => RideInfo(
        rideId: j['ride_id'] as String,
        active: j['status'] == 'active',
        thresholdM: j['threshold_m'] as int,
        leaderRiderId: j['leader_rider_id'] as String?,
        expiresAt: DateTime.parse(j['expires_at'] as String).toUtc(),
        riders: [
          for (final r in (j['riders'] as List)) Rider.fromJson(r as Map<String, dynamic>),
        ],
        regroup: RegroupPoint.fromJson(j['regroup']),
        plan: TripPlan.fromJson(j['plan']),
      );
}

/// POST /rides response.
class CreatedRide {
  const CreatedRide({
    required this.rideId,
    required this.leaderRiderId,
    required this.qrPayload,
    required this.riderToken,
  });

  final String rideId;
  final String leaderRiderId;
  final String qrPayload;
  final String riderToken;
}
