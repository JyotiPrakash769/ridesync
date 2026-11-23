import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ridesync/core/theme/app_theme.dart';
import 'package:ridesync/features/convoy_map/rider_marker_widget.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/shared/format.dart';
import 'package:ridesync/shared/geo.dart';
import 'package:ridesync/state/convoy_state.dart';
import 'package:ridesync/state/settings.dart';

import 'helpers/fakes.dart';

const double _degPerM = 1 / 111194.93;

Map<String, dynamic> _pos(String id, double lat, double lng, DateTime at,
        {String role = 'member', double? speed}) =>
    {'rider_id': id, 'name': 'R$id', 'role': role, 'lat': lat, 'lng': lng, 'speed_kph': speed,
     'last_seen_at': at.toIso8601String(), 'status': 'online'};

ConvoyState _apply(ConvoyState s, List<Map<String, dynamic>> riders) =>
    applyMessage(s, {'type': 'rider_positions', 'riders': riders});

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 10);

  test('bearing: north, east, south, west', () {
    expect(bearingDeg(0, 0, 1, 0), closeTo(0, 1e-6));
    expect(bearingDeg(0, 0, 0, 1), closeTo(90, 1e-6));
    expect(bearingDeg(1, 0, 0, 0), closeTo(180, 1e-6));
    expect(bearingDeg(0, 1, 0, 0), closeTo(270, 1e-6));
  });

  group('trails + heading', () {
    test('moving north builds a trail and a 0 degree heading', () {
      var s = const ConvoyState();
      for (var i = 0; i < 4; i++) {
        s = _apply(s, [_pos('a', 20 + i * 20 * _degPerM, 85, t0.add(Duration(seconds: 4 * i)))]);
      }
      expect(s.trails['a'], hasLength(4));
      expect(s.headingOf('a'), closeTo(0, 0.5));
    });

    test('GPS jitter under 3 m is not recorded and gives no heading', () {
      var s = _apply(const ConvoyState(), [_pos('a', 20, 85, t0)]);
      s = _apply(s, [_pos('a', 20 + 1 * _degPerM, 85, t0.add(const Duration(seconds: 4)))]);
      expect(s.trails['a'], hasLength(1));
      expect(s.headingOf('a'), isNull);
    });

    test('trail keeps only the last 5 minutes', () {
      var s = const ConvoyState();
      for (var i = 0; i <= 10; i++) {
        s = _apply(s, [_pos('a', 20 + i * 50 * _degPerM, 85, t0.add(Duration(minutes: i)))]);
      }
      final pts = s.trails['a']!;
      expect(pts.first.at, t0.add(const Duration(minutes: 5)));
      expect(pts.last.at, t0.add(const Duration(minutes: 10)));
    });

    test('rider_left drops the trail', () {
      var s = _apply(const ConvoyState(), [_pos('a', 20, 85, t0)]);
      s = applyMessage(s, {'type': 'rider_left', 'rider_id': 'a'});
      expect(s.trails, isEmpty);
    });
  });

  test('distance, speed and gap labels', () {
    expect(formatDistance(649.6), '650 m');
    expect(formatDistance(1234), '1.2 km');
    const leader = Rider(id: 'L', name: 'L', role: RiderRole.leader, status: RiderStatus.online,
        lat: 20, lng: 85);
    final m = Rider(id: 'm', name: 'm', role: RiderRole.member, status: RiderStatus.online,
        lat: 20 - 650 * _degPerM, lng: 85, speedKph: 41.6);
    expect(leaderGapLabel(m, leader), '650 m behind');
    expect(leaderGapLabel(leader, leader), 'Leading');
    expect(leaderGapLabel(m, null), isNull);
    expect(speedLabel(m), '42 km/h');
    expect(speedLabel(leader), isNull);
  });

  test('settings round-trip through Hive', () async {
    final store = await tempSettingsStore();
    expect(store.load().themeMode, ThemeMode.dark); // dark by default
    await store.save(const AppSettings(
        themeMode: ThemeMode.system, handlebarMode: true, voiceAlerts: false, localeCode: 'hi'));
    final s = store.load();
    expect((s.themeMode, s.handlebarMode, s.voiceAlerts, s.vibrationAlerts, s.localeCode),
        (ThemeMode.system, true, false, true, 'hi'));
  });

  test('handlebar mode raises contrast', () {
    expect(AppTheme.dark(highContrast: true).colorScheme,
        isNot(equals(AppTheme.dark().colorScheme)));
  });

  testWidgets('own marker reads "You" and shows a heading arrow', (tester) async {
    const me = Rider(id: 'me', name: 'Jyoti', role: RiderRole.member, status: RiderStatus.online,
        lat: 1, lng: 1);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: const Center(child: RiderMarkerWidget(rider: me, isSelf: true, headingDeg: 90))));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Jyoti'), findsNothing);
    expect(find.byIcon(Icons.navigation), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: const Center(child: RiderMarkerWidget(rider: me))));
    expect(find.text('Jyoti'), findsOneWidget);
    expect(find.byIcon(Icons.navigation), findsNothing);
  });
}
