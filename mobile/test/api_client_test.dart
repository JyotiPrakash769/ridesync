import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/core/network/api_client.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = const {}]);
  final int status;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });

  @override
  void close({bool force = false}) {}
}

class _Recording implements HttpClientAdapter {
  _Recording(this.seen);
  final List<RequestOptions> seen;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    seen.add(o);
    return ResponseBody.fromString(
        jsonEncode({'status': 'ended', 'threshold_m': 300, 'accepted': 0}), 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) =>
      throw DioException.connectionError(requestOptions: o, reason: 'offline');

  @override
  void close({bool force = false}) {}
}

ApiClient _client(HttpClientAdapter a) =>
    ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = a);

void main() {
  test('join returns rider id and secret token', () async {
    final api = _client(_Adapter(201, {'rider_id': 'r1', 'ride_id': 'K7Q2MX', 'rider_token': 't'}));
    final j = await api.joinRide('K7Q2MX', 'Ravi');
    expect((j.riderId, j.riderToken), ('r1', 't'));
  });

  test('authenticated calls send X-Rider-Id and X-Rider-Token', () async {
    final seen = <RequestOptions>[];
    final api = _client(_Recording(seen));
    const auth = RiderAuth('r1', 'secret');
    await api.endRide('K7Q2MX', auth);
    await api.setThreshold('K7Q2MX', auth, 300);
    await api.syncPoints('K7Q2MX', auth, const []);
    for (final o in seen) {
      expect(o.headers['X-Rider-Token'], 'secret', reason: o.path);
      expect(o.headers['X-Rider-Id'], 'r1', reason: o.path);
      expect((o.data as Map)['rider_id'], 'r1', reason: o.path);
    }
    expect(seen, hasLength(3));
  });

  test('maps 404 / 410 / 403 / offline to distinct kinds', () async {
    Future<ApiErrorKind> kindFor(HttpClientAdapter a) async {
      try {
        await _client(a).joinRide('K7Q2MX', 'Ravi');
      } on ApiException catch (e) {
        return e.kind;
      }
      fail('expected ApiException');
    }

    expect(await kindFor(_Adapter(404)), ApiErrorKind.notFound);
    expect(await kindFor(_Adapter(410)), ApiErrorKind.gone);
    expect(await kindFor(_Adapter(403)), ApiErrorKind.forbidden);
    expect(await kindFor(_Adapter(401)), ApiErrorKind.unauthorized);
    expect(await kindFor(_Adapter(429)), ApiErrorKind.rateLimited);
    expect(await kindFor(_Offline()), ApiErrorKind.network);
  });
}
