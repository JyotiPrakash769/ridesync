import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_plan.dart';
import '../../shared/format.dart';
import '../../shared/widgets/error_text.dart';
import '../../state/convoy_provider.dart';
import 'place_search_screen.dart';
import 'trip_progress.dart';

const int maxStops = 5;

/// Leader-only: start, destination, up to 5 stops -> route for everyone.
class TripPlannerScreen extends ConsumerStatefulWidget {
  const TripPlannerScreen({super.key, this.initial, this.nearLat, this.nearLng});

  final TripPlan? initial;
  final double? nearLat;
  final double? nearLng;

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  TripPlace? _from; // null = my location
  TripPlace? _to;
  late final List<TripPlace> _stops = [...?widget.initial?.stops];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _to = widget.initial?.destination;
    final o = widget.initial?.origin;
    _from = o == null || o.label == 'Start' ? null : o;
  }

  Future<TripPlace?> _pick(String title, {bool myLocation = false}) =>
      Navigator.of(context).push<TripPlace>(MaterialPageRoute(
        builder: (_) => PlaceSearchScreen(
          title: title,
          nearLat: widget.nearLat,
          nearLng: widget.nearLng,
          offerMyLocation: myLocation,
        ),
      ));

  Future<void> _plan() async {
    if (_to == null) {
      setState(() => _error = 'Choose a destination first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(convoyProvider.notifier).setPlan(origin: _from, destination: _to, stops: _stops);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.statusCode == 422
            ? 'Couldn\'t find a route. Wait for your GPS position or choose a start point.'
            : apiErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await ref.read(convoyProvider.notifier).setPlan();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row({
    required IconData icon,
    required String label,
    required String? value,
    required VoidCallback onTap,
    VoidCallback? onRemove,
    Key? key,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      key: key,
      minTileHeight: AppTokens.minTouch,
      leading: Icon(icon, color: scheme.primary),
      title: Text(value ?? label,
          style: value == null ? TextStyle(color: scheme.onSurfaceVariant) : null),
      subtitle: value == null ? null : Text(label),
      onTap: _busy ? null : onTap,
      trailing: onRemove == null
          ? const Icon(Icons.chevron_right)
          : IconButton(tooltip: 'Remove stop', icon: const Icon(Icons.close), onPressed: onRemove),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.initial;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan trip')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _row(
            key: const Key('fromRow'),
            icon: Icons.trip_origin,
            label: 'Start',
            value: _from?.label ?? 'My location',
            onTap: () async {
              final p = await _pick('Start from', myLocation: true);
              if (p == null) return;
              setState(() => _from = p.lat.isNaN ? null : p);
            },
          ),
          for (var i = 0; i < _stops.length; i++)
            _row(
              icon: Icons.local_gas_station,
              label: 'Stop ${i + 1}',
              value: _stops[i].label,
              onTap: () async {
                final p = await _pick('Stop ${i + 1}');
                if (p != null) setState(() => _stops[i] = p);
              },
              onRemove: () => setState(() => _stops.removeAt(i)),
            ),
          _row(
            key: const Key('toRow'),
            icon: Icons.flag,
            label: 'Destination',
            value: _to?.label,
            onTap: () async {
              final p = await _pick('Where to?');
              if (p != null) setState(() => _to = p);
            },
          ),
          if (_stops.length < maxStops)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final p = await _pick('Add a stop');
                          if (p != null) setState(() => _stops.add(p));
                        },
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Add stop (fuel, food, rest)'),
                ),
              ),
            ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                'Current plan: ${formatDistance(current.distanceM.toDouble())} · '
                '${formatDuration(current.durationS)}'
                '${current.approximate ? ' (straight-line estimate)' : ''}',
                style: text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
              ),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 0), child: InlineError(_error!)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: FilledButton.icon(
              onPressed: _busy ? null : _plan,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.route),
              label: const Text('Plan route for everyone'),
            ),
          ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear trip'),
              ),
            ),
        ],
      ),
    );
  }
}
