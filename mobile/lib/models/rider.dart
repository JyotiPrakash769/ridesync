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
    this.battery,
  });

  /// Phone battery %, when the rider's app reports it (v0.4).
  final int? battery;

  final String id;
  final String name;
  final RiderRole role;
  final RiderStatus status;
  final double? lat;
  final double? lng;
  final double? speedKph;
  final DateTime? lastSeenAt;

  bool get isLeader => role == RiderRole.leader;

  Rider withRole(RiderRole r) => Rider(
        id: id,
        name: name,
        role: r,
        status: status,
        lat: lat,
        lng: lng,
        speedKph: speedKph,
        lastSeenAt: lastSeenAt,
        battery: battery,
      );
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
        battery: (j['battery'] as num?)?.toInt(),
      );
}
