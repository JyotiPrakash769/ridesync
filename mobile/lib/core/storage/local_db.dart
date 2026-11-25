import 'package:hive_flutter/hive_flutter.dart';

import '../../state/ride_session.dart';

/// Hive boxes. Plain maps only (no type adapters / codegen).
abstract final class LocalDb {
  static const String sessionBox = 'session';
  static const String locationQueueBox = 'location_queue';
  static const String settingsBox = 'settings';
  static const String savedTripsBox = 'saved_trips';

  static Future<void> init() async {
    await Hive.initFlutter('ridesync');
    await Hive.openBox<dynamic>(sessionBox);
    await Hive.openBox<dynamic>(locationQueueBox);
    await Hive.openBox<dynamic>(settingsBox);
    await Hive.openBox<dynamic>(savedTripsBox);
  }
}

/// Persists the current ride so a restart or backgrounding restores it.
class SessionStore {
  SessionStore(this._box);

  final Box<dynamic> _box;
  static const String _key = 'current';

  RideSession? load() {
    final raw = _box.get(_key);
    if (raw is! Map) return null;
    return RideSession.fromMap(raw.cast<String, dynamic>());
  }

  Future<void> save(RideSession s) => _box.put(_key, s.toMap());

  Future<void> clear() => _box.delete(_key);
}
