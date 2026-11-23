import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../../shared/widgets/centered_form.dart';
import '../../shared/widgets/error_text.dart';
import '../../state/ride_session_provider.dart';

/// Phase 1 stand-in for the convoy map (Phase 2): confirms the restored
/// session and lets the leader end / a member leave the ride.
class ConvoyMapScreen extends ConsumerStatefulWidget {
  const ConvoyMapScreen({super.key});

  @override
  ConsumerState<ConvoyMapScreen> createState() => _ConvoyMapScreenState();
}

class _ConvoyMapScreenState extends ConsumerState<ConvoyMapScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _endOrLeave() async {
    final session = ref.read(rideSessionProvider)!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (session.isLeader) {
        await ref.read(apiClientProvider).endRide(session.rideId, session.riderId);
      }
      await ref.read(rideSessionProvider.notifier).clear();
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.gone || e.kind == ApiErrorKind.notFound) {
        await ref.read(rideSessionProvider.notifier).clear();
        return;
      }
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(rideSessionProvider);
    if (session == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return CenteredForm(
      children: [
        Text('Ride ${session.rideId}', style: text.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          '${session.displayName} · ${session.isLeader ? 'Leader' : 'Rider'}',
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
        if (_error != null) ...[const SizedBox(height: 16), InlineError(_error!)],
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: _busy ? null : _endOrLeave,
          child: Text(session.isLeader ? 'End ride for everyone' : 'Leave ride'),
        ),
      ],
    );
  }
}
