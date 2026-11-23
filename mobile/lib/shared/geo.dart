import 'dart:math';

const double earthRadiusM = 6371000;

/// Great-circle distance in meters (matches the backend's haversine_m).
double haversineM(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * pi / 180;
  final dp = rad(lat2 - lat1);
  final dl = rad(lng2 - lng1);
  final a = pow(sin(dp / 2), 2) + cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dl / 2), 2);
  return 2 * earthRadiusM * asin(min(1.0, sqrt(a)));
}

/// Initial compass bearing from point 1 to point 2, degrees clockwise from north.
double bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * pi / 180;
  final p1 = rad(lat1), p2 = rad(lat2), dl = rad(lng2 - lng1);
  final y = sin(dl) * cos(p2);
  final x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}
