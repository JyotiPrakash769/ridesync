import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/shared/format.dart';
import 'package:ridesync/state/convoy_state.dart';

Map<String, dynamic> _r(String id, String name, {String role = 'member', String status = 'online',
        double? lat, double? lng, String? seen}) =>
    {'rider_id': id, 'name': name, 'role': role, 'lat': lat, 'lng': lng, 'speed_kph': null,
     'last_seen_at': seen, 'status': status};

void main() {
  test('rider_positions replaces the roster', () {
    var s = const ConvoyState();
    s = applyMessage(s, {
      'type': 'rider_positions',
      'riders': [
        _r('a', 'Asha', role: 'leader', lat: 1, lng: 2, seen: '2026-07-28T10:15:03Z'),
        _r('b', 'Ravi', status: 'weak'),
      ],
    });
    expect(s.riders.keys, ['a', 'b']);
    expect(s.leader!.name, 'Asha');
    expect(s.riders['a']!.lat, 1);
    expect(s.riders['b']!.status, RiderStatus.weak);
    expect(s.riders['a']!.lastSeenAt, DateTime.utc(2026, 7, 28, 10, 15, 3));
  });

  test('rider_joined adds, rider_left removes, ride_ended flags', () {
    var s = applyMessage(const ConvoyState(),
        {'type': 'rider_joined', 'rider_id': 'c', 'name': 'Chen', 'role': 'member'});
    expect(s.riders['c']!.name, 'Chen');
    expect(s.riders['c']!.status, RiderStatus.offline);
    s = applyMessage(s, {'type': 'rider_left', 'rider_id': 'c'});
    expect(s.riders, isEmpty);
    expect(applyMessage(s, {'type': 'ride_ended'}).ended, isTrue);
  });

  test('unknown messages are ignored', () {
    const s = ConvoyState();
    expect(identical(applyMessage(s, {'type': 'teleport'}), s), isTrue);
  });

  test('last-update labels', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    Rider r(RiderStatus st, Duration? ago) => Rider(
        id: 'x', name: 'X', role: RiderRole.member, status: st,
        lastSeenAt: ago == null ? null : now.subtract(ago));
    expect(lastUpdateLabel(r(RiderStatus.online, const Duration(seconds: 1)), now), 'Updated just now');
    expect(lastUpdateLabel(r(RiderStatus.weak, const Duration(seconds: 30)), now), 'Updated 30s ago');
    expect(lastUpdateLabel(r(RiderStatus.offline, const Duration(minutes: 4)), now), 'Last seen 4m ago');
    expect(lastUpdateLabel(r(RiderStatus.offline, null), now), 'Waiting for first update');
  });
}
