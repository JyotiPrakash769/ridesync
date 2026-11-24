/// Google encoded polyline codec (same as the backend's route_geometry.py).
List<(double, double)> decodePolyline(String encoded, {int precision = 5}) {
  final factor = _pow10(precision);
  final out = <(double, double)>[];
  var i = 0, lat = 0, lng = 0;
  while (i < encoded.length) {
    for (var axis = 0; axis < 2; axis++) {
      var shift = 0, result = 0, b = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final delta = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      if (axis == 0) {
        lat += delta;
      } else {
        lng += delta;
      }
    }
    out.add((lat / factor, lng / factor));
  }
  return out;
}

String encodePolyline(List<(double, double)> points, {int precision = 5}) {
  final factor = _pow10(precision);
  final buf = StringBuffer();
  var pLat = 0, pLng = 0;
  for (final (lat, lng) in points) {
    final iLat = (lat * factor).round(), iLng = (lng * factor).round();
    for (final d in [iLat - pLat, iLng - pLng]) {
      var v = d < 0 ? ~(d << 1) : d << 1;
      while (v >= 0x20) {
        buf.writeCharCode((0x20 | (v & 0x1F)) + 63);
        v >>= 5;
      }
      buf.writeCharCode(v + 63);
    }
    pLat = iLat;
    pLng = iLng;
  }
  return buf.toString();
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
