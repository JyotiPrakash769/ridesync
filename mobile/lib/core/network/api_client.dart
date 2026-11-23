import 'package:dio/dio.dart';

import '../../models/ride.dart';
import '../config/env.dart';

enum ApiErrorKind { notFound, gone, forbidden, invalid, network, server }

class ApiException implements Exception {
  const ApiException(this.kind, [this.statusCode]);

  final ApiErrorKind kind;
  final int? statusCode;

  @override
  String toString() => 'ApiException($kind, $statusCode)';
}

/// REST wrapper for the foundation-doc §4 API.
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              contentType: 'application/json',
            ));

  final Dio _dio;

  Future<CreatedRide> createRide(String leaderName) async {
    final j = await _send(() => _dio.post('/rides', data: {'leader_name': leaderName}));
    return CreatedRide(
      rideId: j['ride_id'] as String,
      leaderRiderId: j['leader_rider_id'] as String,
      qrPayload: j['qr_payload'] as String,
    );
  }

  /// Returns the new rider_id. Throws ApiException(notFound) for an unknown
  /// ride and ApiException(gone) for an ended/expired one.
  Future<String> joinRide(String rideId, String displayName) async {
    final j = await _send(
      () => _dio.post('/rides/$rideId/join', data: {'display_name': displayName}),
    );
    return j['rider_id'] as String;
  }

  Future<RideInfo> getRide(String rideId) async =>
      RideInfo.fromJson(await _send(() => _dio.get('/rides/$rideId')));

  Future<int> setThreshold(String rideId, String riderId, int thresholdM) async {
    final j = await _send(() => _dio.patch(
          '/rides/$rideId/threshold',
          data: {'rider_id': riderId, 'threshold_m': thresholdM},
        ));
    return j['threshold_m'] as int;
  }

  Future<void> endRide(String rideId, String riderId) async {
    await _send(() => _dio.post('/rides/$rideId/end', data: {'rider_id': riderId}));
  }

  /// Offline-sync batch upload (Phase 4). Returns the accepted count.
  Future<int> syncPoints(String rideId, String riderId, List<Map<String, dynamic>> points) async {
    final j = await _send(() => _dio.post(
          '/rides/$rideId/sync',
          data: {'rider_id': riderId, 'points': points},
        ));
    return j['accepted'] as int;
  }

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return (res.data as Map).cast<String, dynamic>();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == null) throw const ApiException(ApiErrorKind.network);
      throw ApiException(
        switch (code) {
          404 => ApiErrorKind.notFound,
          410 => ApiErrorKind.gone,
          403 => ApiErrorKind.forbidden,
          422 || 400 => ApiErrorKind.invalid,
          _ => ApiErrorKind.server,
        },
        code,
      );
    }
  }
}
