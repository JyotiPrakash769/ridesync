import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

import '../../state/settings.dart';

/// What the announcer says. Kept separate so translations (and TTS language)
/// can be swapped in without touching the logic.
class AnnouncerStrings {
  const AnnouncerStrings({this.ttsLanguage = 'en-IN'});

  final String ttsLanguage;

  String fallingBehind(String name, int meters) => '$name is falling behind, $meters meters.';
  String regroupSet(String label) =>
      label.isEmpty ? 'Regroup point set.' : 'Regroup point set: $label.';
  String youLead() => 'You are now the ride leader.';
  String newLeader(String name) => '$name is now leading the ride.';
  String rideEnded() => 'The ride has ended.';
  String offRoute(String name, int meters) => '$name is off the planned route, $meters meters.';
  String youOffRoute() => 'You are off the planned route.';
  String youBackOnRoute() => 'You are back on the route.';
  String quick(String name, String code, bool fromLeader) {
    final text = quickMessageText(code);
    return fromLeader ? 'Leader: $text.' : '$name: $text.';
  }

  String stopped(String name) => '$name has stopped.';
  String arrived(String name) => '$name has arrived.';
  String lowBattery(String name, int pct) => '$name\'s phone battery is at $pct percent.';
  String tripPlanned(String destination) =>
      destination.isEmpty ? 'A trip has been planned.' : 'Trip planned to $destination.';
}

typedef SpeakFn = Future<void> Function(String text, String language);
typedef VibrateFn = Future<void> Function(List<int> pattern);

/// Turns ride events into speech and vibration, so riders don't have to look
/// at the screen. Respects the Spoken alerts / Vibrate settings.
class RideAnnouncer {
  RideAnnouncer({SpeakFn? speak, VibrateFn? vibrate})
      : _speak = speak ?? _ttsSpeak,
        _vibrate = vibrate ?? _deviceVibrate;

  final SpeakFn _speak;
  final VibrateFn _vibrate;

  static const List<int> alertPattern = [0, 400, 150, 400];
  static const List<int> infoPattern = [0, 150];

  /// Returns what was announced (for tests), or null.
  Future<String?> onMessage(
    Map<String, dynamic> msg, {
    required bool isLeader,
    required String selfId,
    required AppSettings settings,
    AnnouncerStrings strings = const AnnouncerStrings(),
  }) async {
    String? say;
    List<int>? buzz;
    switch (msg['type']) {
      case 'distance_alert':
        if (!isLeader) return null; // the leader is the one who needs to know
        say = strings.fallingBehind(msg['name'] as String, (msg['distance_m'] as num).round());
        buzz = alertPattern;
      case 'regroup_point':
        final p = msg['point'];
        if (p is! Map || isLeader) return null; // the leader set it themselves
        say = strings.regroupSet((p['label'] as String?) ?? '');
        buzz = infoPattern;
      case 'leader_changed':
        final id = msg['leader_rider_id'];
        say = id == selfId ? strings.youLead() : strings.newLeader(msg['name'] as String);
        buzz = infoPattern;
      case 'route_status':
        final mine = msg['rider_id'] == selfId;
        final off = msg['off_route'] == true;
        if (mine) {
          say = off ? strings.youOffRoute() : strings.youBackOnRoute();
          buzz = off ? alertPattern : infoPattern;
        } else if (isLeader && off) {
          say = strings.offRoute(msg['name'] as String, (msg['distance_m'] as num).round());
          buzz = alertPattern;
        } else {
          return null;
        }
      case 'quick_message':
        if (msg['rider_id'] == selfId) return null;
        say = strings.quick(msg['name'] as String, msg['code'] as String, msg['role'] == 'leader');
        buzz = msg['code'] == 'help' ? alertPattern : infoPattern;
      case 'rider_stopped':
        if (!isLeader || msg['rider_id'] == selfId) return null;
        say = strings.stopped(msg['name'] as String);
        buzz = alertPattern;
      case 'rider_arrived':
        if (!isLeader || msg['rider_id'] == selfId) return null;
        say = strings.arrived(msg['name'] as String);
        buzz = infoPattern;
      case 'low_battery': // synthesised by the app from rider_positions
        if (!isLeader || msg['rider_id'] == selfId) return null;
        say = strings.lowBattery(msg['name'] as String, (msg['battery'] as num).toInt());
        buzz = infoPattern;
      case 'trip_plan':
        final p = msg['plan'];
        if (p is! Map || isLeader) return null;
        say = strings.tripPlanned(((p['destination'] as Map?)?['label'] as String?) ?? '');
        buzz = infoPattern;
      case 'ride_ended':
        say = strings.rideEnded();
        buzz = infoPattern;
      default:
        return null;
    }
    if (settings.vibrationAlerts) await _vibrate(buzz);
    if (settings.voiceAlerts) await _speak(say, strings.ttsLanguage);
    return say;
  }

  static FlutterTts? _tts;

  static Future<void> _ttsSpeak(String text, String language) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage(language);
      await tts.speak(text);
    } catch (_) {/* no TTS engine: vibration still works */}
  }

  static Future<void> _deviceVibrate(List<int> pattern) async {
    try {
      if (await Vibration.hasVibrator()) await Vibration.vibrate(pattern: pattern);
    } catch (_) {}
  }
}

/// Quick message codes -> text (same codes as the server allows).
const Map<String, String> quickMessages = {
  'slow_down': 'Slow down',
  'speed_up': 'Speed up',
  'stop_next_fuel': 'Stop at the next fuel station',
  'regroup': 'Regroup',
  'lets_go': "Let's go",
  'stopping': 'Stopping',
  'need_fuel': 'I need fuel',
  'help': 'I need help',
  'all_good': 'All good',
  'on_my_way': 'On my way',
};

const List<String> leaderQuickCodes = ['slow_down', 'speed_up', 'stop_next_fuel', 'regroup', 'lets_go'];
const List<String> riderQuickCodes = ['stopping', 'need_fuel', 'help', 'all_good', 'on_my_way'];

String quickMessageText(String code) => quickMessages[code] ?? code;
