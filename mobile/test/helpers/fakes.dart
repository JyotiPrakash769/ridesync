import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:ridesync/core/network/api_client.dart';
import 'package:ridesync/core/storage/local_db.dart';

/// Opens a Hive box in a throwaway temp dir.
Future<Box<dynamic>> openTempBox(String name) async {
  final dir = await Directory.systemTemp.createTemp('ridesync_test_');
  Hive.init(dir.path);
  return Hive.openBox<dynamic>(name);
}

int _boxSeq = 0;

/// Each call gets its own box: Hive returns an already-open box by name.
Future<SessionStore> tempSessionStore() async =>
    SessionStore(await openTempBox('${LocalDb.sessionBox}_${_boxSeq++}'));

/// ApiClient whose join/create results are scripted.
class FakeApi extends ApiClient {
  FakeApi({this.joinError, this.joinRiderId = 'rider-1'}) : super(dio: Dio());

  static const String token = 'secret-token';

  final ApiException? joinError;
  final String joinRiderId;
  final List<(String, String)> joins = [];

  @override
  Future<JoinedRide> joinRide(String rideId, String displayName) async {
    joins.add((rideId, displayName));
    if (joinError != null) throw joinError!;
    return JoinedRide(riderId: joinRiderId, riderToken: token);
  }
}
