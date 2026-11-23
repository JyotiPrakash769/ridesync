import '../models/rider.dart';

/// The locally persisted ride membership (no accounts in v0.1).
class RideSession {
  const RideSession({
    required this.rideId,
    required this.riderId,
    required this.role,
    required this.displayName,
  });

  final String rideId;
  final String riderId;
  final RiderRole role;
  final String displayName;

  bool get isLeader => role == RiderRole.leader;

  Map<String, dynamic> toMap() => {
        'ride_id': rideId,
        'rider_id': riderId,
        'role': role.name,
        'display_name': displayName,
      };

  static RideSession? fromMap(Map<String, dynamic> m) {
    final rideId = m['ride_id'], riderId = m['rider_id'], name = m['display_name'];
    if (rideId is! String || riderId is! String || name is! String) return null;
    return RideSession(
      rideId: rideId,
      riderId: riderId,
      role: parseRole(m['role'] as String?),
      displayName: name,
    );
  }
}
