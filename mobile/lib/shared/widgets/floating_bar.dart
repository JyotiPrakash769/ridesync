import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

/// Pill-shaped M3 surface floating above the bottom safe area.
/// [thresholdChip] is passed only for the leader; members never see it.
class FloatingBar extends StatelessWidget {
  const FloatingBar({
    super.key,
    required this.riderCount,
    required this.onToggleStatus,
    required this.onRecenter,
    this.statusOpen = false,
    this.thresholdChip,
    this.onPlanTrip,
  });

  /// Leader only: opens the trip planner.
  final VoidCallback? onPlanTrip;

  final int riderCount;
  final VoidCallback onToggleStatus;
  final VoidCallback onRecenter;
  final bool statusOpen;
  final Widget? thresholdChip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: AppTokens.barElevation,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: AppTokens.minTouch + 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Semantics(
                label: '$riderCount riders in this ride',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(Icons.group, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        '$riderCount',
                        style: text.titleMedium?.copyWith(fontFeatures: tabularFigures),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (thresholdChip != null) ...[thresholdChip!, const SizedBox(width: 4)],
              if (onPlanTrip != null)
                IconButton(
                  tooltip: 'Plan trip',
                  onPressed: onPlanTrip,
                  icon: const Icon(Icons.route),
                ),
              IconButton(
                tooltip: 'Center on group',
                onPressed: onRecenter,
                icon: const Icon(Icons.center_focus_strong),
              ),
              IconButton(
                tooltip: statusOpen ? 'Hide rider status' : 'Show rider status',
                isSelected: statusOpen,
                onPressed: onToggleStatus,
                icon: const Icon(Icons.format_list_bulleted),
                selectedIcon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
