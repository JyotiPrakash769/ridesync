import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/deep_links.dart';
import 'core/location/background_task.dart';
import 'core/theme/app_theme.dart';
import 'features/convoy_map/convoy_map_screen.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/intro_screen.dart';
import 'features/ride_join/join_ride_screen.dart';
import 'state/convoy_provider.dart';
import 'state/ride_session_provider.dart';
import 'state/settings.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// Stops the foreground tracking service (overridden in tests: no platform).
final stopTrackingProvider = Provider<Future<void> Function()>((ref) => TrackingService.stop);

class RideSyncApp extends ConsumerStatefulWidget {
  const RideSyncApp({super.key, this.deepLinks});

  /// Null disables deep-link listening (tests).
  final DeepLinks? deepLinks;

  @override
  ConsumerState<RideSyncApp> createState() => _RideSyncAppState();
}

class _RideSyncAppState extends ConsumerState<RideSyncApp> {
  StreamSubscription<String>? _links;

  @override
  void initState() {
    super.initState();
    _links = widget.deepLinks?.rideIds.listen(_openJoin);
  }

  void _openJoin(String rideId) {
    final session = ref.read(rideSessionProvider);
    if (session?.rideId == rideId) return; // already in this ride
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => JoinRideScreen(initialRideId: rideId)),
    );
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(rideSessionProvider, (prev, next) {
      if (prev != null && next == null) {
        // Ride over (ended, left, or refused): stop tracking, drop unsent points.
        unawaited(ref.read(stopTrackingProvider)());
        unawaited(ref.read(locationQueueProvider).clear());
      }
    });
    final inRide = ref.watch(rideSessionProvider) != null;
    final settings = ref.watch(settingsProvider);
    final hc = settings.handlebarMode;
    return MaterialApp(
      title: 'RideSync',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(highContrast: hc),
      darkTheme: AppTheme.dark(highContrast: hc),
      themeMode: settings.themeMode,
      // Handlebar mode: everything a bit larger for glancing at a mounted phone.
      builder: (context, child) => hc
          ? MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(handlebarTextScale)),
              child: child!,
            )
          : child!,
      home: inRide
          ? const ConvoyMapScreen()
          : settings.introSeen
              ? const HomeScreen()
              : const IntroScreen(),
    );
  }
}
