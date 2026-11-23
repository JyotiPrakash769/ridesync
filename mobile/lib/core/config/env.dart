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

  /// Deep-link hosts/schemes used in QR payloads.
  static const String joinLinkHost = 'ridesync.app';
  static const String joinLinkScheme = 'ridesync';
}
