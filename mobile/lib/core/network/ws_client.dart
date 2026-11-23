import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

enum WsConnState { connecting, connected, reconnecting, closed }

/// Close codes the server uses to refuse a socket or end a ride. These are
/// final: reconnecting cannot succeed, so the client stops.
const int closeRideNotFound = 4404;
const int closeRideEnded = 4410;
const int closeNotARider = 4403;
const int closeUnauthorized = 4401;
/// 4429 (rate limited) is NOT fatal: the normal backoff retries later.
const Set<int> fatalCloseCodes = {
  closeRideNotFound,
  closeRideEnded,
  closeNotARider,
  closeUnauthorized,
};

/// Reconnect delays: 1s, 2s, 5s, 10s, then 10s forever.
const List<Duration> backoffSchedule = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
];

Duration backoffFor(int attempt) => backoffSchedule[min(attempt, backoffSchedule.length - 1)];

typedef WsConnector = WebSocketChannel Function(Uri uri);

/// The single owner of reconnect logic. Other parts of the app (offline sync)
/// listen to [states] for `connected` instead of reconnecting themselves.
class WsClient {
  WsClient({required this.uri, WsConnector? connector})
      : _connect = connector ?? WebSocketChannel.connect;

  final Uri uri;
  final WsConnector _connect;

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _states = StreamController<WsConnState>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _stopped = false;
  bool _opening = false;
  WsConnState _state = WsConnState.closed;
  int? fatalCloseCode;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<WsConnState> get states => _states.stream;
  WsConnState get state => _state;
  bool get isConnected => _state == WsConnState.connected;

  void start() {
    _stopped = false;
    _open();
  }

  /// Sends if connected. Returns false otherwise so callers can queue.
  bool send(Map<String, dynamic> message) {
    final ch = _channel;
    if (!isConnected || ch == null) return false;
    try {
      ch.sink.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Network came back (connectivity_plus): skip the remaining backoff wait.
  void retryNow() {
    if (_stopped || isConnected || _opening) return;
    _retry?.cancel();
    _attempt = 0;
    _open();
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(WsConnState.closed);
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _states.close();
  }

  void _setState(WsConnState s) {
    if (_state == s) return;
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  Future<void> _open() async {
    if (_stopped || _opening) return;
    _opening = true;
    _setState(_attempt == 0 ? WsConnState.connecting : WsConnState.reconnecting);
    final WebSocketChannel ch;
    try {
      ch = _connect(uri);
      await ch.ready;
    } catch (_) {
      _opening = false;
      _scheduleReconnect();
      return;
    }
    _opening = false;
    if (_stopped) {
      await ch.sink.close();
      return;
    }
    _channel = ch;
    _attempt = 0;
    _setState(WsConnState.connected);
    _sub = ch.stream.listen(
      (data) {
        if (data is! String) return;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic> && !_messages.isClosed) _messages.add(decoded);
        } catch (_) {/* ignore malformed frames */}
      },
      onDone: () => _onClosed(ch.closeCode),
      onError: (_) => _onClosed(null),
      cancelOnError: true,
    );
  }

  void _onClosed(int? code) {
    _channel = null;
    if (_stopped) return;
    if (code != null && fatalCloseCodes.contains(code)) {
      fatalCloseCode = code;
      _stopped = true;
      _setState(WsConnState.closed);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _setState(WsConnState.reconnecting);
    final delay = backoffFor(_attempt);
    _attempt++;
    _retry?.cancel();
    _retry = Timer(delay, _open);
  }
}
