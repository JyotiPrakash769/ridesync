import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ridesync/core/network/api_client.dart';
import 'package:ridesync/core/storage/local_db.dart';
import 'package:ridesync/core/theme/app_theme.dart';
import 'package:ridesync/features/ride_join/join_ride_screen.dart';
import 'package:ridesync/state/ride_session_provider.dart';

import 'helpers/fakes.dart';

Future<void> _pump(WidgetTester tester, FakeApi api, SessionStore store, {String? prefill}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      sessionStoreProvider.overrideWithValue(store),
    ],
    child: MaterialApp(theme: AppTheme.dark(), home: JoinRideScreen(initialRideId: prefill)),
  ));
}

Future<void> _joinAs(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('displayNameField')), name);
  await tester.tap(find.text('Join ride'));
  await tester.pump();
  // Let real async work (Hive file I/O) complete, then render the result.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late SessionStore store;
  setUp(() async => store = await tempSessionStore());

  testWidgets('deep-link prefill skips to the name step', (tester) async {
    await _pump(tester, FakeApi(), store, prefill: 'k7q2mx');
    expect(find.text('Joining K7Q2MX'), findsOneWidget);
  });

  testWidgets('invalid typed code shows a format hint', (tester) async {
    await _pump(tester, FakeApi(), store);
    await tester.enterText(find.byKey(const Key('rideCodeField')), 'OOOO');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.textContaining('6 letters/numbers'), findsOneWidget);
  });

  testWidgets('404 shows "no ride with code"', (tester) async {
    await _pump(tester, FakeApi(joinError: const ApiException(ApiErrorKind.notFound, 404)),
        store, prefill: 'K7Q2MX');
    await _joinAs(tester, 'Ravi');
    expect(find.text('No ride with code K7Q2MX. Check the code and try again.'), findsOneWidget);
    expect(find.text('This ride has ended.'), findsNothing);
    expect(store.load(), isNull);
  });

  testWidgets('410 shows "ride has ended"', (tester) async {
    await _pump(tester, FakeApi(joinError: const ApiException(ApiErrorKind.gone, 410)),
        store, prefill: 'K7Q2MX');
    await _joinAs(tester, 'Ravi');
    expect(find.text('This ride has ended.'), findsOneWidget);
    expect(find.textContaining('No ride with code'), findsNothing);
    expect(store.load(), isNull);
  });

  testWidgets('successful join persists the session', (tester) async {
    final api = FakeApi(joinRiderId: 'rider-9');
    await _pump(tester, api, store, prefill: 'K7Q2MX');
    await _joinAs(tester, '  Ravi ');
    expect(api.joins.single, ('K7Q2MX', 'Ravi'));
    final s = store.load()!;
    expect((s.rideId, s.riderId, s.isLeader, s.displayName), ('K7Q2MX', 'rider-9', false, 'Ravi'));
    expect(s.riderToken, FakeApi.token);
  });
}
