import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/core/network/ws_client.dart';

import 'helpers/fake_socket.dart';

void main() {
  final uri = Uri.parse('ws://test/ws/rides/K7Q2MX?rider_id=r');

  test('backoff schedule is 1s, 2s, 5s, 10s, then capped at 10s', () {
    expect(
      [for (var i = 0; i < 7; i++) backoffFor(i).inSeconds],
      [1, 2, 5, 10, 10, 10, 10],
    );
  });

  test('failed connects retry on the backoff schedule', () {
    fakeAsync((fa) {
      final attempts = <int>[];
      final client = WsClient(
        uri: uri,
        connector: (_) {
          attempts.add(fa.elapsed.inSeconds);
          return FakeChannel(fail: true);
        },
      );
      final states = <WsConnState>[];
      client.states.listen(states.add);
      client.start();
      fa.elapse(const Duration(seconds: 40));
      // t=0, +1 -> 1, +2 -> 3, +5 -> 8, +10 -> 18, +10 -> 28, +10 -> 38
      expect(attempts, [0, 1, 3, 8, 18, 28, 38]);
      expect(states.first, WsConnState.connecting);
      expect(states.last, WsConnState.reconnecting);
      expect(client.isConnected, isFalse);
      client.stop();
    });
  });

  test('a drop reconnects after 1s and resets the backoff', () {
    fakeAsync((fa) {
      final channels = <FakeChannel>[];
      final client = WsClient(uri: uri, connector: (_) {
        final c = FakeChannel();
        channels.add(c);
        return c;
      });
      final received = <Map<String, dynamic>>[];
      client.messages.listen(received.add);
      client.start();
      fa.flushMicrotasks();
      expect(client.state, WsConnState.connected);

      channels.last.serverSend(jsonEncode({'type': 'ride_ended'}));
      fa.flushMicrotasks();
      expect(received.single['type'], 'ride_ended');

      channels.last.serverClose(1006); // network drop
      fa.flushMicrotasks();
      expect(client.state, WsConnState.reconnecting);
      fa.elapse(const Duration(milliseconds: 999));
      expect(channels, hasLength(1));
      fa.elapse(const Duration(milliseconds: 1));
      expect(channels, hasLength(2));
      expect(client.state, WsConnState.connected);

      // Second drop starts from 1s again (attempt counter reset on success).
      channels.last.serverClose(1006);
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 1));
      expect(channels, hasLength(3));
      client.stop();
    });
  });

  test('fatal close codes stop reconnecting', () {
    for (final code in [closeRideEnded, closeRideNotFound, closeNotARider]) {
      fakeAsync((fa) {
        final channels = <FakeChannel>[];
        final client = WsClient(uri: uri, connector: (_) {
          final c = FakeChannel();
          channels.add(c);
          return c;
        });
        client.start();
        fa.flushMicrotasks();
        channels.last.serverClose(code);
        fa.flushMicrotasks();
        fa.elapse(const Duration(minutes: 1));
        expect(channels, hasLength(1), reason: '$code');
        expect(client.state, WsConnState.closed);
        expect(client.fatalCloseCode, code);
      });
    }
  });

  test('send only works while connected, and resumes after reconnect', () {
    fakeAsync((fa) {
      final channels = <FakeChannel>[];
      final client = WsClient(uri: uri, connector: (_) {
        final c = FakeChannel();
        channels.add(c);
        return c;
      });
      expect(client.send({'type': 'heartbeat'}), isFalse);
      client.start();
      fa.flushMicrotasks();
      expect(client.send({'type': 'heartbeat'}), isTrue);
      expect(channels.last.fakeSink.sent.single, '{"type":"heartbeat"}');

      channels.last.serverClose(1006);
      fa.flushMicrotasks();
      expect(client.send({'type': 'heartbeat'}), isFalse);
      fa.elapse(const Duration(seconds: 1));
      expect(client.send({'type': 'heartbeat'}), isTrue);
      expect(channels.last.fakeSink.sent, hasLength(1));
      client.stop();
    });
  });

  test('retryNow skips the remaining backoff when the network returns', () {
    fakeAsync((fa) {
      var fail = true;
      final attempts = <int>[];
      final client = WsClient(uri: uri, connector: (_) {
        attempts.add(fa.elapsed.inSeconds);
        return FakeChannel(fail: fail);
      });
      client.start();
      fa.elapse(const Duration(seconds: 4)); // attempts at 0, 1, 3; next due at 8
      expect(attempts, [0, 1, 3]);
      fail = false;
      client.retryNow();
      fa.flushMicrotasks();
      expect(attempts, [0, 1, 3, 4]);
      expect(client.isConnected, isTrue);
      client.retryNow(); // no-op while connected
      fa.flushMicrotasks();
      expect(attempts, hasLength(4));
      client.stop();
    });
  });
}
