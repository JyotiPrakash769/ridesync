import 'package:material_ui/material_ui.dart';

import '../../core/config/env.dart';
import '../../models/rider.dart';
import 'google_map_view.dart';
import 'osm_map_view.dart';

/// Camera commands the convoy screen needs, independent of the map provider.
abstract interface class ConvoyMapHandle {
  void fitGroup(Iterable<Rider> riders);
  void focus(Rider rider);
}

/// Full-bleed convoy map. Uses OpenStreetMap by default; Google Maps when the
/// app is built with --dart-define=MAP_PROVIDER=google (needs MAPS_API_KEY).
class ConvoyMapView extends StatelessWidget {
  const ConvoyMapView({
    super.key,
    required this.riders,
    required this.onReady,
    required this.padding,
    this.showMyLocation = false,
  });

  final List<Rider> riders;
  final ValueChanged<ConvoyMapHandle> onReady;

  /// Space covered by floating chrome; camera fits keep riders out of it.
  final EdgeInsets padding;
  final bool showMyLocation;

  static bool get usesGoogle => Env.mapProvider == 'google';

  @override
  Widget build(BuildContext context) => usesGoogle
      ? GoogleConvoyMap(
          riders: riders, onReady: onReady, padding: padding, showMyLocation: showMyLocation)
      : OsmConvoyMap(riders: riders, onReady: onReady, padding: padding);
}
