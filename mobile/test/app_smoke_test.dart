import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/app.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/state/ride_session.dart';
import 'package:ridesync/state/ride_session_provider.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('no saved session -> home screen', (tester) async {
    final store = await tester.runAsync(tempSessionStore);
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionStoreProvider.overrideWithValue(store!)],
      child: const RideSyncApp(),
    ));
    expect(find.text('Create a ride'), findsOneWidget);
    expect(find.text('Join a ride'), findsOneWidget);
  });

  // The map screen hosts a native GoogleMap view that can't render in a
  // widget test, so restoration is checked at the provider level.
  test('saved session is restored on start', () async {
    final store = await tempSessionStore();
    await store.save(const RideSession(
        rideId: 'K7Q2MX', riderId: 'r', riderToken: 't', role: RiderRole.member, displayName: 'Ravi'));
    final container = ProviderContainer(
      overrides: [sessionStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final s = container.read(rideSessionProvider)!;
    expect((s.rideId, s.riderId, s.isLeader), ('K7Q2MX', 'r', false));
  });
}
