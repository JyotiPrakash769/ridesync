import '../core/network/api_client.dart';
import '../models/rider.dart';

/// The locally persisted ride membership (no accounts in v0.1).
class RideSession {
  const RideSession({
    required this.rideId,
    required this.riderId,
    required this.riderToken,
    required this.role,
    required this.displayName,
  });

  final String rideId;
  final String riderId;

  /// Secret from create/join; proves to the server that we are [riderId].
  /// Stored only in the app's private Hive box.
  final String riderToken;
  final RiderRole role;
  final String displayName;

  bool get isLeader => role == RiderRole.leader;

  RiderAuth get auth => RiderAuth(riderId, riderToken);

  RideSession copyWith({RiderRole? role}) => RideSession(
        rideId: rideId,
        riderId: riderId,
        riderToken: riderToken,
        role: role ?? this.role,
        displayName: displayName,
      );

  Map<String, dynamic> toMap() => {
        'ride_id': rideId,
        'rider_id': riderId,
        'rider_token': riderToken,
        'role': role.name,
        'display_name': displayName,
      };

  static RideSession? fromMap(Map<String, dynamic> m) {
    final rideId = m['ride_id'], riderId = m['rider_id'], name = m['display_name'];
    final token = m['rider_token'];
    // v0.1 sessions have no token and can't authenticate any more: drop them.
    if (rideId is! String || riderId is! String || name is! String || token is! String) {
      return null;
    }
    return RideSession(
      rideId: rideId,
      riderId: riderId,
      riderToken: token,
      role: parseRole(m['role'] as String?),
      displayName: name,
    );
  }
}
