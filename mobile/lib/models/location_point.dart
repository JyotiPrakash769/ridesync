/// A GPS fix that could not be sent live; queued for POST /rides/{id}/sync.
class LocationPoint {
  const LocationPoint({required this.lat, required this.lng, required this.recordedAt});

  final double lat;
  final double lng;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
      };

  static LocationPoint? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'], lng = raw['lng'], at = raw['recorded_at'];
    if (lat is! num || lng is! num || at is! String) return null;
    final t = DateTime.tryParse(at);
    if (t == null) return null;
    return LocationPoint(lat: lat.toDouble(), lng: lng.toDouble(), recordedAt: t.toUtc());
  }
}
