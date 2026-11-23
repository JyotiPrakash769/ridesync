import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/location/location_service.dart';
import '../../core/storage/local_db.dart';

const String _bgPromptedKey = 'bg_location_prompted';

/// Two sequential location requests (fine, then background), each preceded
/// by a plain-language explanation; then notifications for the tracking
/// notification. Returns what the rider granted.
Future<LocationAccess> runTrackingPermissionFlow(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;

  // Step 1: precise location while using the app.
  var fine = await Permission.location.status;
  if (!fine.isGranted) {
    if (!context.mounted) return LocationAccess.denied;
    final go = await _explain(
      context,
      icon: Icons.location_on,
      title: 'Share your location with the group',
      body: 'RideSync shows everyone in this ride on one map. Your location is only shared '
          'with this ride and only while you\'re in it.',
      action: 'Continue',
    );
    if (!go) return LocationAccess.denied;
    fine = await Permission.location.request();
    if (fine.isPermanentlyDenied) return LocationAccess.deniedForever;
    if (!fine.isGranted) return LocationAccess.denied;
  }

  // Step 2: background ("Allow all the time"). Asked once per install.
  var access = LocationAccess.foregroundOnly;
  if (await Permission.locationAlways.isGranted) {
    access = LocationAccess.always;
  } else {
    final box = Hive.box<dynamic>(LocalDb.sessionBox);
    if (box.get(_bgPromptedKey) != true) {
      await box.put(_bgPromptedKey, true);
      if (!context.mounted) return access;
      final go = await _explain(
        context,
        icon: Icons.screen_lock_portrait,
        title: 'Keep tracking with the screen off',
        body: 'With your phone locked on the handlebar, RideSync keeps sharing your position. '
            'On the next screen choose "Allow all the time".',
        action: 'Open settings',
        secondary: 'Not now',
      );
      if (go && (await Permission.locationAlways.request()).isGranted) {
        access = LocationAccess.always;
      }
      if (access == LocationAccess.foregroundOnly && context.mounted) {
        await _explain(
          context,
          icon: Icons.info_outline,
          title: 'Location only while using RideSync',
          body: 'Tracking keeps running while the "RideSync is tracking your ride" notification '
              'is showing. If Android closes the app, your group stops seeing you until you '
              'reopen it. You can change this later in Settings › Apps › RideSync › Location.',
          action: 'Got it',
        );
      }
    }
  }

  // Android 13+: the persistent tracking notification needs this.
  if (await FlutterForegroundTask.checkNotificationPermission() !=
      NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  return access;
}

Future<bool> _explain(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String body,
  required String action,
  String? secondary,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      icon: Icon(icon),
      title: Text(title),
      content: Text(body),
      actions: [
        if (secondary != null)
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(secondary)),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}
