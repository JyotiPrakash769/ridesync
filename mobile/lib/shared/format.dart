import '../models/rider.dart';

/// "just now", "12s ago", "4m ago", "2h ago".
String formatAgo(DateTime? t, DateTime now) {
  if (t == null) return 'never';
  final d = now.difference(t);
  if (d.inSeconds < 3) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  return '${d.inHours}h ago';
}

/// Status-sheet subtitle. Offline riders read "Last seen Xm ago".
String lastUpdateLabel(Rider r, DateTime now) {
  if (r.lastSeenAt == null) return 'Waiting for first update';
  final ago = formatAgo(r.lastSeenAt, now);
  return r.status == RiderStatus.offline ? 'Last seen $ago' : 'Updated $ago';
}

String statusLabel(RiderStatus s) => switch (s) {
      RiderStatus.online => 'Online',
      RiderStatus.weak => 'Weak signal',
      RiderStatus.offline => 'Offline',
    };
