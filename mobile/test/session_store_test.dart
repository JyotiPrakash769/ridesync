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
      role: RiderRole.leader,
      displayName: 'Asha',
    );
    await store.save(s);
    final loaded = store.load()!;
    expect(loaded.rideId, 'K7Q2MX');
    expect(loaded.riderId, 'abc');
    expect(loaded.isLeader, isTrue);
    expect(loaded.displayName, 'Asha');

    await store.clear();
    expect(store.load(), isNull);
  });
}
