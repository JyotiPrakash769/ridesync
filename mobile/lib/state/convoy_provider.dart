import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/config/env.dart';
import '../core/location/location_service.dart';
import '../core/network/ws_client.dart';
import 'convoy_state.dart';
import 'ride_session.dart';
import 'ride_session_provider.dart';

/// Send cadence: a location_update every ~4s when there is a fresh fix,
/// otherwise a heartbeat at most every 10s so the rider stays "online".
const Duration sendInterval = Duration(seconds: 4);
const Duration heartbeatInterval = Duration(seconds: 10);

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final wsConnectorProvider = Provider<WsConnector?>((ref) => null); // null = real socket

Uri rideSocketUri(RideSession s) =>
    Uri.parse('${Env.wsBaseUrl}/ws/rides/${s.rideId}?rider_id=${s.riderId}');

final convoyProvider = NotifierProvider<ConvoyController, ConvoyState>(ConvoyController.new);

/// Owns the live link for the current ride. Rebuilt whenever the session
/// changes; everything it starts is torn down in ref.onDispose.
class ConvoyController extends Notifier<ConvoyState> {
  WsClient? _ws;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _sendTimer;
  Position? _latest;
  bool _latestSent = true;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);

  WsClient? get socket => _ws;

  @override
  ConvoyState build() {
    final session = ref.watch(rideSessionProvider);
    ref.onDispose(_teardown);
    if (session == null) return const ConvoyState(conn: WsConnState.closed);

    final ws = WsClient(uri: rideSocketUri(session), connector: ref.read(wsConnectorProvider));
    _ws = ws;
    _subs
      ..add(ws.messages.listen((m) => state = applyMessage(state, m)))
      ..add(ws.states.listen((c) {
        state = state.copyWith(conn: c, fatalCloseCode: ws.fatalCloseCode);
        if (c == WsConnState.connected) _flush(force: true);
      }));
    ws.start();
    _sendTimer = Timer.periodic(sendInterval, (_) => _flush());
    unawaited(_loadInitial(session));
    return const ConvoyState();
  }

  Future<void> _loadInitial(RideSession s) async {
    try {
      final info = await ref.read(apiClientProvider).getRide(s.rideId);
      final known = {...state.riders};
      for (final r in info.riders) {
        known.putIfAbsent(r.id, () => r);
      }
      state = state.copyWith(thresholdM: info.thresholdM, riders: known, ended: !info.active);
    } catch (_) {/* the socket snapshot fills this in anyway */}
  }

  /// Starts GPS once permission is granted (the screen asks the user).
  Future<LocationAccess> startLocation() async {
    final svc = ref.read(locationServiceProvider);
    final access = await svc.ensureForegroundPermission();
    if (access == LocationAccess.always || access == LocationAccess.foregroundOnly) {
      _subs.add(svc.positions().listen((p) {
        _latest = p;
        _latestSent = false;
      }));
    }
    return access;
  }

  void _flush({bool force = false}) {
    final ws = _ws;
    if (ws == null) return;
    final now = DateTime.now();
    final p = _latest;
    if (p != null && (!_latestSent || force)) {
      final ok = ws.send({
        'type': 'location_update',
        'lat': p.latitude,
        'lng': p.longitude,
        'speed_kph': p.speed >= 0 ? p.speed * 3.6 : null,
        'ts': p.timestamp.toUtc().toIso8601String(),
      });
      if (ok) {
        _latestSent = true;
        _lastSend = now;
      }
      return;
    }
    if (now.difference(_lastSend) >= heartbeatInterval && ws.send({'type': 'heartbeat'})) {
      _lastSend = now;
    }
  }

  /// Member leaves for good (server removes them and broadcasts rider_left).
  void sendLeave() => _ws?.send({'type': 'leave'});

  void _teardown() {
    _sendTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final ws = _ws;
    _ws = null;
    if (ws != null) unawaited(ws.dispose());
  }
}
