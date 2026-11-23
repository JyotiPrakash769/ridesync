import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/core/alerts/announcer.dart';
import 'package:ridesync/models/ride_summary.dart';
import 'package:ridesync/models/rider.dart';
import 'package:ridesync/state/convoy_state.dart';
import 'package:ridesync/state/settings.dart';

Map<String, dynamic> _r(String id, String role) => {
      'rider_id': id, 'name': id.toUpperCase(), 'role': role, 'lat': 20.0, 'lng': 85.0,
      'speed_kph': null, 'last_seen_at': null, 'status': 'online',
    };

class _Spy {
  final said = <(String, String)>[];
  final buzzed = <List<int>>[];
  late final announcer = RideAnnouncer(
    speak: (t, lang) async => said.add((t, lang)),
    vibrate: (p) async => buzzed.add(p),
  );
}

void main() {
  group('reducer', () {
    test('regroup_point sets and clears', () {
      var s = applyMessage(const ConvoyState(), {
        'type': 'regroup_point',
        'point': {'lat': 20.3, 'lng': 85.8, 'label': 'Fuel station', 'set_at': '2026-01-01T10:00:00Z'},
      });
      expect((s.regroup!.label, s.regroup!.lat), ('Fuel station', 20.3));
      s = applyMessage(s, {'type': 'regroup_point', 'point': null});
      expect(s.regroup, isNull);
    });

    test('leader_changed swaps roles and clears alerts', () {
      var s = applyMessage(const ConvoyState(), {
        'type': 'rider_positions',
        'riders': [_r('a', 'leader'), _r('b', 'member')],
      });
      s = applyMessage(s, {'type': 'distance_alert', 'rider_id': 'b', 'name': 'B', 'distance_m': 600});
      s = applyMessage(s, {'type': 'leader_changed', 'leader_rider_id': 'b', 'name': 'B', 'reason': 'handoff'});
      expect(s.leader!.id, 'b');
      expect(s.riders['a']!.role, RiderRole.member);
      expect(s.alerts, isEmpty);
    });
  });

  test('takeover is offered only after the leader is gone 4+ minutes', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    Rider leader(Duration? ago) => Rider(id: 'L', name: 'L', role: RiderRole.leader,
        status: RiderStatus.offline, lastSeenAt: ago == null ? null : now.subtract(ago));
    expect(leaderGone(leader(const Duration(minutes: 3)), now), isFalse);
    expect(leaderGone(leader(const Duration(minutes: 5)), now), isTrue);
    expect(leaderGone(leader(null), now), isFalse);
    expect(leaderGone(null, now), isFalse);
  });

  group('announcer', () {
    const on = AppSettings();
    final alert = {'type': 'distance_alert', 'rider_id': 'b', 'name': 'Ravi', 'distance_m': 650};

    test('leader hears and feels the falling-behind alert', () async {
      final spy = _Spy();
      final said = await spy.announcer.onMessage(alert, isLeader: true, selfId: 'a', settings: on);
      expect(said, 'Ravi is falling behind, 650 meters.');
      expect(spy.said.single.$2, 'en-IN');
      expect(spy.buzzed.single, RideAnnouncer.alertPattern);
    });

    test('members are not told about distance alerts', () async {
      final spy = _Spy();
      expect(await spy.announcer.onMessage(alert, isLeader: false, selfId: 'b', settings: on), isNull);
      expect(spy.said, isEmpty);
      expect(spy.buzzed, isEmpty);
    });

    test('voice and vibration follow the settings', () async {
      final spy = _Spy();
      await spy.announcer.onMessage(alert, isLeader: true, selfId: 'a',
          settings: const AppSettings(voiceAlerts: false));
      expect((spy.said.length, spy.buzzed.length), (0, 1));
      await spy.announcer.onMessage(alert, isLeader: true, selfId: 'a',
          settings: const AppSettings(vibrationAlerts: false));
      expect((spy.said.length, spy.buzzed.length), (1, 1));
    });

    test('regroup, leader change and ride end are announced', () async {
      final spy = _Spy();
      Future<String?> say(Map<String, dynamic> m, {bool leader = false, String self = 'b'}) =>
          spy.announcer.onMessage(m, isLeader: leader, selfId: self, settings: on);
      expect(await say({'type': 'regroup_point', 'point': {'lat': 1, 'lng': 2, 'label': 'Food stop'}}),
          'Regroup point set: Food stop.');
      expect(await say({'type': 'regroup_point', 'point': {'lat': 1, 'lng': 2, 'label': 'x'}}, leader: true),
          isNull, reason: 'the leader set it');
      expect(await say({'type': 'leader_changed', 'leader_rider_id': 'b', 'name': 'B'}),
          'You are now the ride leader.');
      expect(await say({'type': 'leader_changed', 'leader_rider_id': 'c', 'name': 'Chen'}),
          'Chen is now leading the ride.');
      expect(await say({'type': 'ride_ended'}), 'The ride has ended.');
      expect(await say({'type': 'rider_positions', 'riders': []}), isNull);
    });
  });

  test('summary parses', () {
    final s = RideSummary.fromJson({
      'duration_s': 5400,
      'falling_behind_total': 2,
      'riders': [
        {'rider_id': 'a', 'name': 'Asha', 'role': 'leader', 'distance_km': 42.3,
         'falling_behind_count': 0, 'max_gap_m': null},
        {'rider_id': 'b', 'name': 'Ravi', 'role': 'member', 'distance_km': 41.9,
         'falling_behind_count': 2, 'max_gap_m': 900},
      ],
    });
    expect(s.duration, const Duration(minutes: 90));
    expect(s.riders.last.maxGapM, 900);
    expect(s.riders.first.isLeader, isTrue);
  });
}
