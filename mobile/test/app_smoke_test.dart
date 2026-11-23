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

  testWidgets('saved session is restored on start', (tester) async {
    final store = await tester.runAsync(() async {
      final s = await tempSessionStore();
      await s.save(const RideSession(
          rideId: 'K7Q2MX', riderId: 'r', role: RiderRole.member, displayName: 'Ravi'));
      return s;
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [sessionStoreProvider.overrideWithValue(store!)],
      child: const RideSyncApp(),
    ));
    expect(find.text('Ride K7Q2MX'), findsOneWidget);
    expect(find.text('Leave ride'), findsOneWidget);
  });
}
