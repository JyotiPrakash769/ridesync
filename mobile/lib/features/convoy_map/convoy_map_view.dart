import 'package:material_ui/material_ui.dart';

import '../../core/config/env.dart';
import '../../models/rider.dart';
import '../../state/convoy_state.dart';
import 'google_map_view.dart';
import 'osm_map_view.dart';

/// Camera commands the convoy screen needs, independent of the map provider.
abstract interface class ConvoyMapHandle {
  void fitGroup(Iterable<Rider> riders);
  void focus(Rider rider);
}

/// Everything a map implementation draws.
class ConvoyMapData {
  const ConvoyMapData({
    required this.riders,
    required this.trails,
    required this.selfId,
    required this.headingOf,
    this.regroup,
    this.youLabel = 'You',
  });

  final List<Rider> riders;
  final Map<String, List<TrailPoint>> trails;
  final String selfId;
  final double? Function(String riderId) headingOf;

  /// Leader's regroup pin (stage 4), if any.
  final RegroupPoint? regroup;
  final String youLabel;
}

/// Full-bleed convoy map. Uses OpenStreetMap by default; Google Maps when the
/// app is built with --dart-define=MAP_PROVIDER=google (needs MAPS_API_KEY).
class ConvoyMapView extends StatelessWidget {
  const ConvoyMapView({
    super.key,
    required this.data,
    required this.onReady,
    required this.padding,
    this.showMyLocation = false,
    this.onLongPress,
  });

  final ConvoyMapData data;
  final ValueChanged<ConvoyMapHandle> onReady;

  /// Space covered by floating chrome; camera fits keep riders out of it.
  final EdgeInsets padding;
  final bool showMyLocation;

  /// Long-press on the map (lat, lng): leader sets a regroup point.
  final void Function(double lat, double lng)? onLongPress;

  static bool get usesGoogle => Env.mapProvider == 'google';

  @override
  Widget build(BuildContext context) => usesGoogle
      ? GoogleConvoyMap(
          data: data,
          onReady: onReady,
          padding: padding,
          showMyLocation: showMyLocation,
          onLongPress: onLongPress,
        )
      : OsmConvoyMap(data: data, onReady: onReady, padding: padding, onLongPress: onLongPress);
}
