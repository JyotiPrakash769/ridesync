import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android foreground service that keeps the app process (and therefore the
/// geolocator stream and WebSocket in the main isolate) alive while the
/// screen is locked, with a persistent "RideSync is tracking your ride"
/// notification. Location itself stays in the main isolate: simplest
/// reliable setup for v0.1.
abstract final class TrackingService {
  static const int _serviceId = 4711;

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ridesync_tracking',
        channelName: 'Ride tracking',
        channelDescription: 'Shown while RideSync shares your location with your group.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false,
      ),
    );
  }

  static Future<bool> start(String rideId) async {
    if (await FlutterForegroundTask.isRunningService) return true;
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'RideSync is tracking your ride',
      notificationText: 'Ride $rideId · your group can see you',
      callback: startTrackingCallback,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void startTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

/// No work in the service isolate; the service only exists to keep the
/// process foregrounded (location type) while riding.
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
