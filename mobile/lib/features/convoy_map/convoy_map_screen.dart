import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/location/background_task.dart';
import '../../core/location/location_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/ride_summary.dart';
import '../../models/rider.dart';
import '../../shared/format.dart';
import '../../shared/widgets/connection_chip.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../state/convoy_provider.dart';
import '../../state/convoy_state.dart';
import '../../state/ride_session_provider.dart';
import '../alerts/distance_alert_banner.dart';
import '../alerts/threshold_selector.dart';
import '../regroup/regroup_widgets.dart';
import '../rider_status/rider_status_sheet.dart';
import '../settings/settings_sheet.dart';
import 'convoy_map_view.dart';
import 'tracking_permission_flow.dart';

/// The map IS the screen: full-bleed, no app bar, floating chrome only.
class ConvoyMapScreen extends ConsumerStatefulWidget {
  const ConvoyMapScreen({super.key});

  @override
  ConsumerState<ConvoyMapScreen> createState() => _ConvoyMapScreenState();
}

class _ConvoyMapScreenState extends ConsumerState<ConvoyMapScreen> {
  ConvoyMapHandle? _map;
  bool _statusOpen = false;
  bool _fittedOnce = false;
  bool _busy = false;
  LocationAccess? _access;
  final _sheet = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTracking());
  }

  Future<void> _startTracking() async {
    final access = await runTrackingPermissionFlow(context);
    if (!mounted) return;
    setState(() => _access = access);
    if (access == LocationAccess.always || access == LocationAccess.foregroundOnly) {
      final session = ref.read(rideSessionProvider);
      if (session != null) await TrackingService.start(session.rideId);
      ref.read(convoyProvider.notifier).startGps();
    }
  }

  void _recenter(Iterable<Rider> riders) => _map?.fitGroup(riders);

  /// Frames the whole group once, the first time anyone has a position.
  void _maybeFirstFit(ConvoyState s) {
    if (_fittedOnce || _map == null) return;
    if (s.riders.values.any((r) => r.hasPosition)) {
      _fittedOnce = true;
      _recenter(s.riders.values);
    }
  }

  void _showRider(String riderId) {
    final r = ref.read(convoyProvider).riders[riderId];
    if (r != null) _map?.focus(r);
  }

  Future<void> _setThreshold(int m) async {
    try {
      await ref.read(convoyProvider.notifier).setThreshold(m);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  Future<void> _setRegroupAt(double lat, double lng) async {
    final label = await showRegroupDialog(context);
    if (label == null) return;
    await _guard(() => ref.read(convoyProvider.notifier).setRegroup(lat, lng, label));
  }

  Future<void> _regroupHere() async {
    final convoy = ref.read(convoyProvider);
    final session = ref.read(rideSessionProvider)!;
    final me = ref.read(convoyProvider.notifier).myPosition ??
        (convoy.riders[session.riderId]?.hasPosition ?? false
            ? (lat: convoy.riders[session.riderId]!.lat!, lng: convoy.riders[session.riderId]!.lng!)
            : null);
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waiting for your GPS position…')));
      return;
    }
    await _setRegroupAt(me.lat, me.lng);
  }

  void _focusRegroup() {
    final p = ref.read(convoyProvider).regroup;
    if (p == null) return;
    _map?.focus(Rider(id: 'regroup', name: '', role: RiderRole.member,
        status: RiderStatus.online, lat: p.lat, lng: p.lng));
  }

  /// Leader taps a rider: show on map or hand over leadership.
  Future<void> _riderActions(Rider r) async {
    final session = ref.read(rideSessionProvider)!;
    if (!session.isLeader || r.id == session.riderId) {
      _showRider(r.id);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              minTileHeight: AppTokens.minTouch,
              leading: const Icon(Icons.my_location),
              title: Text('Show ${r.name} on map'),
              enabled: r.hasPosition,
              onTap: () => Navigator.pop(context, 'show'),
            ),
            ListTile(
              minTileHeight: AppTokens.minTouch,
              leading: const Icon(Icons.star),
              title: Text('Make ${r.name} the leader'),
              onTap: () => Navigator.pop(context, 'lead'),
            ),
          ],
        ),
      ),
    );
    if (action == 'show') _showRider(r.id);
    if (action == 'lead' && mounted) {
      final ok = await _confirm('Make ${r.name} the leader?',
          'They get the alerts and controls. You become a regular rider.', 'Make leader');
      if (ok) await _guard(() => ref.read(convoyProvider.notifier).changeLeader(r.id));
    }
  }

  Future<void> _takeOver() async {
    final ok = await _confirm('Take over as leader?',
        'The leader has been offline for a while. You\'ll get the falling-behind alerts and '
            'ride controls.', 'Take over');
    final me = ref.read(rideSessionProvider)?.riderId;
    if (ok && me != null) await _guard(() => ref.read(convoyProvider.notifier).changeLeader(me));
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  void _toggleStatus() {
    setState(() => _statusOpen = !_statusOpen);
  }

  Future<void> _endOrLeave() async {
    final session = ref.read(rideSessionProvider);
    if (session == null) return;
    setState(() => _busy = true);
    try {
      if (session.isLeader) {
        await ref.read(apiClientProvider).endRide(session.rideId, session.auth);
        ref.read(convoyProvider.notifier).markEnded(); // shows the summary
      } else {
        ref.read(convoyProvider.notifier).sendLeave();
        await ref.read(rideSessionProvider.notifier).clear();
      }
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.gone ||
          e.kind == ApiErrorKind.notFound ||
          e.kind == ApiErrorKind.unauthorized) {
        await ref.read(rideSessionProvider.notifier).clear();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(rideSessionProvider);
    final convoy = ref.watch(convoyProvider);
    ref.listen(convoyProvider, (prev, next) {
      if (!identical(prev?.riders, next.riders)) _maybeFirstFit(next);
    });
    if (session == null) return const SizedBox.shrink();
    if (convoy.ended || convoy.fatalCloseCode != null) {
      return _RideOverView(code: convoy.fatalCloseCode);
    }

    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final barBottom = padding.bottom + AppTokens.sideMargin;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ConvoyMapView(
              data: ConvoyMapData(
                riders: convoy.riders.values.toList(),
                trails: convoy.trails,
                selfId: session.riderId,
                headingOf: convoy.headingOf,
                regroup: convoy.regroup,
              ),
              onLongPress: session.isLeader ? _setRegroupAt : null,
              showMyLocation:
                  _access == LocationAccess.always || _access == LocationAccess.foregroundOnly,
              padding: EdgeInsets.only(
                top: padding.top + 56,
                bottom: AppTokens.minTouch + barBottom + 8,
              ),
              onReady: (handle) {
                _map = handle;
                _maybeFirstFit(ref.read(convoyProvider));
              },
            ),
          ),
          Positioned(
            top: padding.top + 12,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                children: [
                  ConnectionChip(state: convoy.conn),
                  if (_access != null &&
                      _access != LocationAccess.always &&
                      _access != LocationAccess.foregroundOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _LocationOffChip(access: _access!),
                    ),
                ],
              ),
            ),
          ),
          if (_statusOpen)
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: 0.45,
              minChildSize: 0.2,
              maxChildSize: 0.9,
              builder: (context, scroll) => Material(
                color: scheme.surfaceContainerLow,
                elevation: 1,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: RiderStatusSheet(
                  riders: convoy.riders.values.toList(),
                  scrollController: scroll,
                  selfId: session.riderId,
                  onRiderTap: _riderActions,
                  footer: Padding(
                    padding: EdgeInsets.only(bottom: AppTokens.minTouch + barBottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (session.isLeader) ...[
                          FilledButton.tonalIcon(
                            onPressed: _regroupHere,
                            icon: const Icon(Icons.flag_circle),
                            label: const Text('Regroup at my location'),
                          ),
                          const SizedBox(height: 4),
                          Text('Tip: long-press the map to set a regroup point anywhere.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                        ],
                        if (!session.isLeader &&
                            leaderGone(convoy.leader, DateTime.now().toUtc())) ...[
                          FilledButton.icon(
                            onPressed: _takeOver,
                            icon: const Icon(Icons.star),
                            label: const Text('Take over as leader'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        OutlinedButton.icon(
                          onPressed: () => showSettingsSheet(context),
                          icon: const Icon(Icons.settings),
                          label: const Text('Settings'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _confirmEnd(session.isLeader),
                          icon: Icon(session.isLeader ? Icons.flag : Icons.logout),
                          label: Text(session.isLeader ? 'End ride for everyone' : 'Leave ride'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: AppTokens.sideMargin,
            right: AppTokens.sideMargin,
            bottom: barBottom + AppTokens.minTouch + 8 + AppTokens.gap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (convoy.regroup != null) ...[
                  RegroupCard(
                    point: convoy.regroup!,
                    myLat: convoy.riders[session.riderId]?.lat,
                    myLng: convoy.riders[session.riderId]?.lng,
                    onTap: _focusRegroup,
                    onClear: session.isLeader
                        ? () => _guard(() => ref.read(convoyProvider.notifier).clearRegroup())
                        : null,
                  ),
                  const SizedBox(height: AppTokens.gap),
                ],
                if (session.isLeader)
                  DistanceAlertBanner(
                    alerts: convoy.alerts,
                    onShowWorst: _showRider,
                    onDismiss: () => ref.read(convoyProvider.notifier).dismissAlerts(),
                  ),
              ],
            ),
          ),
          Positioned(
            left: AppTokens.sideMargin,
            right: AppTokens.sideMargin,
            bottom: barBottom,
            child: FloatingBar(
              riderCount: convoy.riders.length,
              statusOpen: _statusOpen,
              onToggleStatus: _toggleStatus,
              onRecenter: () => _recenter(convoy.riders.values),
              thresholdChip: session.isLeader
                  ? ThresholdChip(thresholdM: convoy.thresholdM, onChanged: _setThreshold)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(bool leader) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(leader ? 'End the ride?' : 'Leave the ride?'),
        content: Text(leader
            ? 'Everyone will be disconnected and the ride code will stop working.'
            : 'You\'ll disappear from the group map. You can rejoin with the ride code.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(leader ? 'End ride' : 'Leave'),
          ),
        ],
      ),
    );
    if (ok == true) await _endOrLeave();
  }
}

class _LocationOffChip extends StatelessWidget {
  const _LocationOffChip({required this.access});

  final LocationAccess access;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = access == LocationAccess.serviceOff
        ? 'Location is off — others can\'t see you'
        : 'Location permission denied — others can\'t see you';
    return Material(
      color: scheme.errorContainer,
      shape: const StadiumBorder(),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: scheme.onErrorContainer)),
          ],
        ),
      ),
    );
  }
}

/// Shown when the ride ended (leader / expiry) or the server refused us.
/// For an ended ride it loads the ride summary.
class _RideOverView extends ConsumerStatefulWidget {
  const _RideOverView({this.code});

  final int? code;

  @override
  ConsumerState<_RideOverView> createState() => _RideOverViewState();
}

class _RideOverViewState extends ConsumerState<_RideOverView> {
  Future<RideSummary>? _summary;

  @override
  void initState() {
    super.initState();
    final s = ref.read(rideSessionProvider);
    if (s != null && widget.code == null) {
      _summary = ref.read(apiClientProvider).getSummary(s.rideId, s.auth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final message = switch (widget.code) {
      closeNotARider => 'You\'re no longer part of this ride.',
      closeUnauthorized => 'Your ride session is no longer valid. Join the ride again.',
      closeRideNotFound => 'This ride no longer exists.',
      _ => 'This ride has ended.',
    };
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.flag, size: 48),
            const SizedBox(height: 16),
            Text(message, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_summary != null)
              FutureBuilder<RideSummary>(
                future: _summary,
                builder: (context, snap) {
                  final s = snap.data;
                  if (s == null) {
                    return snap.hasError
                        ? const SizedBox.shrink()
                        : const Center(child: CircularProgressIndicator());
                  }
                  final h = s.duration.inHours, m = s.duration.inMinutes % 60;
                  return Card(
                    color: scheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ride summary', style: text.titleMedium),
                          const SizedBox(height: 8),
                          Text(
                            '${h > 0 ? '${h}h ' : ''}${m}min · '
                            '${s.fallingBehindTotal} falling-behind alert'
                            '${s.fallingBehindTotal == 1 ? '' : 's'}',
                            style: text.bodyMedium?.copyWith(fontFeatures: tabularFigures),
                          ),
                          const Divider(height: 24),
                          for (final r in s.riders)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(r.isLeader ? Icons.star : Icons.two_wheeler),
                              title: Text(r.name),
                              subtitle: Text(
                                [
                                  '${r.distanceKm.toStringAsFixed(1)} km',
                                  if (r.fallingBehindCount > 0)
                                    'fell behind ${r.fallingBehindCount}x'
                                        '${r.maxGapM != null ? ' (max ${formatDistance(r.maxGapM!.toDouble())})' : ''}',
                                ].join(' · '),
                                style: text.bodySmall?.copyWith(fontFeatures: tabularFigures),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ref.read(rideSessionProvider.notifier).clear(),
              child: const Text('Back to start'),
            ),
          ],
        ),
      ),
    );
  }
}
