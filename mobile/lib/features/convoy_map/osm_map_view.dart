import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/rider.dart';
import '../../models/trip_plan.dart';
import 'convoy_map_view.dart';
import 'map_geometry.dart';
import 'rider_marker_widget.dart';

/// OpenStreetMap map (no API key): standard OSM tiles, darkened on the
/// device in dark mode (flutter_map's darkModeTileBuilder). CARTO's dark
/// basemap now requires an API key, so it is not used.
///
/// Markers glide to each new position over [glide] instead of jumping every
/// ~4 s, trails are drawn under them, and the leader's regroup pin on top.
class OsmConvoyMap extends StatefulWidget {
  const OsmConvoyMap({
    super.key,
    required this.data,
    required this.onReady,
    required this.padding,
    this.onLongPress,
  });

  final ConvoyMapData data;
  final ValueChanged<ConvoyMapHandle> onReady;
  final EdgeInsets padding;
  final void Function(double lat, double lng)? onLongPress;

  static const String tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const Duration glide = Duration(milliseconds: 900);

  @override
  State<OsmConvoyMap> createState() => _OsmConvoyMapState();
}

class _OsmConvoyMapState extends State<OsmConvoyMap>
    with SingleTickerProviderStateMixin
    implements ConvoyMapHandle {
  final _controller = MapController();
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: OsmConvoyMap.glide, value: 1);
  final Map<String, LatLng> _from = {};
  final Map<String, LatLng> _to = {};

  @override
  void initState() {
    super.initState();
    _retarget(snap: true);
  }

  @override
  void didUpdateWidget(OsmConvoyMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.data.riders, widget.data.riders)) _retarget();
  }

  /// Starts a glide from wherever each marker is drawn now to its new point.
  void _retarget({bool snap = false}) {
    final t = Curves.easeInOut.transform(_anim.value);
    var moved = false;
    final ids = <String>{};
    for (final r in widget.data.riders) {
      if (!r.hasPosition) continue;
      ids.add(r.id);
      final target = LatLng(r.lat!, r.lng!);
      final current = _displayed(r.id, t) ?? target;
      if (_to[r.id] != target) moved = true;
      _from[r.id] = snap ? target : current;
      _to[r.id] = target;
    }
    _from.removeWhere((k, _) => !ids.contains(k));
    _to.removeWhere((k, _) => !ids.contains(k));
    if (moved && !snap) _anim.forward(from: 0);
  }

  LatLng? _displayed(String id, double t) {
    final a = _from[id], b = _to[id];
    if (a == null || b == null) return b;
    return LatLng(a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t);
  }

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
  void fitPoints(List<(double, double)> points) {
    if (points.length < 2) return;
    _controller.fitCamera(CameraFit.coordinates(
      coordinates: [for (final (la, ln) in points) LatLng(la, ln)],
      padding: widget.padding + const EdgeInsets.all(40),
      maxZoom: 16,
    ));
  }

  @override
  void focus(Rider r) {
    if (r.hasPosition) _controller.move(LatLng(r.lat!, r.lng!), MapGeometry.focusZoom);
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final ordered = [
      ...data.riders.where((r) => r.hasPosition && !r.isLeader && r.id != data.selfId),
      ...data.riders.where((r) => r.hasPosition && r.isLeader && r.id != data.selfId),
      ...data.riders.where((r) => r.hasPosition && r.id == data.selfId), // you on top
    ];
    final regroup = data.regroup;

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: const LatLng(MapGeometry.fallbackLat, MapGeometry.fallbackLng),
        initialZoom: 13,
        backgroundColor: scheme.surface,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onLongPress: widget.onLongPress == null
            ? null
            : (_, p) => widget.onLongPress!(p.latitude, p.longitude),
        onMapReady: () => widget.onReady(this),
      ),
      children: [
        TileLayer(
          urlTemplate: OsmConvoyMap.tiles,
          userAgentPackageName: 'app.ridesync.ridesync',
          tileBuilder: dark ? darkModeTileBuilder : null,
          maxZoom: 19,
        ),
        if (data.plan != null && data.plan!.route.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: [for (final (la, ln) in data.plan!.route) LatLng(la, ln)],
              strokeWidth: 7,
              color: scheme.primary.withValues(alpha: data.plan!.approximate ? 0.45 : 0.85),
              borderStrokeWidth: 2,
              borderColor: scheme.surface.withValues(alpha: 0.8),
              pattern: data.plan!.approximate
                  ? StrokePattern.dashed(segments: const [14, 10])
                  : const StrokePattern.solid(),
            ),
          ]),
        if (data.plan != null) MarkerLayer(markers: _tripMarkers(data.plan!, scheme)),
        PolylineLayer(
          polylines: [
            for (final r in ordered)
              if ((data.trails[r.id]?.length ?? 0) >= 2)
                Polyline(
                  points: [for (final p in data.trails[r.id]!) LatLng(p.lat, p.lng)],
                  strokeWidth: 4,
                  color: (r.id == data.selfId
                          ? scheme.tertiary
                          : r.isLeader
                              ? scheme.primary
                              : scheme.secondary)
                      .withValues(alpha: 0.4),
                ),
          ],
        ),
        if (regroup != null)
          MarkerLayer(markers: [
            Marker(
              point: LatLng(regroup.lat, regroup.lng),
              width: 160,
              height: 72,
              alignment: const Alignment(0, -0.6),
              child: _RegroupPin(label: regroup.label),
            ),
          ]),
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_anim.value);
            return MarkerLayer(
              markers: [
                for (final r in ordered)
                  Marker(
                    key: ValueKey(r.id),
                    point: _displayed(r.id, t) ?? LatLng(r.lat!, r.lng!),
                    width: RiderMarkerWidget.width,
                    height: RiderMarkerWidget.height,
                    alignment: RiderMarkerWidget.anchor,
                    child: RiderMarkerWidget(
                      rider: r,
                      isSelf: r.id == data.selfId,
                      headingDeg: data.headingOf(r.id),
                      youLabel: data.youLabel,
                    ),
                  ),
              ],
            );
          },
        ),
        Padding(
          padding: EdgeInsets.only(top: widget.padding.top),
          child: SimpleAttributionWidget(
            alignment: Alignment.topLeft,
            backgroundColor: scheme.surface.withValues(alpha: 0.7),
            source: Text(
              'OpenStreetMap contributors',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }
}

List<Marker> _tripMarkers(TripPlan plan, ColorScheme scheme) => [
      Marker(
        point: LatLng(plan.origin.lat, plan.origin.lng),
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.primary, width: 4),
          ),
        ),
      ),
      for (var i = 0; i < plan.stops.length; i++)
        Marker(
          point: LatLng(plan.stops[i].lat, plan.stops[i].lng),
          width: 30,
          height: 30,
          child: Semantics(
            label: 'Stop ${i + 1}: ${plan.stops[i].label}',
            child: CircleAvatar(
              backgroundColor: scheme.secondary,
              child: Text('${i + 1}',
                  style: TextStyle(color: scheme.onSecondary, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      Marker(
        point: LatLng(plan.destination.lat, plan.destination.lng),
        width: 44,
        height: 44,
        alignment: const Alignment(0.4, -0.8),
        child: Semantics(
          label: 'Destination: ${plan.destination.label}',
          child: Icon(Icons.sports_score, size: 40, color: scheme.primary),
        ),
      ),
    ];

class _RegroupPin extends StatelessWidget {
  const _RegroupPin({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
        Icon(Icons.flag_circle, size: 40, color: scheme.tertiary),
      ],
    );
  }
}
