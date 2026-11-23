import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/app.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/state/ride_session.dart';
import 'package:ridesync/state/ride_session_provider.dart';
import 'package:ridesync/state/settings.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('first run shows the intro, then home', (tester) async {
    final stores = await tester.runAsync(
        () async => (await tempSessionStore(), await tempSettingsStore()));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(stores!.$1),
        settingsStoreProvider.overrideWithValue(stores.$2),
      ],
      child: const RideSyncApp(),
    ));
    expect(find.text('Ride together'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Create a ride'), findsOneWidget);
    expect(find.text('Join a ride'), findsOneWidget);
    expect(stores.$2.load().introSeen, isTrue);
  });

  testWidgets('intro already seen -> home screen directly', (tester) async {
    final stores = await tester.runAsync(() async =>
        (await tempSessionStore(), await tempSettingsStore(initial: const AppSettings(introSeen: true))));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(stores!.$1),
        settingsStoreProvider.overrideWithValue(stores.$2),
      ],
      child: const RideSyncApp(),
    ));
    expect(find.text('Create a ride'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
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
