enum RiderRole { leader, member }

enum RiderStatus { online, weak, offline }

RiderRole parseRole(String? s) => s == 'leader' ? RiderRole.leader : RiderRole.member;

RiderStatus parseStatus(String? s) => switch (s) {
      'online' => RiderStatus.online,
      'weak' => RiderStatus.weak,
      _ => RiderStatus.offline,
    };

/// One rider: same shape as GET /rides/{id} riders[] and WS rider_positions.
class Rider {
  const Rider({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    this.lat,
    this.lng,
    this.speedKph,
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final RiderRole role;
  final RiderStatus status;
  final double? lat;
  final double? lng;
  final double? speedKph;
  final DateTime? lastSeenAt;

  bool get isLeader => role == RiderRole.leader;
  bool get hasPosition => lat != null && lng != null;

  factory Rider.fromJson(Map<String, dynamic> j) => Rider(
        id: j['rider_id'] as String,
        name: j['name'] as String,
        role: parseRole(j['role'] as String?),
        status: parseStatus(j['status'] as String?),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        speedKph: (j['speed_kph'] as num?)?.toDouble(),
        lastSeenAt: j['last_seen_at'] == null
            ? null
            : DateTime.parse(j['last_seen_at'] as String).toUtc(),
      );
}
