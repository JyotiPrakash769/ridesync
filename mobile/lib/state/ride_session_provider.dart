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
    required bool leader,
    required String displayName,
    bool activate = true,
  }) async {
    final s = RideSession(
      rideId: rideId,
      riderId: riderId,
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
    final riderId = await ref.read(apiClientProvider).joinRide(rideId, displayName);
    return adopt(rideId: rideId, riderId: riderId, leader: false, displayName: displayName);
  }

  /// Forgets the ride locally (server-side end is a separate API call).
  Future<void> clear() async {
    _pending = null;
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }
}
