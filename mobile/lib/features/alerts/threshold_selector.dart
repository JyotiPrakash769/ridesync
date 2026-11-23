import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

const List<int> thresholdOptionsM = [100, 300, 500, 1000];

/// Leader-only chip in the floating bar showing the current threshold.
class ThresholdChip extends StatelessWidget {
  const ThresholdChip({super.key, required this.thresholdM, required this.onChanged});

  final int thresholdM;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: 'Falling-behind distance',
      child: ActionChip(
        avatar: const Icon(Icons.social_distance, size: 18),
        label: Text('$thresholdM m', style: text.labelLarge?.copyWith(fontFeatures: tabularFigures)),
        shape: const StadiumBorder(),
        onPressed: () async {
          final picked = await showModalBottomSheet<int>(
            context: context,
            showDragHandle: true,
            builder: (_) => _ThresholdSheet(current: thresholdM),
          );
          if (picked != null && picked != thresholdM) onChanged(picked);
        },
      ),
    );
  }
}

class _ThresholdSheet extends StatelessWidget {
  const _ThresholdSheet({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Alert when a rider is more than', style: text.titleMedium),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final m in thresholdOptionsM)
                  ButtonSegment(
                    value: m,
                    label: Text('$m m', style: const TextStyle(fontFeatures: tabularFigures)),
                  ),
              ],
              selected: {current},
              style: SegmentedButton.styleFrom(minimumSize: const Size(0, AppTokens.minTouch)),
              onSelectionChanged: (s) => Navigator.of(context).pop(s.single),
            ),
            const SizedBox(height: 8),
            Text('behind you.', style: text.titleMedium),
          ],
        ),
      ),
    );
  }
}
