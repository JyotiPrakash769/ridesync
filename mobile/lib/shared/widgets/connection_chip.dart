import 'package:material_ui/material_ui.dart';

import '../../core/network/ws_client.dart';

/// Small floating chip at the top: a subtle "Reconnecting…" (not an error).
/// Hidden while connected.
class ConnectionChip extends StatelessWidget {
  const ConnectionChip({super.key, required this.state});

  final WsConnState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (state) {
      WsConnState.connected => null,
      WsConnState.connecting => 'Connecting…',
      WsConnState.reconnecting => 'Reconnecting…',
      WsConnState.closed => 'Offline',
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: label == null
          ? const SizedBox.shrink()
          : Material(
              key: ValueKey(label),
              color: scheme.surfaceContainerHigh,
              elevation: 3,
              shape: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
            ),
    );
  }
}
