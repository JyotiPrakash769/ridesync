import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/rider.dart';
import 'convoy_map_view.dart';
import 'map_geometry.dart';
import 'rider_marker_widget.dart';

/// OpenStreetMap-data map (no API key). Dark theme uses CARTO's dark basemap,
/// light theme the standard OSM tiles. Attribution is required by both.
class OsmConvoyMap extends StatefulWidget {
  const OsmConvoyMap({
    super.key,
    required this.riders,
    required this.onReady,
    required this.padding,
  });

  final List<Rider> riders;
  final ValueChanged<ConvoyMapHandle> onReady;
  final EdgeInsets padding;

  static const String darkTiles =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const String lightTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  State<OsmConvoyMap> createState() => _OsmConvoyMapState();
}

class _OsmConvoyMapState extends State<OsmConvoyMap> implements ConvoyMapHandle {
  final _controller = MapController();

  @override
  void fitGroup(Iterable<Rider> riders) {
    final pts = MapGeometry.points(riders);
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _controller.move(LatLng(pts.single.$1, pts.single.$2), MapGeometry.singleRiderZoom);
      return;
    }
    final ((s, w), (n, e)) = MapGeometry.bounds(riders)!;
    _controller.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(LatLng(s, w), LatLng(n, e)),
      padding: widget.padding + const EdgeInsets.all(48),
      maxZoom: 17,
    ));
  }

  @override
  void focus(Rider r) {
    if (r.hasPosition) _controller.move(LatLng(r.lat!, r.lng!), MapGeometry.focusZoom);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final sorted = [
      ...widget.riders.where((r) => r.hasPosition && !r.isLeader),
      ...widget.riders.where((r) => r.hasPosition && r.isLeader), // leader drawn on top
    ];
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: const LatLng(MapGeometry.fallbackLat, MapGeometry.fallbackLng),
        initialZoom: 13,
        backgroundColor: scheme.surface,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () => widget.onReady(this),
      ),
      children: [
        TileLayer(
          urlTemplate: dark ? OsmConvoyMap.darkTiles : OsmConvoyMap.lightTiles,
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'app.ridesync.ridesync',
          retinaMode: dark && RetinaMode.isHighDensity(context),
          maxZoom: 19,
        ),
        MarkerLayer(
          markers: [
            for (final r in sorted)
              Marker(
                key: ValueKey(r.id),
                point: LatLng(r.lat!, r.lng!),
                width: RiderMarkerWidget.width,
                height: RiderMarkerWidget.height,
                alignment: RiderMarkerWidget.anchor,
                child: RiderMarkerWidget(rider: r),
              ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(top: widget.padding.top),
          child: SimpleAttributionWidget(
            alignment: Alignment.topLeft,
            backgroundColor: scheme.surface.withValues(alpha: 0.7),
            source: Text(
              dark ? 'OpenStreetMap contributors · CARTO' : 'OpenStreetMap contributors',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }
}
