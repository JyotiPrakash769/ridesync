import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../models/rider.dart';
import '../format.dart';

/// Colored dot + text label (never color alone).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.showLabel = true});

  final RiderStatus status;
  final bool showLabel;

  static Color colorFor(RiderStatus s) => switch (s) {
        RiderStatus.online => StatusColors.online,
        RiderStatus.weak => StatusColors.weak,
        RiderStatus.offline => StatusColors.offline,
      };

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: colorFor(status), shape: BoxShape.circle),
    );
    if (!showLabel) return Semantics(label: statusLabel(status), child: dot);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(statusLabel(status), style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
