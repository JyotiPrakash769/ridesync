/// Leader-set meeting point ("regroup at the fuel station").
class RegroupPoint {
  const RegroupPoint({required this.lat, required this.lng, required this.label, this.setAt});

  final double lat;
  final double lng;
  final String label;
  final DateTime? setAt;

  static RegroupPoint? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'];
    if (lat is! num || lng is! num) return null;
    return RegroupPoint(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: (j['label'] as String?) ?? '',
      setAt: j['set_at'] is String ? DateTime.tryParse(j['set_at'] as String)?.toUtc() : null,
    );
  }
}
