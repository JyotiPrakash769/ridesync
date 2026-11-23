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
  test('join returns rider id', () async {
    final api = _client(_Adapter(201, {'rider_id': 'r1', 'ride_id': 'K7Q2MX'}));
    expect(await api.joinRide('K7Q2MX', 'Ravi'), 'r1');
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
    expect(await kindFor(_Offline()), ApiErrorKind.network);
  });
}
