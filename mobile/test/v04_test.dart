import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ridesync/core/alerts/announcer.dart';
import 'package:ridesync/core/storage/saved_trips.dart';
import 'package:ridesync/core/theme/app_theme.dart';
import 'package:ridesync/features/assist/assist_logic.dart';
import 'package:ridesync/features/assist/assist_widgets.dart';
import 'package:ridesync/features/trip/navigation_launcher.dart';
import 'package:ridesync/features/trip/trip_assist.dart';
import 'package:ridesync/features/trip/trip_card.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/models/trip_plan.dart';
import 'package:ridesync/shared/polyline.dart';
import 'package:ridesync/state/convoy_state.dart';
import 'package:ridesync/state/settings.dart';

import 'helpers/fakes.dart';

const double _m = 1 / 111194.93;

/// 200 km north in two legs: 120 km (2h) to "Fuel", then 80 km (1h20).
TripPlan _plan({int? fuel, DateTime? departure}) => TripPlan.fromJson({
      'origin': {'lat': 20.0, 'lng': 85.0, 'label': 'Start'},
      'destination': {'lat': 20.0 + 200000 * _m, 'lng': 85.0, 'label': 'Puri'},
      'stops': [
        {'lat': 20.0 + 120000 * _m, 'lng': 85.0, 'label': 'Fuel'},
      ],
      'polyline': encodePolyline([(20.0, 85.0), (20.0 + 120000 * _m, 85.0), (20.0 + 200000 * _m, 85.0)]),
      'distance_m': 200000,
      'duration_s': 12000,
      'legs': [
        {'distance_m': 120000, 'duration_s': 7200},
        {'distance_m': 80000, 'duration_s': 4800},
      ],
      'provider': 'google:two_wheeler',
      'approximate': false,
      'fuel_range_km': fuel,
      'departure_at': departure?.toIso8601String(),
    })!;

Rider _r(String id, double northM, {bool leader = false, double? speed, RiderStatus st = RiderStatus.online, int? battery}) =>
    Rider(id: id, name: id.toUpperCase(), role: leader ? RiderRole.leader : RiderRole.member,
        status: st, lat: 20.0 + northM * _m, lng: 85.0, speedKph: speed, battery: battery);

void main() {
  group('trip assist', () {
    test('long legs, fuel gaps and break midpoint', () {
      final p = _plan(fuel: 100);
      expect(longLegs(p), [0]); // 2h > 90 min
      expect(fuelGaps(p, 100), [0]); // 120 km > 100 km
      expect(fuelGaps(p, 180), isEmpty);
      expect(legEndLabel(p, 0), 'Fuel');
      expect(legEndLabel(p, 1), 'Puri');
      final mid = legMidpoint(p, 0);
      expect((mid.lat - 20.0) / _m, closeTo(60000, 50));
      expect(mid.label, 'Break');
    });

    test('stops ahead for re-routing', () {
      final p = _plan();
      expect(stopsAhead(p, 20.0 + 50000 * _m, 85.0).map((s) => s.label), ['Fuel']);
      expect(stopsAhead(p, 20.0 + 130000 * _m, 85.0), isEmpty);
    });

    test('arrival clock uses departure when it is ahead', () {
      final now = DateTime.utc(2026, 11, 25, 0, 30);
      final dep = DateTime.utc(2026, 11, 25, 1, 0);
      expect(arrivalTime(_plan(departure: dep), now: now), dep.add(const Duration(seconds: 12000)));
      expect(arrivalTime(_plan(), now: now, remainingS: 600), now.add(const Duration(minutes: 10)));
    });

    test('navigation goes to the next stop, else the destination', () {
      final p = _plan();
      expect(navigationTarget(p, p.stops.first).label, 'Fuel');
      expect(navigationTarget(p, null).label, 'Puri');
    });
  });

  group('leader assist', () {
    test('group spread, last rider and sweep gap', () {
      final s = groupSpread([
        _r('l', 0, leader: true),
        _r('a', -300),
        _r('b', -1800),
        _r('c', -5000, st: RiderStatus.offline), // offline riders don't count
      ], sweepId: 'a')!;
      expect(s.spreadM, closeTo(1800, 2));
      expect(s.lastRiderId, 'b');
      expect(s.sweepGapM, closeTo(300, 2));
      expect(s.together(500), isFalse);
      expect(s.together(2000), isTrue);
    });

    test('eta assumes at least 25 km/h and 1.3x road factor', () {
      expect(etaSeconds(_r('a', 0), 20.0 + 1000 * _m, 85.0), closeTo(187, 2));
      expect(etaSeconds(_r('a', 0, speed: 50), 20.0 + 1000 * _m, 85.0), closeTo(94, 2));
    });

    test('regroup hint after 2 minutes spread over 2x threshold', () {
      final h = RegroupHint();
      final t0 = DateTime.utc(2026);
      const wide = GroupSpread(spreadM: 1200);
      expect(h.update(wide, 500, t0), isFalse);
      expect(h.update(wide, 500, t0.add(const Duration(seconds: 119))), isFalse);
      expect(h.update(wide, 500, t0.add(const Duration(seconds: 121))), isTrue);
      expect(h.update(const GroupSpread(spreadM: 400), 500, t0.add(const Duration(minutes: 3))), isFalse);
    });
  });

  group('reducer', () {
    test('stopped / moving / arrived / sweep / quick message', () {
      var s = applyMessage(const ConvoyState(), {
        'type': 'rider_stopped', 'rider_id': 'b', 'name': 'B', 'stopped_s': 200, 'lat': 1.0, 'lng': 2.0,
      });
      expect(s.stopped['b']!.lat, 1.0);
      s = applyMessage(s, {'type': 'rider_moving', 'rider_id': 'b', 'name': 'B'});
      expect(s.stopped, isEmpty);
      s = applyMessage(s, {'type': 'rider_arrived', 'rider_id': 'b', 'name': 'B'});
      expect(s.arrived, {'b'});
      s = applyMessage(s, {'type': 'sweep_changed', 'sweep_rider_id': 'b'});
      expect(s.sweepId, 'b');
      s = applyMessage(s, {'type': 'rider_left', 'rider_id': 'b'});
      expect(s.sweepId, isNull);
      s = applyMessage(s, {'type': 'quick_message', 'rider_id': 'a', 'name': 'Asha', 'role': 'leader', 'code': 'slow_down'});
      expect((s.lastQuick!.code, s.lastQuick!.fromLeader), ('slow_down', true));
    });

    test('battery parses from rider_positions', () {
      final s = applyMessage(const ConvoyState(), {'type': 'rider_positions', 'riders': [
        {'rider_id': 'a', 'name': 'A', 'role': 'member', 'lat': 1, 'lng': 2, 'speed_kph': null,
         'last_seen_at': null, 'status': 'online', 'battery': 12},
      ]});
      expect(s.riders['a']!.battery, 12);
    });
  });

  group('announcer', () {
    Future<String?> say(Map<String, dynamic> m, {bool leader = false, String self = 'z'}) =>
        RideAnnouncer(speak: (_, _) async {}, vibrate: (_) async {})
            .onMessage(m, isLeader: leader, selfId: self, settings: const AppSettings());

    test('quick messages, stopped, arrived, low battery', () async {
      expect(await say({'type': 'quick_message', 'rider_id': 'a', 'name': 'Asha', 'role': 'leader', 'code': 'slow_down'}),
          'Leader: Slow down.');
      expect(await say({'type': 'quick_message', 'rider_id': 'b', 'name': 'Ravi', 'role': 'member', 'code': 'need_fuel'}),
          'Ravi: I need fuel.');
      expect(await say({'type': 'quick_message', 'rider_id': 'z', 'name': 'Me', 'role': 'member', 'code': 'help'}),
          isNull, reason: 'not my own');
      expect(await say({'type': 'rider_stopped', 'rider_id': 'b', 'name': 'Ravi'}, leader: true), 'Ravi has stopped.');
      expect(await say({'type': 'rider_stopped', 'rider_id': 'b', 'name': 'Ravi'}), isNull);
      expect(await say({'type': 'rider_arrived', 'rider_id': 'b', 'name': 'Ravi'}, leader: true), 'Ravi has arrived.');
      expect(await say({'type': 'low_battery', 'rider_id': 'b', 'name': 'Ravi', 'battery': 12}, leader: true),
          "Ravi's phone battery is at 12 percent.");
    });
  });

  test('saved trips round-trip and newest first', () async {
    final store = SavedTripsStore(await openTempBox('saved_trips_test'));
    await store.save(const SavedTrip(name: 'A', destination: TripPlace(lat: 1, lng: 2, label: 'X')));
    await store.save(const SavedTrip(
        name: 'B',
        origin: TripPlace(lat: 3, lng: 4, label: 'Home'),
        destination: TripPlace(lat: 5, lng: 6, label: 'Puri'),
        stops: [TripPlace(lat: 7, lng: 8, label: 'Fuel')]));
    final all = store.all();
    expect(all.map((e) => e.$2.name), ['B', 'A']);
    expect((all.first.$2.origin!.label, all.first.$2.stops.single.label), ('Home', 'Fuel'));
    await store.remove(all.first.$1);
    expect(store.all().single.$2.name, 'A');
  });

  testWidgets('trip card before departure shows leave and arrive times', (tester) async {
    final now = DateTime.utc(2026, 11, 25, 0, 0);
    final dep = now.add(const Duration(hours: 6));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: TripCard(
        plan: _plan(departure: dep),
        onTap: () {},
        onNavigate: () {},
        onEdit: () {},
        weatherWarning: 'Rain likely at Puri ~9:20 AM',
        now: now,
      )),
    ));
    expect(find.textContaining('leave ${formatClock(dep)}'), findsOneWidget);
    expect(find.textContaining('arrive ~${formatClock(dep.add(const Duration(seconds: 12000)))}'), findsOneWidget);
    expect(find.text('Rain likely at Puri ~9:20 AM'), findsOneWidget);
    expect(find.byTooltip('Navigate with Google Maps'), findsOneWidget);
    expect(find.byTooltip('Edit trip'), findsOneWidget);
  });

  testWidgets('leader assist card summarises spread and arrivals', (tester) async {
    final riders = {for (final r in [_r('l', 0, leader: true), _r('a', -300), _r('b', -1800)]) r.id: r};
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: LeaderAssistCard(
        spread: groupSpread(riders.values, sweepId: 'b')!,
        riders: riders,
        thresholdM: 500,
        sweepId: 'b',
        arrived: const {'a'},
        hasPlan: true,
      )),
    ));
    expect(find.textContaining('Spread 1.8 km · last: B · sweep 1.8 km back · arrived 1/2, waiting: B'),
        findsOneWidget);
  });

  testWidgets('quick message sheet offers leader codes only to the leader', (tester) async {
    Future<void> open(bool leader) async {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(leader),
        theme: AppTheme.dark(),
        home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
          onPressed: () => showQuickMessageSheet(context, isLeader: leader),
          child: const Text('open'),
        )))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await open(false);
    expect(find.text('Slow down'), findsNothing);
    expect(find.text('I need fuel'), findsOneWidget);
    await open(true);
    expect(find.text('Slow down'), findsOneWidget);
  });
}
