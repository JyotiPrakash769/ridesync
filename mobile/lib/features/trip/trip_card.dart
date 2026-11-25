import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trip_plan.dart';
import '../../shared/format.dart';
import 'trip_assist.dart';
import 'trip_progress.dart';

/// Compact floating card at the top: destination, distance/time left,
/// arrival clock, next stop, weather warning. Everyone sees it; tapping
/// frames the route. Navigate hands the next stop to Google Maps.
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.plan,
    this.progress,
    required this.onTap,
    this.onNavigate,
    this.onEdit,
    this.weatherWarning,
    this.now,
  });

  final TripPlan plan;

  /// Null until we have a GPS position.
  final TripProgress? progress;
  final VoidCallback onTap;
  final VoidCallback? onNavigate;

  /// Leader only.
  final VoidCallback? onEdit;
  final String? weatherWarning;

  /// Clock override for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = this.now ?? DateTime.now().toUtc();
    final p = progress;
    final dest = plan.destination.label.isEmpty ? 'Destination' : plan.destination.label;
    final dep = plan.departureAt;
    final beforeDeparture = dep != null && dep.isAfter(now);

    final String headline;
    if (beforeDeparture) {
      headline = '$dest · leave ${formatClock(dep)} · arrive ~'
          '${formatClock(arrivalTime(plan, now: now))}';
    } else if (p == null) {
      headline = '$dest · ${formatDistance(plan.distanceM.toDouble())} · ${formatDuration(plan.durationS)}';
    } else if (p.arrived) {
      headline = 'Arrived at $dest';
    } else {
      headline = '$dest · ${formatDistance(p.remainingM)} · '
          'arrive ~${formatClock(arrivalTime(plan, now: now, remainingS: p.remainingS))}';
    }
    final details = <String>[
      if (!beforeDeparture && p != null && !p.arrived) '${formatDuration(p.remainingS)} left',
      if (p?.nextStop != null)
        'Next: ${p!.nextStop!.label.isEmpty ? 'stop' : p.nextStop!.label} in ${formatDistance(p.nextStopM!)}',
      if (plan.approximate) 'straight-line estimate',
    ];
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: AppTokens.barElevation,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.route, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(fontFeatures: tabularFigures)),
                    if (details.isNotEmpty)
                      Text(details.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant, fontFeatures: tabularFigures)),
                    if (weatherWarning != null)
                      Row(
                        children: [
                          Icon(Icons.thunderstorm, size: 14, color: scheme.error),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(weatherWarning!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: scheme.error)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (onNavigate != null)
                IconButton(
                  tooltip: 'Navigate with Google Maps',
                  icon: const Icon(Icons.navigation),
                  onPressed: onNavigate,
                ),
              if (onEdit != null)
                IconButton(tooltip: 'Edit trip', icon: const Icon(Icons.edit), onPressed: onEdit),
            ],
          ),
        ),
      ),
    );
  }
}
