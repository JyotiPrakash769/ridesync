import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/deep_links.dart';
import 'core/theme/app_theme.dart';
import 'features/convoy_map/convoy_map_screen.dart';
import 'features/home/home_screen.dart';
import 'features/ride_join/join_ride_screen.dart';
import 'state/ride_session_provider.dart';

final navigatorKey = GlobalKey<NavigatorState>();

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
    final inRide = ref.watch(rideSessionProvider) != null;
    return MaterialApp(
      title: 'RideSync',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: inRide ? const ConvoyMapScreen() : const HomeScreen(),
    );
  }
}
