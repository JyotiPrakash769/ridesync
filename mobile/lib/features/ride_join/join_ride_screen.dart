import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../../core/ride_id.dart';
import '../../shared/widgets/centered_form.dart';
import '../../shared/widgets/error_text.dart';
import '../../state/ride_session_provider.dart';
import 'qr_scanner_widget.dart';

/// Two steps: ride code (scan or type) -> display name -> join.
/// [initialRideId] prefills step 1 when opened from a deep link.
class JoinRideScreen extends ConsumerStatefulWidget {
  const JoinRideScreen({super.key, this.initialRideId});

  final String? initialRideId;

  @override
  ConsumerState<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends ConsumerState<JoinRideScreen> {
  late final TextEditingController _code;
  final _name = TextEditingController();
  String? _rideId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final pre = widget.initialRideId == null ? null : normalizeRideId(widget.initialRideId!);
    _code = TextEditingController(text: pre ?? '');
    _rideId = pre; // a valid deep link skips straight to the name step
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    final id = normalizeRideId(_code.text);
    setState(() {
      _error = id == null ? 'Ride codes are 6 letters/numbers, like K7Q2MX.' : null;
      _rideId = id;
    });
  }

  Future<void> _scan() async {
    final id = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (id == null || !mounted) return;
    setState(() {
      _code.text = id;
      _rideId = id;
      _error = null;
    });
  }

  Future<void> _join() async {
    final name = _name.text.trim();
    final rideId = _rideId!;
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name so the group knows who you are.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(rideSessionProvider.notifier).joinRide(rideId, name);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e, rideId: rideId);
        // A missing or ended ride means the code step needs redoing.
        if (e.kind == ApiErrorKind.notFound || e.kind == ApiErrorKind.gone) _rideId = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rideId = _rideId;

    if (rideId == null) {
      return CenteredForm(
        onBack: () => Navigator.of(context).pop(),
        children: [
          Text('Join a ride', style: text.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
          const SizedBox(height: 20),
          Text('or enter the ride code', style: text.labelLarge, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextField(
            key: const Key('rideCodeField'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: text.headlineSmall?.copyWith(letterSpacing: 6),
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _continue(),
            decoration: const InputDecoration(labelText: 'Ride code', counterText: ''),
          ),
          if (_error != null) ...[const SizedBox(height: 8), InlineError(_error!)],
          const SizedBox(height: 16),
          FilledButton(onPressed: _continue, child: const Text('Continue')),
        ],
      );
    }

    return CenteredForm(
      onBack: _busy ? null : () => setState(() => _rideId = null),
      children: [
        Text('Joining $rideId', style: text.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          key: const Key('displayNameField'),
          controller: _name,
          enabled: !_busy,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _join(),
          decoration:
              const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person)),
        ),
        if (_error != null) ...[const SizedBox(height: 8), InlineError(_error!)],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Join ride'),
        ),
      ],
    );
  }
}
