import 'package:material_ui/material_ui.dart';

import '../../shared/format.dart';
import '../../shared/geo.dart';
import '../../shared/widgets/alert_card.dart';
import '../../state/convoy_state.dart';

const List<String> regroupPresets = ['Fuel station', 'Food stop', 'Rest stop', 'Photo stop'];

/// Asks the leader for a short label. Returns null if cancelled.
Future<String?> showRegroupDialog(BuildContext context) {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.flag_circle),
      title: const Text('Set regroup point'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: ctl,
            maxLength: 40,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Where? (optional)'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in regroupPresets)
                ActionChip(label: Text(p), onPressed: () => Navigator.pop(context, p)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctl.text.trim()),
          child: const Text('Set for everyone'),
        ),
      ],
    ),
  );
}

/// Floating card shown to everyone while a regroup point is set.
class RegroupCard extends StatelessWidget {
  const RegroupCard({
    super.key,
    required this.point,
    required this.myLat,
    required this.myLng,
    required this.onTap,
    this.onClear,
  });

  final RegroupPoint point;
  final double? myLat;
  final double? myLng;
  final VoidCallback onTap;

  /// Leader only.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final away = myLat == null || myLng == null
        ? null
        : formatDistance(haversineM(myLat!, myLng!, point.lat, point.lng));
    return AlertCard(
      tone: AlertTone.tertiary,
      icon: Icons.flag_circle,
      title: point.label.isEmpty ? 'Regroup point' : 'Regroup: ${point.label}',
      subtitle: [if (away != null) '$away away', 'tap to show'].join(' · '),
      onTap: onTap,
      onDismiss: onClear,
    );
  }
}
