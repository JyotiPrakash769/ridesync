import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/trip_plan.dart';
import 'local_db.dart';

/// A trip saved on this phone for reuse ("Bhubaneswar -> Puri").
class SavedTrip {
  const SavedTrip({required this.name, this.origin, required this.destination, this.stops = const []});

  final String name;
  final TripPlace? origin; // null = my location
  final TripPlace destination;
  final List<TripPlace> stops;

  Map<String, dynamic> toMap() => {
        'name': name,
        'origin': origin?.toJson(),
        'destination': destination.toJson(),
        'stops': [for (final s in stops) s.toJson()],
      };

  static SavedTrip? fromMap(Object? raw) {
    if (raw is! Map || raw['destination'] is! Map) return null;
    TripPlace p(Object m) => TripPlace.fromJson((m as Map).cast<String, dynamic>());
    return SavedTrip(
      name: (raw['name'] as String?) ?? '',
      origin: raw['origin'] is Map ? p(raw['origin'] as Object) : null,
      destination: p(raw['destination'] as Object),
      stops: [for (final s in (raw['stops'] as List? ?? const [])) p(s as Object)],
    );
  }
}

/// Device-only storage (no accounts): Hive box `saved_trips`.
class SavedTripsStore {
  SavedTripsStore(this._box);

  final Box<dynamic> _box;
  static const int max = 20;

  List<(dynamic, SavedTrip)> all() => [
        for (final k in _box.keys.toList().reversed)
          if (SavedTrip.fromMap(_box.get(k)) case final t?) (k, t),
      ];

  Future<void> save(SavedTrip t) async {
    await _box.add(t.toMap());
    while (_box.length > max) {
      await _box.delete(_box.keys.first);
    }
  }

  Future<void> remove(dynamic key) => _box.delete(key);
}

final savedTripsStoreProvider = Provider<SavedTripsStore>(
  (ref) => SavedTripsStore(Hive.box<dynamic>(LocalDb.savedTripsBox)),
);
