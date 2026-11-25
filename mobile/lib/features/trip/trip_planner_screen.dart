import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/saved_trips.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_plan.dart';
import '../../shared/format.dart';
import '../../shared/widgets/error_text.dart';
import '../../state/convoy_provider.dart';
import '../../state/ride_session_provider.dart';
import 'place_search_screen.dart';
import 'trip_assist.dart';
import 'trip_progress.dart';

const int maxStops = 5;
const List<int?> fuelRangeChoices = [null, 120, 180, 250, 350];

/// Leader-only: start, destination, up to 5 stops, route options, departure,
/// fuel range -> route for everyone.
class TripPlannerScreen extends ConsumerStatefulWidget {
  const TripPlannerScreen({
    super.key,
    this.initial,
    this.nearLat,
    this.nearLng,
    this.addStop,
    this.setDestination,
  });

  final TripPlan? initial;
  final double? nearLat;
  final double? nearLng;

  /// Opened from "pick on map": prefill a new stop / destination.
  final TripPlace? addStop;
  final TripPlace? setDestination;

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  TripPlace? _from; // null = my location
  TripPlace? _to;
  late final List<TripPlace> _stops = [...?widget.initial?.stops];
  bool _avoidTolls = false;
  bool _avoidHighways = false;
  bool _optimize = false;
  DateTime? _departure;
  int? _fuelRangeKm;
  List<RouteOption>? _options;
  int _selected = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _to = widget.setDestination ?? p?.destination;
    final o = p?.origin;
    _from = o == null || o.label == 'Start' ? null : o;
    _avoidTolls = p?.avoidTolls ?? false;
    _avoidHighways = p?.avoidHighways ?? false;
    _fuelRangeKm = p?.fuelRangeKm;
    final dep = p?.departureAt;
    _departure = dep != null && dep.isAfter(DateTime.now()) ? dep : null;
    if (widget.addStop != null && _stops.length < maxStops) _stops.add(widget.addStop!);
  }

  PlanOptions get _planOptions => PlanOptions(
        avoidTolls: _avoidTolls,
        avoidHighways: _avoidHighways,
        optimizeStops: _optimize && _stops.length > 1,
        alternative: _options == null ? 0 : _selected,
        departureAt: _departure,
        fuelRangeKm: _fuelRangeKm,
      );

  void _changed(VoidCallback f) => setState(() {
        f();
        _options = null; // route options are stale now
        _selected = 0;
      });

  Future<TripPlace?> _pick(String title, {bool myLocation = false}) =>
      Navigator.of(context).push<TripPlace>(MaterialPageRoute(
        builder: (_) => PlaceSearchScreen(
          title: title,
          nearLat: widget.nearLat,
          nearLng: widget.nearLng,
          offerMyLocation: myLocation,
        ),
      ));

  Future<void> _run(Future<void> Function() f, {String? on422}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.statusCode == 422 && on422 != null ? on422 : apiErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _noOrigin =
      'Couldn\'t plan: wait for your GPS position or choose a start point (or check the departure time).';

  Future<void> _compare() async {
    final to = _to;
    if (to == null) return setState(() => _error = 'Choose a destination first.');
    final s = ref.read(rideSessionProvider)!;
    await _run(() async {
      final opts = await ref.read(apiClientProvider).previewPlan(s.rideId, s.auth,
          origin: _from, destination: to, stops: _stops, options: _planOptions);
      if (mounted) {
        setState(() {
          _options = opts;
          _selected = 0;
        });
      }
    }, on422: _noOrigin);
  }

  Future<void> _plan() async {
    final to = _to;
    if (to == null) return setState(() => _error = 'Choose a destination first.');
    await _run(() async {
      await ref.read(convoyProvider.notifier).setPlanWithOptions(
          origin: _from, destination: to, stops: _stops, options: _planOptions);
      if (mounted) Navigator.pop(context);
    }, on422: _noOrigin);
  }

  Future<void> _clear() => _run(() async {
        await ref.read(convoyProvider.notifier).setPlan();
        if (mounted) Navigator.pop(context);
      });

  Future<void> _save() async {
    final to = _to;
    if (to == null) return setState(() => _error = 'Choose a destination first.');
    final ctl = TextEditingController(
        text: '${_from?.label ?? 'My location'} → ${to.label.isEmpty ? 'Destination' : to.label}');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save trip'),
        content: TextField(controller: ctl, maxLength: 60, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref
        .read(savedTripsStoreProvider)
        .save(SavedTrip(name: name, origin: _from, destination: to, stops: List.of(_stops)));
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name"')));
    }
  }

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 7)),
      initialDate: _departure ?? now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final dep = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    _changed(() => _departure = dep.isAfter(now) ? dep : null);
  }

  Widget _place({
    required IconData icon,
    required String label,
    required String? value,
    required VoidCallback onTap,
    Widget? trailing,
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
      trailing: trailing ?? const Icon(Icons.chevron_right),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  @override
  Widget build(BuildContext context) {
    final current = widget.initial;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = ref.watch(savedTripsStoreProvider).all();
    final weather = ref.watch(convoyProvider.select((s) => s.weather));
    final long = current == null ? const <int>[] : longLegs(current);
    final fuel = current == null ? const <int>[] : fuelGaps(current, _fuelRangeKm);

    return Scaffold(
      appBar: AppBar(title: const Text('Plan trip')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (saved.isNotEmpty) ...[
            _section('Saved trips'),
            SizedBox(
              height: AppTokens.minTouch,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final (key, t) in saved)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        avatar: const Icon(Icons.bookmark, size: 18),
                        label: Text(t.name),
                        onPressed: () => _changed(() {
                          _from = t.origin;
                          _to = t.destination;
                          _stops
                            ..clear()
                            ..addAll(t.stops);
                        }),
                        onDeleted: () async {
                          await ref.read(savedTripsStoreProvider).remove(key);
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
          _section('Route'),
          _place(
            key: const Key('fromRow'),
            icon: Icons.trip_origin,
            label: 'Start',
            value: _from?.label ?? 'My location',
            onTap: () async {
              final p = await _pick('Start from', myLocation: true);
              if (p != null) _changed(() => _from = p.lat.isNaN ? null : p);
            },
          ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (a, b) => _changed(() {
              final s = _stops.removeAt(a);
              _stops.insert(b, s);
            }),
            children: [
              for (var i = 0; i < _stops.length; i++)
                _place(
                  key: ValueKey('stop$i${_stops[i].lat}${_stops[i].lng}'),
                  icon: Icons.local_gas_station,
                  label: 'Stop ${i + 1}',
                  value: _stops[i].label.isEmpty ? 'Map point' : _stops[i].label,
                  onTap: () async {
                    final p = await _pick('Stop ${i + 1}');
                    if (p != null) _changed(() => _stops[i] = p);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Remove stop',
                        icon: const Icon(Icons.close),
                        onPressed: () => _changed(() => _stops.removeAt(i)),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          _place(
            key: const Key('toRow'),
            icon: Icons.flag,
            label: 'Destination',
            value: _to?.label,
            onTap: () async {
              final p = await _pick('Where to?');
              if (p != null) _changed(() => _to = p);
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
                          if (p != null) _changed(() => _stops.add(p));
                        },
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Add stop (fuel, food, rest)'),
                ),
              ),
            ),
          _section('Options'),
          SwitchListTile(
            secondary: const Icon(Icons.toll),
            title: const Text('Avoid tolls'),
            value: _avoidTolls,
            onChanged: (v) => _changed(() => _avoidTolls = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.add_road),
            title: const Text('Avoid highways'),
            value: _avoidHighways,
            onChanged: (v) => _changed(() => _avoidHighways = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.swap_vert),
            title: const Text('Best order for stops'),
            subtitle: const Text('Reorder stops to ride the shortest way'),
            value: _optimize && _stops.length > 1,
            onChanged: _stops.length > 1 ? (v) => _changed(() => _optimize = v) : null,
          ),
          ListTile(
            minTileHeight: AppTokens.minTouch,
            leading: const Icon(Icons.schedule),
            title: Text(_departure == null
                ? 'Leave now'
                : 'Leave ${MaterialLocalizations.of(context).formatShortMonthDay(_departure!)}, '
                    '${formatClock(_departure!)}'),
            subtitle: const Text('Plan ahead (up to 7 days); friends can join early'),
            onTap: _pickDeparture,
            trailing: _departure == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: 'Leave now',
                    icon: const Icon(Icons.close),
                    onPressed: () => _changed(() => _departure = null),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(Icons.local_gas_station),
                Text('Fuel range', style: text.bodyMedium),
                for (final r in fuelRangeChoices)
                  ChoiceChip(
                    label: Text(r == null ? 'Off' : '$r km',
                        style: const TextStyle(fontFeatures: tabularFigures)),
                    selected: _fuelRangeKm == r,
                    onSelected: (_) => setState(() => _fuelRangeKm = r),
                  ),
              ],
            ),
          ),
          if (current != null && (long.isNotEmpty || fuel.isNotEmpty || weather.isNotEmpty)) ...[
            _section('Current plan'),
            for (final i in fuel)
              ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
                title: Text('${formatDistance(current.legs[i].distanceM.toDouble())} to '
                    '${legEndLabel(current, i)} — longer than your $_fuelRangeKm km fuel range'),
                subtitle: const Text('Add a fuel stop on this stretch'),
              ),
            for (final i in long)
              ListTile(
                leading: Icon(Icons.free_breakfast, color: scheme.tertiary),
                title: Text('${formatDuration(current.legs[i].durationS)} without a stop to '
                    '${legEndLabel(current, i)}'),
                trailing: _stops.length < maxStops
                    ? TextButton(
                        onPressed: () =>
                            _changed(() => _stops.insert(i.clamp(0, _stops.length), legMidpoint(current, i))),
                        child: const Text('Add break'),
                      )
                    : null,
              ),
            for (final w in weather)
              ListTile(
                leading: Icon(
                  w.warning != null ? Icons.thunderstorm : Icons.wb_cloudy_outlined,
                  color: w.warning != null ? scheme.error : scheme.onSurfaceVariant,
                ),
                title: Text('${w.label.isEmpty ? (w.kind == 'destination' ? 'Destination' : 'Stop') : w.label}'
                    ' · ~${formatClock(w.eta)}'),
                subtitle: Text([
                  if (w.summary != null) w.summary!,
                  if (w.tempC != null) '${w.tempC!.round()}°C',
                  if (w.rainPct != null) 'rain ${w.rainPct}%',
                  if (w.warning != null) w.warning!,
                ].join(' · ')),
              ),
          ],
          if (_options != null) ...[
            _section('Choose a route'),
            RadioGroup<int>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v ?? 0),
              child: Column(
                children: [
                  for (final o in _options!)
                    RadioListTile<int>(
                      value: o.index,
                      title: Text(o.label),
                      subtitle: Text(
                        '${formatDistance(o.distanceM.toDouble())} · ${formatDuration(o.durationS)}',
                        style: const TextStyle(fontFeatures: tabularFigures),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (current != null && _options == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                'Current: ${current.routeLabel.isEmpty ? '' : '${current.routeLabel} · '}'
                '${formatDistance(current.distanceM.toDouble())} · ${formatDuration(current.durationS)}'
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
              label: Text(_options == null ? 'Plan route for everyone' : 'Use this route for everyone'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _compare,
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Compare routes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save trip'),
                  ),
                ),
              ],
            ),
          ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: TextButton.icon(
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
