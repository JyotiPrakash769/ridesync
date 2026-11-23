import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/state/ride_session.dart';

import 'helpers/fakes.dart';

void main() {
  test('session round-trips through Hive and clears', () async {
    final store = await tempSessionStore();
    expect(store.load(), isNull);

    const s = RideSession(
      rideId: 'K7Q2MX',
      riderId: 'abc',
      riderToken: 'tok',
      role: RiderRole.leader,
      displayName: 'Asha',
    );
    await store.save(s);
    final loaded = store.load()!;
    expect(loaded.rideId, 'K7Q2MX');
    expect(loaded.riderId, 'abc');
    expect(loaded.isLeader, isTrue);
    expect(loaded.displayName, 'Asha');
    expect(loaded.riderToken, 'tok');
    expect(loaded.auth.headers, {'X-Rider-Id': 'abc', 'X-Rider-Token': 'tok'});

    await store.clear();
    expect(store.load(), isNull);
  });

  test('a v0.1 session without a token is not restored', () async {
    final store = await tempSessionStore();
    await store.save(const RideSession(
        rideId: 'K7Q2MX', riderId: 'a', riderToken: 't', role: RiderRole.member, displayName: 'R'));
    final raw = Map<String, dynamic>.of(store.load()!.toMap())..remove('rider_token');
    expect(RideSession.fromMap(raw), isNull);
  });
}
