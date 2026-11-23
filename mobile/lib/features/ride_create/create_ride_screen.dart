import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../../shared/widgets/centered_form.dart';
import '../../shared/widgets/error_text.dart';
import '../../state/ride_session.dart';
import '../../state/ride_session_provider.dart';
import 'qr_display_widget.dart';

class CreateRideScreen extends ConsumerStatefulWidget {
  const CreateRideScreen({super.key});

  @override
  ConsumerState<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends ConsumerState<CreateRideScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  RideSession? _created;
  String? _payload;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name so riders know who\'s leading.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Persisting happens before the QR shows, so a restart restores the ride.
      final api = ref.read(apiClientProvider);
      final created = await api.createRide(name);
      final session = await ref.read(rideSessionProvider.notifier).adopt(
            rideId: created.rideId,
            riderId: created.leaderRiderId,
            riderToken: created.riderToken,
            leader: true,
            displayName: name,
            activate: false,
          );
      setState(() {
        _created = session;
        _payload = created.qrPayload;
      });
    } on ApiException catch (e) {
      setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final created = _created;
    if (created != null) {
      return CenteredForm(
        children: [
          Text('Your ride is ready', style: text.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Riders scan this code or type the ride code to join.',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          QrDisplayWidget(rideId: created.rideId, payload: _payload!),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              ref.read(rideSessionProvider.notifier).activate();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start ride'),
          ),
        ],
      );
    }
    return CenteredForm(
      onBack: _busy ? null : () => Navigator.of(context).pop(),
      children: [
        Text('Create a ride', style: text.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          enabled: !_busy,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _create(),
          decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person)),
        ),
        if (_error != null) ...[const SizedBox(height: 8), InlineError(_error!)],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create ride'),
        ),
      ],
    );
  }
}
