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
