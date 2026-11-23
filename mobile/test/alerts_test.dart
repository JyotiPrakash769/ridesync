import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ridesync/core/theme/app_theme.dart';
import 'package:ridesync/features/alerts/distance_alert_banner.dart';
import 'package:ridesync/features/alerts/threshold_selector.dart';
import 'package:ridesync/shared/geo.dart';
import 'package:ridesync/shared/widgets/floating_bar.dart';
import 'package:ridesync/state/convoy_state.dart';

const double _degPerM = 1 / 111194.93;

Map<String, dynamic> _pos(String id, String name, double lat, {String role = 'member'}) => {
      'rider_id': id, 'name': name, 'role': role, 'lat': lat, 'lng': 85.0,
      'speed_kph': null, 'last_seen_at': null, 'status': 'online',
    };

Map<String, dynamic> _alert(String id, String name, int d) =>
    {'type': 'distance_alert', 'rider_id': id, 'name': name, 'distance_m': d};

Widget _wrap(Widget w) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: w));

void main() {
  test('haversine matches the backend', () {
    expect(haversineM(0, 0, 1, 0), closeTo(111194.93, 0.01));
    expect(haversineM(20.296, 85.824, 20.296, 85.824), 0);
  });

  group('alert state', () {
    test('distance_alert adds; several collapse with the worst offender', () {
      var s = applyMessage(const ConvoyState(), _alert('b', 'Ravi', 510));
      expect(alertCopy(s.alerts).$1, 'Ravi is falling behind — 510 m');
      s = applyMessage(s, _alert('c', 'Chen', 900));
      s = applyMessage(s, _alert('d', 'Dev', 650));
      expect(alertCopy(s.alerts).$1, '3 riders falling behind');
      expect(alertCopy(s.alerts).$2, contains('Chen — 900 m'));
      expect(s.worstAlert!.riderId, 'c');
    });

    test('alert clears when the rider catches up below 90% of threshold', () {
      var s = const ConvoyState(thresholdM: 500);
      s = applyMessage(s, _alert('b', 'Ravi', 600));
      s = applyMessage(s, {'type': 'rider_positions', 'riders': [
        _pos('a', 'Asha', 20.0, role: 'leader'),
        _pos('b', 'Ravi', 20.0 - 480 * _degPerM),
      ]});
      expect(s.alerts['b']!.distanceM, 480, reason: 'between 450 and 500 m: kept, distance live');
      s = applyMessage(s, {'type': 'rider_positions', 'riders': [
        _pos('a', 'Asha', 20.0, role: 'leader'),
        _pos('b', 'Ravi', 20.0 - 300 * _degPerM),
      ]});
      expect(s.alerts, isEmpty);
    });

    test('rider_left and threshold_updated clear alerts', () {
      var s = applyMessage(const ConvoyState(), _alert('b', 'Ravi', 600));
      expect(applyMessage(s, {'type': 'rider_left', 'rider_id': 'b'}).alerts, isEmpty);
      s = applyMessage(s, {'type': 'threshold_updated', 'threshold_m': 1000});
      expect((s.thresholdM, s.alerts.isEmpty), (1000, true));
    });
  });

  testWidgets('banner shows summary and taps the worst offender', (tester) async {
    String? shown;
    final s = applyMessage(applyMessage(const ConvoyState(), _alert('b', 'Ravi', 510)),
        _alert('c', 'Chen', 900));
    await tester.pumpWidget(_wrap(DistanceAlertBanner(
      alerts: s.alerts,
      onShowWorst: (id) => shown = id,
      onDismiss: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('2 riders falling behind'), findsOneWidget);
    await tester.tap(find.text('2 riders falling behind'));
    expect(shown, 'c');
  });

  testWidgets('threshold chip is only in the bar when provided (leader)', (tester) async {
    Widget bar({Widget? chip}) => _wrap(Align(
          alignment: Alignment.bottomCenter,
          child: FloatingBar(
            riderCount: 3,
            onToggleStatus: () {},
            onRecenter: () {},
            thresholdChip: chip,
          ),
        ));
    await tester.pumpWidget(bar());
    expect(find.byType(ThresholdChip), findsNothing);
    expect(find.text('3'), findsOneWidget);

    int? picked;
    await tester.pumpWidget(bar(chip: ThresholdChip(thresholdM: 500, onChanged: (m) => picked = m)));
    expect(find.text('500 m'), findsOneWidget);
    await tester.tap(find.text('500 m'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('300 m'));
    await tester.pumpAndSettle();
    expect(picked, 300);
  });
}
