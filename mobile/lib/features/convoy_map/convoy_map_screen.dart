import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

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
import '../rider_status/rider_status_sheet.dart';
import 'map_controller.dart';
import 'rider_marker.dart';

/// The map IS the screen: full-bleed, no app bar, floating chrome only.
class ConvoyMapScreen extends ConsumerStatefulWidget {
  const ConvoyMapScreen({super.key});

  @override
  ConsumerState<ConvoyMapScreen> createState() => _ConvoyMapScreenState();
}

class _ConvoyMapScreenState extends ConsumerState<ConvoyMapScreen> {
  GoogleMapController? _map;
  String? _mapStyle;
  RiderMarkerFactory? _markerFactory;
  Set<Marker> _markers = {};
  bool _statusOpen = false;
  bool _fittedOnce = false;
  bool _busy = false;
  LocationAccess? _access;
  final _sheet = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/map_style_dark.json').then((s) {
      if (mounted) setState(() => _mapStyle = s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final access = await ref.read(convoyProvider.notifier).startLocation();
      if (mounted) setState(() => _access = access);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_markerFactory?.scheme != scheme || _markerFactory?.devicePixelRatio != dpr) {
      _markerFactory = RiderMarkerFactory(scheme, dpr);
    }
  }

  Future<void> _rebuildMarkers(ConvoyState s) async {
    final factory = _markerFactory;
    if (factory == null) return;
    final next = <Marker>{};
    for (final r in s.riders.values) {
      if (!r.hasPosition) continue;
      next.add(Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.lat!, r.lng!),
        icon: await factory.build(name: r.name, leader: r.isLeader),
        anchor: RiderMarkerFactory.anchorFor(),
        alpha: r.status == RiderStatus.offline ? 0.5 : 1,
        zIndexInt: r.isLeader ? 2 : 1,
        infoWindow: InfoWindow(title: r.name),
      ));
    }
    if (mounted) setState(() => _markers = next);
    if (!_fittedOnce && next.isNotEmpty) {
      _fittedOnce = true;
      _recenter(s.riders.values);
    }
  }

  void _recenter(Iterable<Rider> riders) {
    final update = ConvoyCamera.fitGroup(riders);
    if (update != null) unawaited(_map?.animateCamera(update));
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
        await ref.read(apiClientProvider).endRide(session.rideId, session.riderId);
      } else {
        ref.read(convoyProvider.notifier).sendLeave();
      }
      await ref.read(rideSessionProvider.notifier).clear();
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.gone || e.kind == ApiErrorKind.notFound) {
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
      if (!identical(prev?.riders, next.riders)) unawaited(_rebuildMarkers(next));
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
            child: GoogleMap(
              initialCameraPosition:
                  const CameraPosition(target: ConvoyCamera.fallbackCenter, zoom: 13),
              style: Theme.of(context).brightness == Brightness.dark ? _mapStyle : null,
              markers: _markers,
              myLocationEnabled: _access == LocationAccess.always ||
                  _access == LocationAccess.foregroundOnly,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              padding: EdgeInsets.only(bottom: AppTokens.minTouch + barBottom + 8, top: padding.top),
              onMapCreated: (c) {
                _map = c;
                _recenter(convoy.riders.values);
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
                  onRiderTap: (r) {
                    final u = ConvoyCamera.focus(r);
                    if (u != null) unawaited(_map?.animateCamera(u));
                  },
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
          Positioned(
            left: AppTokens.sideMargin,
            right: AppTokens.sideMargin,
            bottom: barBottom,
            child: FloatingBar(
              riderCount: convoy.riders.length,
              statusOpen: _statusOpen,
              onToggleStatus: _toggleStatus,
              onRecenter: () => _recenter(convoy.riders.values),
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
