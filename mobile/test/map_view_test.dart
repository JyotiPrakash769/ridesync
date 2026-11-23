import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ridesync/core/theme/app_theme.dart';
import 'package:ridesync/features/convoy_map/convoy_map_view.dart';
import 'package:ridesync/features/convoy_map/map_geometry.dart';
import 'package:ridesync/features/convoy_map/rider_marker_widget.dart';
import 'package:ridesync/models/rider.dart';

Rider _r(String id, {double? lat, double? lng, bool leader = false,
        RiderStatus status = RiderStatus.online}) =>
    Rider(id: id, name: 'Rider $id', role: leader ? RiderRole.leader : RiderRole.member,
        status: status, lat: lat, lng: lng);

void main() {
  test('OpenStreetMap is the default provider', () {
    expect(ConvoyMapView.usesGoogle, isFalse);
  });

  group('MapGeometry.bounds', () {
    test('null when nobody has a position', () {
      expect(MapGeometry.bounds([_r('a')]), isNull);
    });

    test('spans every positioned rider', () {
      final b = MapGeometry.bounds([
        _r('a', lat: 20.30, lng: 85.82),
        _r('b', lat: 20.28, lng: 85.85),
        _r('c'),
      ])!;
      expect(b, ((20.28, 85.82), (20.30, 85.85)));
    });

    test('pads a group standing at one spot', () {
      final ((s, w), (n, e)) = MapGeometry.bounds([
        _r('a', lat: 20.0, lng: 85.0),
        _r('b', lat: 20.0, lng: 85.0),
      ])!;
      expect(n - s, closeTo(0.0005, 1e-9));
      expect(e - w, closeTo(0.0005, 1e-9));
    });
  });

  testWidgets('leader marker has ring + star; members do not', (tester) async {
    Future<void> pump(Rider r) => tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(), home: Center(child: RiderMarkerWidget(rider: r))));

    await pump(_r('L', lat: 1, lng: 1, leader: true));
    expect(find.text('Rider L'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);

    await pump(_r('M', lat: 1, lng: 1));
    expect(find.text('Rider M'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('offline riders are dimmed', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Center(child: RiderMarkerWidget(rider: _r('X', status: RiderStatus.offline)))));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.5);
  });
}
