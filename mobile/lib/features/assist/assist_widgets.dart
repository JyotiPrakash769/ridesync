import 'package:material_ui/material_ui.dart';

import '../../core/alerts/announcer.dart';
import '../../core/theme/app_theme.dart';
import '../../models/rider.dart';
import '../../shared/format.dart';
import '../../state/convoy_state.dart';
import 'assist_logic.dart';

/// Leader-only strip under the trip card: spread, last rider, sweep gap,
/// arrivals at the destination.
class LeaderAssistCard extends StatelessWidget {
  const LeaderAssistCard({
    super.key,
    required this.spread,
    required this.riders,
    required this.thresholdM,
    this.sweepId,
    this.arrived = const {},
    this.hasPlan = false,
    this.onTapLast,
  });

  final GroupSpread spread;
  final Map<String, Rider> riders;
  final int thresholdM;
  final String? sweepId;
  final Set<String> arrived;
  final bool hasPlan;
  final VoidCallback? onTapLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final together = spread.together(thresholdM);
    final last = spread.lastRiderId == null ? null : riders[spread.lastRiderId];
    final members = riders.values.where((r) => !r.isLeader).toList();
    final waiting = members.where((r) => !arrived.contains(r.id)).map((r) => r.name).toList();
    final parts = <String>[
      together ? 'Group together' : 'Spread ${formatDistance(spread.spreadM)}',
      if (!together && last != null) 'last: ${last.name}',
      if (spread.sweepGapM != null) 'sweep ${formatDistance(spread.sweepGapM!)} back',
      if (hasPlan && arrived.isNotEmpty)
        waiting.isEmpty
            ? 'everyone arrived'
            : 'arrived ${members.length - waiting.length}/${members.length}, waiting: ${waiting.take(2).join(', ')}'
                '${waiting.length > 2 ? '…' : ''}',
    ];
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
      elevation: 1,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTapLast,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(together ? Icons.groups : Icons.social_distance,
                  size: 18, color: together ? scheme.primary : scheme.error),
              const SizedBox(width: 8),
              Flexible(
                child: Text(parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(fontFeatures: tabularFigures)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid of one-tap messages. Returns the chosen code.
Future<String?> showQuickMessageSheet(BuildContext context, {required bool isLeader}) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // big text (handlebar mode) must not overflow
      builder: (context) {
        final codes = [if (isLeader) ...leaderQuickCodes, ...riderQuickCodes];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Send to everyone', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in codes)
                      ActionChip(
                        avatar: Icon(_icon(c), size: 18),
                        label: Text(quickMessageText(c)),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        onPressed: () => Navigator.pop(context, c),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

IconData _icon(String code) => switch (code) {
      'slow_down' => Icons.speed,
      'speed_up' => Icons.fast_forward,
      'stop_next_fuel' || 'need_fuel' => Icons.local_gas_station,
      'regroup' => Icons.groups,
      'lets_go' => Icons.play_arrow,
      'stopping' => Icons.pan_tool,
      'help' => Icons.sos,
      'all_good' => Icons.thumb_up,
      _ => Icons.chat_bubble_outline,
    };

/// Incoming quick message, shown briefly at the top.
class QuickMessageCard extends StatelessWidget {
  const QuickMessageCard({super.key, required this.msg});

  final QuickMsg msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = msg.code == 'help';
    return Material(
      color: urgent ? scheme.errorContainer : scheme.primaryContainer,
      elevation: AppTokens.barElevation,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(msg.code),
                color: urgent ? scheme.onErrorContainer : scheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${msg.fromLeader ? 'Leader' : msg.name}: ${quickMessageText(msg.code)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: urgent ? scheme.onErrorContainer : scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
