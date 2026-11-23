import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/network/api_client.dart';
import '../core/storage/local_db.dart';
import '../models/rider.dart';
import 'ride_session.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(Hive.box<dynamic>(LocalDb.sessionBox)),
);

/// Current ride membership; null when not in a ride. Restored from Hive on
/// startup, so backgrounding or a restart drops the rider back into the ride.
final rideSessionProvider =
    NotifierProvider<RideSessionNotifier, RideSession?>(RideSessionNotifier.new);

class RideSessionNotifier extends Notifier<RideSession?> {
  RideSession? _pending;

  @override
  RideSession? build() => ref.read(sessionStoreProvider).load();

  /// Persists a membership. With [activate] false it is saved (so a restart
  /// restores it) but the UI keeps showing the current screen until
  /// [activate] is called, e.g. the leader looking at the QR code first.
  Future<RideSession> adopt({
    required String rideId,
    required String riderId,
    required String riderToken,
    required bool leader,
    required String displayName,
    bool activate = true,
  }) async {
    final s = RideSession(
      rideId: rideId,
      riderId: riderId,
      riderToken: riderToken,
      role: leader ? RiderRole.leader : RiderRole.member,
      displayName: displayName,
    );
    await ref.read(sessionStoreProvider).save(s);
    if (activate) {
      state = s;
    } else {
      _pending = s;
    }
    return s;
  }

  void activate() {
    final p = _pending;
    if (p != null) {
      _pending = null;
      state = p;
    }
  }

  /// POST /rides/{id}/join, then persist as member.
  Future<RideSession> joinRide(String rideId, String displayName) async {
    final joined = await ref.read(apiClientProvider).joinRide(rideId, displayName);
    return adopt(
      rideId: rideId,
      riderId: joined.riderId,
      riderToken: joined.riderToken,
      leader: false,
      displayName: displayName,
    );
  }

  /// Role changed on the server (leader handoff); keeps Hive in sync.
  Future<void> updateRole(RiderRole role) async {
    final s = state;
    if (s == null || s.role == role) return;
    final next = s.copyWith(role: role);
    await ref.read(sessionStoreProvider).save(next);
    state = next;
  }

  /// Forgets the ride locally (server-side end is a separate API call).
  Future<void> clear() async {
    _pending = null;
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }
}
