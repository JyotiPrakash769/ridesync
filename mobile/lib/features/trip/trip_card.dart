import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../models/trip_plan.dart';
import '../../shared/format.dart';
import 'trip_progress.dart';

/// Compact floating card at the top: destination, distance and time left,
/// next stop. Everyone sees it; tapping frames the whole route.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.plan, this.progress, required this.onTap});

  final TripPlan plan;

  /// Null until we have a GPS position.
  final TripProgress? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final p = progress;
    final dest = plan.destination.label.isEmpty ? 'Destination' : plan.destination.label;
    final String headline;
    if (p == null) {
      headline = '$dest · ${formatDistance(plan.distanceM.toDouble())} · ${formatDuration(plan.durationS)}';
    } else if (p.arrived) {
      headline = 'Arrived at $dest';
    } else {
      headline = '$dest · ${formatDistance(p.remainingM)} · ${formatDuration(p.remainingS)} left';
    }
    final details = <String>[
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
