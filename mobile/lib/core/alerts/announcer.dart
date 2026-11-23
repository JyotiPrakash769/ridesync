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
