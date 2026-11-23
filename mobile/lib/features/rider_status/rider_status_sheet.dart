import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../models/rider.dart';
import '../../shared/format.dart';
import '../../shared/widgets/status_dot.dart';

/// Ticks once a second so "Updated 12s ago" stays current.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now().toUtc()),
);

/// Content of the draggable status sheet: one row per rider.
class RiderStatusSheet extends ConsumerWidget {
  const RiderStatusSheet({
    super.key,
    required this.riders,
    required this.scrollController,
    required this.selfId,
    required this.onRiderTap,
    required this.footer,
  });

  final List<Rider> riders;
  final ScrollController scrollController;
  final String selfId;
  final ValueChanged<Rider> onRiderTap;
  final Widget footer;

  static int _order(Rider r) => r.isLeader ? 0 : 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now().toUtc();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sorted = [...riders]
      ..sort((a, b) => _order(a) != _order(b)
          ? _order(a) - _order(b)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('Riders', style: text.titleLarge),
        ),
        for (final r in sorted)
          ListTile(
            minTileHeight: AppTokens.minTouch,
            onTap: r.hasPosition ? () => onRiderTap(r) : null,
            leading: Icon(
              r.isLeader ? Icons.star : Icons.two_wheeler,
              color: r.isLeader ? scheme.primary : scheme.onSurfaceVariant,
            ),
            title: Row(
              children: [
                Flexible(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                if (r.id == selfId)
                  Text('  (you)', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                if (r.isLeader) ...[
                  const SizedBox(width: 8),
                  Text('Leader', style: text.labelSmall?.copyWith(color: scheme.primary)),
                ],
              ],
            ),
            subtitle: Text(
              lastUpdateLabel(r, now),
              style: text.bodySmall?.copyWith(fontFeatures: tabularFigures),
            ),
            trailing: StatusDot(status: r.status),
          ),
        const Divider(height: 32),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: footer),
      ],
    );
  }
}
