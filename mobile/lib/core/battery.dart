import 'package:flutter/services.dart';

/// Phone battery % via MainActivity's "ridesync/battery" channel (null if unknown).
class BatteryReader {
  const BatteryReader();

  static const _channel = MethodChannel('ridesync/battery');

  Future<int?> level() async {
    try {
      return await _channel.invokeMethod<int>('level');
    } catch (_) {
      return null;
    }
  }
}
