import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/alert_card.dart';
import '../../state/convoy_state.dart';

/// Title/subtitle for the alert card; one alert vs a collapsed summary.
(String, String?) alertCopy(Map<String, DistanceAlert> alerts) {
  if (alerts.length == 1) {
    final a = alerts.values.single;
    return ('${a.name} is falling behind — ${a.distanceM} m', 'Tap to show on map');
  }
  final worst = alerts.values.reduce((a, b) => b.distanceM > a.distanceM ? b : a);
  return (
    '${alerts.length} riders falling behind',
    'Furthest: ${worst.name} — ${worst.distanceM} m · tap to show',
  );
}

/// Leader-only floating alert above the bar. Many alerts collapse into one
/// summary card; tapping centers the map on the worst offender.
class DistanceAlertBanner extends StatelessWidget {
  const DistanceAlertBanner({
    super.key,
    required this.alerts,
    required this.onShowWorst,
    required this.onDismiss,
  });

  final Map<String, DistanceAlert> alerts;
  final ValueChanged<String> onShowWorst;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    Widget child = const SizedBox.shrink(key: ValueKey('none'));
    if (alerts.isNotEmpty) {
      final (title, subtitle) = alertCopy(alerts);
      final worst = alerts.values.reduce((a, b) => b.distanceM > a.distanceM ? b : a);
      child = AlertCard(
        key: const ValueKey('alert'),
        icon: Icons.warning_amber_rounded,
        title: title,
        subtitle: subtitle,
        onTap: () => onShowWorst(worst.riderId),
        onDismiss: onDismiss,
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, alignment: Alignment.bottomCenter, child: c),
      ),
      child: child,
    );
  }
}
