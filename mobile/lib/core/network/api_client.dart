import 'package:dio/dio.dart';

import '../../models/ride.dart';
import '../config/env.dart';

enum ApiErrorKind { notFound, gone, forbidden, unauthorized, invalid, rateLimited, network, server }

/// A rider's identity for authenticated calls: id + secret token from create/join.
class RiderAuth {
  const RiderAuth(this.riderId, this.token);

  final String riderId;
  final String token;

  Map<String, String> get headers => {'X-Rider-Id': riderId, 'X-Rider-Token': token};
}

/// POST /rides/{id}/join response.
class JoinedRide {
  const JoinedRide({required this.riderId, required this.riderToken});

  final String riderId;
  final String riderToken;
}

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
      riderToken: j['rider_token'] as String,
    );
  }

  /// Throws ApiException(notFound) for an unknown ride and
  /// ApiException(gone) for an ended/expired one.
  Future<JoinedRide> joinRide(String rideId, String displayName) async {
    final j = await _send(
      () => _dio.post('/rides/$rideId/join', data: {'display_name': displayName}),
    );
    return JoinedRide(
      riderId: j['rider_id'] as String,
      riderToken: j['rider_token'] as String,
    );
  }

  Future<RideInfo> getRide(String rideId, RiderAuth auth) async => RideInfo.fromJson(
        await _send(() => _dio.get('/rides/$rideId', options: Options(headers: auth.headers))),
      );

  Future<int> setThreshold(String rideId, RiderAuth auth, int thresholdM) async {
    final j = await _send(() => _dio.patch(
          '/rides/$rideId/threshold',
          data: {'rider_id': auth.riderId, 'threshold_m': thresholdM},
          options: Options(headers: auth.headers),
        ));
    return j['threshold_m'] as int;
  }

  Future<void> endRide(String rideId, RiderAuth auth) async {
    await _send(() => _dio.post(
          '/rides/$rideId/end',
          data: {'rider_id': auth.riderId},
          options: Options(headers: auth.headers),
        ));
  }

  /// Offline-sync batch upload. Returns the accepted count.
  Future<int> syncPoints(String rideId, RiderAuth auth, List<Map<String, dynamic>> points) async {
    final j = await _send(() => _dio.post(
          '/rides/$rideId/sync',
          data: {'rider_id': auth.riderId, 'points': points},
          options: Options(headers: auth.headers),
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
          401 => ApiErrorKind.unauthorized,
          429 => ApiErrorKind.rateLimited,
          422 || 400 => ApiErrorKind.invalid,
          _ => ApiErrorKind.server,
        },
        code,
      );
    }
  }
}
