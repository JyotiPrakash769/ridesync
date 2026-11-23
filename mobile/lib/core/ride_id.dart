import 'config/env.dart';

/// Ride IDs: 6 chars of base32 (A-Z, 2-7) minus O, I, L. Must match the
/// backend's RIDE_ID_ALPHABET.
const String rideIdAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ234567';
const int rideIdLength = 6;

final RegExp _rideIdRe = RegExp('^[$rideIdAlphabet]{$rideIdLength}\$');

/// Uppercases and strips spaces/dashes. Returns null if not a valid ride ID.
String? normalizeRideId(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return _rideIdRe.hasMatch(s) ? s : null;
}

/// Accepts a QR/deep-link payload or a bare ride ID:
///   `https://<join host>/join/ABC234`, `ridesync://join/ABC234`, `ABC234`
String? parseRideIdFromLink(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.scheme == 'https' && Env.joinLinkHosts.contains(uri.host)) {
      if (segs.length == 2 && segs[0] == 'join') return normalizeRideId(segs[1]);
      return null;
    }
    if (uri.scheme == Env.joinLinkScheme && uri.host == 'join') {
      // ridesync://join/ABC234 -> host "join", path "/ABC234"
      if (segs.length == 1) return normalizeRideId(segs[0]);
      return null;
    }
    return null;
  }
  return normalizeRideId(text);
}
