import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/alerts/announcer.dart';
import '../core/config/env.dart';
import '../core/location/location_service.dart';
import '../core/network/ws_client.dart';
import '../core/storage/local_db.dart';
import '../core/storage/location_queue.dart';
import '../features/offline_sync/sync_manager.dart';
import '../models/location_point.dart';
import '../models/rider.dart';
import 'convoy_state.dart';
import 'ride_session.dart';
import 'ride_session_provider.dart';
import 'settings.dart';

/// Send cadence: a location_update every ~4s when there is a fresh fix,
/// otherwise a heartbeat at most every 10s so the rider stays "online".
const Duration sendInterval = Duration(seconds: 4);
const Duration heartbeatInterval = Duration(seconds: 10);

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final announcerProvider = Provider<RideAnnouncer>((ref) => RideAnnouncer());

/// Localised announcer phrases; replaced by the l10n layer.
final announcerStringsProvider = Provider<AnnouncerStrings>((ref) => const AnnouncerStrings());

final wsConnectorProvider = Provider<WsConnector?>((ref) => null); // null = real socket

final locationQueueProvider = Provider<LocationQueue>(
  (ref) => LocationQueue(Hive.box<dynamic>(LocalDb.locationQueueBox)),
);

/// Emits when the device regains a network connection (null in tests).
final connectivityProvider = Provider<Stream<List<ConnectivityResult>>?>(
  (ref) => Connectivity().onConnectivityChanged,
);

Uri rideSocketUri(RideSession s) =>
    Uri.parse('${Env.wsBaseUrl}/ws/rides/${s.rideId}').replace(
      queryParameters: {'rider_id': s.riderId, 'token': s.riderToken},
    );

final convoyProvider = NotifierProvider<ConvoyController, ConvoyState>(ConvoyController.new);

/// Owns the live link for the current ride. Rebuilt whenever the session
/// changes; everything it starts is torn down in ref.onDispose.
class ConvoyController extends Notifier<ConvoyState> {
  WsClient? _ws;
  SyncManager? _sync;
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
    final api = ref.read(apiClientProvider);
    final sync = SyncManager(
      queue: ref.read(locationQueueProvider),
      upload: (points) => api.syncPoints(session.rideId, session.auth, points),
    );
    _sync = sync;
    _subs
      ..add(ws.messages.listen((m) {
        state = applyMessage(state, m);
        _onEvent(m);
      }))
      ..add(ws.states.listen((c) {
        state = state.copyWith(conn: c, fatalCloseCode: ws.fatalCloseCode);
        if (c == WsConnState.connected) {
          // Reconnected: upload what was cached offline, then resume live sends.
          unawaited(sync.flush());
          _flush(force: true);
        }
      }));
    final connectivity = ref.read(connectivityProvider);
    if (connectivity != null) {
      _subs.add(connectivity.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) ws.retryNow();
      }));
    }
    ws.start();
    _sendTimer = Timer.periodic(sendInterval, (_) => _flush());
    unawaited(_loadInitial(session));
    return const ConvoyState();
  }

  Future<void> _loadInitial(RideSession s) async {
    try {
      final info = await ref.read(apiClientProvider).getRide(s.rideId, s.auth);
      final known = {...state.riders};
      for (final r in info.riders) {
        known.putIfAbsent(r.id, () => r);
      }
      state = state.copyWith(
        thresholdM: info.thresholdM,
        riders: known,
        ended: !info.active,
        regroup: () => state.regroup ?? info.regroup,
      );
    } catch (_) {/* the socket snapshot fills this in anyway */}
  }

  bool _gpsStarted = false;

  /// Starts the GPS stream. Call after the permission flow granted access.
  void startGps() {
    if (_gpsStarted || _ws == null) return;
    _gpsStarted = true;
    _subs.add(ref.read(locationServiceProvider).positions().listen((p) {
      _latest = p;
      _latestSent = false;
    }));
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
      } else if (!_latestSent) {
        // Couldn't send live: cache it for POST /sync on reconnect (once per fix).
        _latestSent = true;
        unawaited(_sync?.enqueue(
          LocationPoint(lat: p.latitude, lng: p.longitude, recordedAt: p.timestamp.toUtc()),
        ));
      }
      return;
    }
    if (now.difference(_lastSend) >= heartbeatInterval && ws.send({'type': 'heartbeat'})) {
      _lastSend = now;
    }
  }

  /// Speech/vibration + keeping our own role in sync after a leader change.
  void _onEvent(Map<String, dynamic> m) {
    final session = ref.read(rideSessionProvider);
    if (session == null) return;
    if (m['type'] == 'leader_changed') {
      final iLead = m['leader_rider_id'] == session.riderId;
      unawaited(ref
          .read(rideSessionProvider.notifier)
          .updateRole(iLead ? RiderRole.leader : RiderRole.member));
    }
    unawaited(ref.read(announcerProvider).onMessage(
          m,
          isLeader: session.isLeader,
          selfId: session.riderId,
          settings: ref.read(settingsProvider),
          strings: ref.read(announcerStringsProvider),
        ));
  }

  /// Leader: set the meeting point (label like "Fuel station").
  Future<void> setRegroup(double lat, double lng, String label) async {
    final s = ref.read(rideSessionProvider);
    if (s == null) return;
    await ref.read(apiClientProvider).setRegroup(s.rideId, s.auth, lat: lat, lng: lng, label: label);
  }

  Future<void> clearRegroup() async {
    final s = ref.read(rideSessionProvider);
    if (s == null) return;
    await ref.read(apiClientProvider).setRegroup(s.rideId, s.auth);
  }

  /// Leader hands off; a member passes their own id to take over.
  Future<void> changeLeader(String newLeaderId) async {
    final s = ref.read(rideSessionProvider);
    if (s == null) return;
    await ref.read(apiClientProvider).changeLeader(s.rideId, s.auth, newLeaderId);
  }

  /// The leader ended the ride via REST: show the summary even if the
  /// ride_ended broadcast doesn't arrive (socket down).
  void markEnded() => state = state.copyWith(ended: true);

  /// Our latest GPS fix (for "regroup at my location").
  ({double lat, double lng})? get myPosition {
    final p = _latest;
    return p == null ? null : (lat: p.latitude, lng: p.longitude);
  }

  /// Leader-only. The room (including us) gets threshold_updated.
  Future<void> setThreshold(int meters) async {
    final session = ref.read(rideSessionProvider);
    if (session == null || !session.isLeader) return;
    final applied =
        await ref.read(apiClientProvider).setThreshold(session.rideId, session.auth, meters);
    state = state.copyWith(thresholdM: applied, alerts: const {});
  }

  void dismissAlerts() => state = state.copyWith(alerts: const {});

  /// Member leaves for good (server removes them and broadcasts rider_left).
  void sendLeave() => _ws?.send({'type': 'leave'});

  void _teardown() {
    _sendTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _gpsStarted = false;
    _sync = null;
    final ws = _ws;
    _ws = null;
    if (ws != null) unawaited(ws.dispose());
  }
}
