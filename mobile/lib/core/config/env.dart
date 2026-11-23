/// Backend endpoints. Override at build time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000 \
///               --dart-define=WS_BASE_URL=ws://192.168.1.20:8000
/// Defaults target the Android emulator's alias for the host machine.
/// The Google Maps key is not here: it lives in android/local.properties
/// (MAPS_API_KEY), see README.
class Env {
  const Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'ws://10.0.2.2:8000',
  );

  /// Map provider: 'osm' (default, OpenStreetMap data, no API key) or
  /// 'google' (needs MAPS_API_KEY). Build with
  ///   --dart-define=MAP_PROVIDER=google
  static const String mapProvider = String.fromEnvironment('MAP_PROVIDER', defaultValue: 'osm');

  /// https host of QR join links (`https://<host>/join/CODE`). Defaults to the
  /// API host, which serves the /join landing page. Must match the
  /// JOIN_HOST manifest placeholder for links to open the app directly.
  static const String _joinHostOverride = String.fromEnvironment('JOIN_HOST');
  static String get joinLinkHost =>
      _joinHostOverride.isNotEmpty ? _joinHostOverride : Uri.parse(apiBaseUrl).host;

  /// Hosts accepted for join links: the configured one plus the original.
  static Set<String> get joinLinkHosts => {joinLinkHost, 'ridesync.app'};
  static const String joinLinkScheme = 'ridesync';

  /// Privacy policy page served by the backend.
  static String get privacyUrl => '$apiBaseUrl/privacy';

  /// Optional Sentry DSN for crash reports (empty = disabled).
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');
}
