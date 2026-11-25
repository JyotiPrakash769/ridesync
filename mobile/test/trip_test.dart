import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ridesync/core/alerts/announcer.dart';
import 'package:ridesync/core/theme/app_theme.dart';
import 'package:ridesync/features/trip/place_search_screen.dart';
import 'package:ridesync/features/trip/trip_assist.dart';
import 'package:ridesync/features/trip/trip_card.dart';
import 'package:ridesync/features/trip/trip_progress.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/trip_plan.dart';
import 'package:ridesync/shared/polyline.dart';
import 'package:ridesync/state/convoy_state.dart';
import 'package:ridesync/state/ride_session.dart';
import 'package:ridesync/state/ride_session_provider.dart';
import 'package:ridesync/state/settings.dart';

import 'helpers/fakes.dart';

const double _m = 1 / 111194.93;

/// 10 km straight north from (20, 85), one stop at 5 km, Google says 15 min.
Map<String, dynamic> _planJson({bool approximate = false}) => {
      'origin': {'lat': 20.0, 'lng': 85.0, 'label': 'Start'},
      'destination': {'lat': 20.0 + 10000 * _m, 'lng': 85.0, 'label': 'Puri'},
      'stops': [
        {'lat': 20.0 + 5000 * _m, 'lng': 85.0, 'label': 'Fuel'},
      ],
      'polyline': encodePolyline([(20.0, 85.0), (20.0 + 5000 * _m, 85.0), (20.0 + 10000 * _m, 85.0)]),
      'distance_m': 10000,
      'duration_s': 900,
      'legs': [],
      'provider': approximate ? 'straight_line' : 'google:two_wheeler',
      'approximate': approximate,
    };

void main() {
  test('polyline codec matches Google\'s reference example', () {
    const enc = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';
    const pts = [(38.5, -120.2), (40.7, -120.95), (43.252, -126.453)];
    expect(decodePolyline(enc), pts);
    expect(encodePolyline(pts), enc);
  });

  group('trip progress', () {
    final plan = TripPlan.fromJson(_planJson())!;

    test('remaining distance, time and next stop', () {
      final p = tripProgress(plan, 20.0 + 3000 * _m, 85.0);
      expect(p.remainingM, closeTo(7000, 20));
      expect(p.remainingS, closeTo(630, 3)); // 70% of 15 min
      expect(p.nextStop!.label, 'Fuel');
      expect(p.nextStopM, closeTo(2000, 20));
      expect(p.isOffRoute, isFalse);
    });

    test('past the stop, next stop is none; near the end counts as arrived', () {
      final p = tripProgress(plan, 20.0 + 9950 * _m, 85.0);
      expect(p.nextStop, isNull);
      expect(p.arrived, isTrue);
    });

    test('off-route distance', () {
      final p = tripProgress(plan, 20.0 + 3000 * _m, 85.0 + 400 * _m / 0.9397);
      expect(p.distanceFromRouteM, closeTo(400, 5));
      expect(p.isOffRoute, isTrue);
    });

    test('approximate plans estimate time at 40 km/h', () {
      final a = TripPlan.fromJson(_planJson(approximate: true))!;
      expect(tripProgress(a, 20.0, 85.0).remainingS, closeTo(900, 5)); // 10 km @ 40 km/h
    });

    test('duration format', () {
      expect(formatDuration(25 * 60), '25 min');
      expect(formatDuration(72 * 60), '1h 12m');
    });
  });

  group('reducer', () {
    test('trip_plan sets and clears; route_status tracks off-route riders', () {
      var s = applyMessage(const ConvoyState(), {'type': 'trip_plan', 'plan': _planJson()});
      expect(s.plan!.destination.label, 'Puri');
      expect(s.plan!.route, hasLength(3));
      s = applyMessage(s, {'type': 'route_status', 'rider_id': 'b', 'name': 'Ravi', 'off_route': true, 'distance_m': 320});
      expect(s.offRoute, {'b': 320});
      s = applyMessage(s, {'type': 'route_status', 'rider_id': 'b', 'name': 'Ravi', 'off_route': false, 'distance_m': 90});
      expect(s.offRoute, isEmpty);
      s = applyMessage(s, {'type': 'trip_plan', 'plan': null});
      expect(s.plan, isNull);
    });
  });

  group('announcer', () {
    Future<String?> say(Map<String, dynamic> m, {bool leader = false, String self = 'b'}) =>
        RideAnnouncer(speak: (_, _) async {}, vibrate: (_) async {})
            .onMessage(m, isLeader: leader, selfId: self, settings: const AppSettings());
    final off = {'type': 'route_status', 'rider_id': 'b', 'name': 'Ravi', 'off_route': true, 'distance_m': 320};

    test('the rider hears they are off route; the leader hears who', () async {
      expect(await say(off), 'You are off the planned route.');
      expect(await say(off, leader: true, self: 'a'), 'Ravi is off the planned route, 320 meters.');
      expect(await say(off, self: 'c'), isNull); // other members aren't told
      expect(await say({...off, 'off_route': false}), 'You are back on the route.');
    });

    test('members hear a new trip plan', () async {
      expect(await say({'type': 'trip_plan', 'plan': _planJson()}), 'Trip planned to Puri.');
      expect(await say({'type': 'trip_plan', 'plan': _planJson()}, leader: true), isNull);
    });
  });

  testWidgets('trip card shows distance, time left and next stop', (tester) async {
    final plan = TripPlan.fromJson(_planJson())!;
    final now = DateTime.utc(2026, 11, 25, 10);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: TripCard(
            plan: plan, progress: tripProgress(plan, 20.0 + 3000 * _m, 85.0), onTap: () {}, now: now),
      ),
    ));
    final eta = formatClock(now.add(const Duration(seconds: 630)));
    expect(find.text('Puri · 7.0 km · arrive ~$eta'), findsOneWidget);
    expect(find.text('11 min left · Next: Fuel in 2.0 km'), findsOneWidget);
  });

  testWidgets('place search returns the chosen place', (tester) async {
    final api = FakeApi();
    final store = await tester.runAsync(() async {
      final s = await tempSessionStore();
      await s.save(const RideSession(
          rideId: 'K7Q2MX', riderId: 'a', riderToken: 't', role: RiderRole.leader, displayName: 'A'));
      return s;
    });
    TripPlace? picked;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(store!),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => picked = await Navigator.of(context).push<TripPlace>(
                    MaterialPageRoute(builder: (_) => const PlaceSearchScreen(title: 'Where to?'))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('placeSearchField')), 'puri');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.searches, ['puri']);
    await tester.tap(find.text('Puri Beach'));
    await tester.pumpAndSettle();
    expect((picked!.label, picked!.lat), ('Puri Beach', 19.7984));
  });
}
