import 'package:hive/hive.dart';

import '../../models/location_point.dart';

/// Persistent FIFO of unsent points (Hive box `location_queue`).
/// Keys are Hive's auto-increment ints, so insertion order is preserved.
class LocationQueue {
  LocationQueue(this._box, {this.maxPoints = 10000});

  final Box<dynamic> _box;

  /// Oldest points are dropped beyond this (~11h at one point per 4s).
  final int maxPoints;

  int get length => _box.length;
  bool get isEmpty => _box.isEmpty;

  Future<void> enqueue(LocationPoint p) async {
    await _box.add(p.toJson());
    final overflow = _box.length - maxPoints;
    if (overflow > 0) await _box.deleteAll(_box.keys.take(overflow).toList());
  }

  /// Oldest-first batch with the Hive keys needed to remove exactly these.
  (List<dynamic> keys, List<LocationPoint> points) peek(int max) {
    final keys = <dynamic>[];
    final points = <LocationPoint>[];
    for (final k in _box.keys) {
      if (points.length >= max) break;
      final p = LocationPoint.fromMap(_box.get(k));
      keys.add(k);
      if (p != null) points.add(p);
    }
    return (keys, points);
  }

  Future<void> remove(List<dynamic> keys) => _box.deleteAll(keys);

  Future<void> clear() => _box.clear();
}
