/// GET /rides/{id}/summary.
class RiderSummary {
  const RiderSummary({
    required this.riderId,
    required this.name,
    required this.isLeader,
    required this.distanceKm,
    required this.fallingBehindCount,
    this.maxGapM,
  });

  final String riderId;
  final String name;
  final bool isLeader;
  final double distanceKm;
  final int fallingBehindCount;
  final int? maxGapM;
}

class RideSummary {
  const RideSummary({
    required this.duration,
    required this.fallingBehindTotal,
    required this.riders,
    this.plannedDistanceKm,
    this.destination,
  });

  final double? plannedDistanceKm;
  final String? destination;
  final Duration duration;
  final int fallingBehindTotal;
  final List<RiderSummary> riders;

  factory RideSummary.fromJson(Map<String, dynamic> j) => RideSummary(
        duration: Duration(seconds: (j['duration_s'] as num).toInt()),
        fallingBehindTotal: (j['falling_behind_total'] as num).toInt(),
        plannedDistanceKm: (j['planned_distance_km'] as num?)?.toDouble(),
        destination: j['destination'] as String?,
        riders: [
          for (final r in (j['riders'] as List).cast<Map<String, dynamic>>())
            RiderSummary(
              riderId: r['rider_id'] as String,
              name: r['name'] as String,
              isLeader: r['role'] == 'leader',
              distanceKm: (r['distance_km'] as num).toDouble(),
              fallingBehindCount: (r['falling_behind_count'] as num).toInt(),
              maxGapM: (r['max_gap_m'] as num?)?.toInt(),
            ),
        ],
      );
}
