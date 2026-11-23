import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/location/background_task.dart';
import '../../core/location/location_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/rider.dart';
import '../../shared/widgets/connection_chip.dart';
import '../../shared/widgets/error_text.dart';
import '../../shared/widgets/floating_bar.dart';
import '../../state/convoy_provider.dart';
import '../../state/convoy_state.dart';
import '../../state/ride_session_provider.dart';
import '../alerts/distance_alert_banner.dart';
import '../alerts/threshold_selector.dart';
import '../rider_status/rider_status_sheet.dart';
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
      } else {
        ref.read(convoyProvider.notifier).sendLeave();
      }
      await ref.read(rideSessionProvider.notifier).clear();
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
              riders: convoy.riders.values.toList(),
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
                  onRiderTap: (r) => _showRider(r.id),
                  footer: Padding(
                    padding: EdgeInsets.only(bottom: AppTokens.minTouch + barBottom),
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _confirmEnd(session.isLeader),
                      icon: Icon(session.isLeader ? Icons.flag : Icons.logout),
                      label: Text(session.isLeader ? 'End ride for everyone' : 'Leave ride'),
                    ),
                  ),
                ),
              ),
            ),
          if (session.isLeader)
            Positioned(
              left: AppTokens.sideMargin,
              right: AppTokens.sideMargin,
              bottom: barBottom + AppTokens.minTouch + 8 + AppTokens.gap,
              child: DistanceAlertBanner(
                alerts: convoy.alerts,
                onShowWorst: _showRider,
                onDismiss: () => ref.read(convoyProvider.notifier).dismissAlerts(),
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
class _RideOverView extends ConsumerWidget {
  const _RideOverView({this.code});

  final int? code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final message = switch (code) {
      closeNotARider => 'You\'re no longer part of this ride.',
      closeUnauthorized => 'Your ride session is no longer valid. Join the ride again.',
      closeRideNotFound => 'This ride no longer exists.',
      _ => 'This ride has ended.',
    };
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flag, size: 48),
              const SizedBox(height: 16),
              Text(message, style: text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => ref.read(rideSessionProvider.notifier).clear(),
                child: const Text('Back to start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
