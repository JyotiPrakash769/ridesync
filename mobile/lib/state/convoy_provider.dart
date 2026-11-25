import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/alerts/announcer.dart';
import '../core/battery.dart';
import '../core/config/env.dart';
import '../core/location/location_service.dart';
import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../core/storage/local_db.dart';
import '../core/storage/location_queue.dart';
import '../features/offline_sync/sync_manager.dart';
import '../models/location_point.dart';
import '../models/rider.dart';
import '../models/trip_plan.dart';
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

final batteryReaderProvider = Provider<BatteryReader>((ref) => const BatteryReader());

/// Low-battery warning threshold (leader hears it once per crossing).
const int lowBatteryPct = 15;

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
  int? _battery;
  DateTime _batteryAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _weatherTimer;
  final Set<String> _lowBatteryWarned = {};

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
        final before = state;
        state = applyMessage(state, m);
        _onEvent(m);
        if (m['type'] == 'rider_positions') _checkBatteries(before);
        if (m['type'] == 'trip_plan') unawaited(refreshWeather());
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
    _weatherTimer = Timer.periodic(const Duration(minutes: 30), (_) => refreshWeather());
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
        plan: () => state.plan ?? info.plan,
        sweepId: () => state.sweepId ?? info.sweepId,
        arrived: {...info.arrived, ...state.arrived},
      );
      if (state.plan != null) unawaited(refreshWeather());
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
    if (now.difference(_batteryAt) > const Duration(minutes: 2)) {
      _batteryAt = now;
      unawaited(ref.read(batteryReaderProvider).level().then((b) => _battery = b));
    }
    if (p != null && (!_latestSent || force)) {
      final ok = ws.send({
        'type': 'location_update',
        'lat': p.latitude,
        'lng': p.longitude,
        'speed_kph': p.speed >= 0 ? p.speed * 3.6 : null,
        'ts': p.timestamp.toUtc().toIso8601String(),
        if (_battery != null) 'battery': _battery,
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

  /// Leader: plan (or with destination null, clear) the trip.
  Future<void> setPlan({TripPlace? origin, TripPlace? destination, List<TripPlace> stops = const []}) async {
    final s = ref.read(rideSessionProvider);
    if (s == null) return;
    final plan = await ref
        .read(apiClientProvider)
        .setPlan(s.rideId, s.auth, origin: origin, destination: destination, stops: stops);
    state = state.copyWith(plan: () => plan, offRoute: const {});
  }

  /// Leader: plan with route options (avoid tolls/highways, alternative,
  /// departure time, fuel range).
  Future<void> setPlanWithOptions({
    TripPlace? origin,
    required TripPlace destination,
    List<TripPlace> stops = const [],
    PlanOptions options = const PlanOptions(),
  }) async {
    final s = ref.read(rideSessionProvider);
    if (s == null) return;
    final plan = await ref.read(apiClientProvider).setPlan(s.rideId, s.auth,
        origin: origin, destination: destination, stops: stops, options: options);
    state = state.copyWith(plan: () => plan, offRoute: const {}, arrived: const {});
    unawaited(refreshWeather());
  }

  Future<void> refreshWeather() async {
    final s = ref.read(rideSessionProvider);
    if (s == null || state.plan == null) return;
    try {
      final w = await ref.read(apiClientProvider).getWeather(s.rideId, s.auth);
      state = state.copyWith(weather: w);
    } catch (_) {/* weather is a nice-to-have */}
  }

  Future<void> setSweep(String? riderId) async {
    final s = ref.read(rideSessionProvider);
    if (s == null) return;
    await ref.read(apiClientProvider).setSweep(s.rideId, s.auth, riderId);
    state = state.copyWith(sweepId: () => riderId);
  }

  /// One-tap message to the ride (codes in announcer.dart).
  bool sendQuick(String code) => _ws?.send({'type': 'quick_message', 'code': code}) ?? false;

  /// Leader hears once when a rider's battery drops to lowBatteryPct or below.
  void _checkBatteries(ConvoyState before) {
    for (final r in state.riders.values) {
      final b = r.battery;
      if (b == null) continue;
      if (b > lowBatteryPct + 5) _lowBatteryWarned.remove(r.id);
      final prev = before.riders[r.id]?.battery;
      if (b <= lowBatteryPct && !_lowBatteryWarned.contains(r.id) && (prev == null || prev > lowBatteryPct || prev == b)) {
        _lowBatteryWarned.add(r.id);
        _onEvent({'type': 'low_battery', 'rider_id': r.id, 'name': r.name, 'battery': b});
      }
    }
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
    _weatherTimer?.cancel();
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
