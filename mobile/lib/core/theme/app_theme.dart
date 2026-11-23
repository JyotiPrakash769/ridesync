import 'package:material_ui/material_ui.dart';

/// Brand seed. Every UI color comes from the ColorScheme generated from this
/// seed; widgets must use Theme.of(context).colorScheme.* rather than hex.
const Color _seed = Color(0xFFFFC72C);

/// Shape/size tokens shared by the floating chrome.
abstract final class AppTokens {
  /// Minimum touch target: one-handed use on a handlebar mount.
  static const double minTouch = 56;
  static const double barRadius = 28;
  static const double barElevation = 3;
  static const double sideMargin = 16;
  static const double gap = 12;
}

/// Fixed semantic status colors. The only hex allowed in widgets besides the
/// map style. Always pair with a text label or icon, never color alone.
abstract final class StatusColors {
  static const Color online = Color(0xFF5DCAA5);
  static const Color weak = Color(0xFFEF9F27);
  static const Color offline = Color(0xFFE24B4A);
}

/// Tabular figures so distances, speeds and timers don't jitter.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

abstract final class AppTheme {
  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    const minSize = Size(AppTokens.minTouch, AppTokens.minTouch);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: minSize),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: minSize),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: minSize),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: minSize),
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}
