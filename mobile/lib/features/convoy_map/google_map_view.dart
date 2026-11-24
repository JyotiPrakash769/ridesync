import 'dart:async';

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/rider.dart';
import 'convoy_map_view.dart';
import 'map_controller.dart';
import 'rider_marker.dart';

/// Google Maps implementation (MAP_PROVIDER=google). Needs MAPS_API_KEY in
/// android/local.properties or the CI secret; without it tiles stay blank.
class GoogleConvoyMap extends StatefulWidget {
  const GoogleConvoyMap({
    super.key,
    required this.data,
    required this.onReady,
    required this.padding,
    required this.showMyLocation,
    this.onLongPress,
  });

  final ConvoyMapData data;
  final ValueChanged<ConvoyMapHandle> onReady;
  final EdgeInsets padding;
  final bool showMyLocation;
  final void Function(double lat, double lng)? onLongPress;

  @override
  State<GoogleConvoyMap> createState() => _GoogleConvoyMapState();
}

class _GoogleConvoyMapState extends State<GoogleConvoyMap> implements ConvoyMapHandle {
  GoogleMapController? _map;
  String? _style;
  RiderMarkerFactory? _factory;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/map_style_dark.json').then((s) {
      if (mounted) setState(() => _style = s);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (_factory?.scheme != scheme || _factory?.devicePixelRatio != dpr) {
      _factory = RiderMarkerFactory(scheme, dpr);
      unawaited(_rebuild());
    }
  }

  @override
  void didUpdateWidget(GoogleConvoyMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.data.riders, widget.data.riders)) unawaited(_rebuild());
  }

  Future<void> _rebuild() async {
    final factory = _factory;
    if (factory == null) return;
    final next = <Marker>{};
    for (final r in widget.data.riders) {
      if (!r.hasPosition) continue;
      next.add(Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.lat!, r.lng!),
        icon: await factory.build(name: r.name, leader: r.isLeader),
        anchor: RiderMarkerFactory.anchorFor(),
        alpha: r.status == RiderStatus.offline ? 0.5 : 1,
        zIndexInt: r.id == widget.data.selfId ? 3 : (r.isLeader ? 2 : 1),
        infoWindow: InfoWindow(title: r.name),
      ));
    }
    if (mounted) setState(() => _markers = next);
  }

  @override
  void fitGroup(Iterable<Rider> riders) {
    final u = ConvoyCamera.fitGroup(riders);
    if (u != null) unawaited(_map?.animateCamera(u));
  }

  @override
  void fitPoints(List<(double, double)> points) {
    if (points.length < 2) return;
    var s = points.first.$1, n = s, w = points.first.$2, e = w;
    for (final (la, ln) in points) {
      if (la < s) s = la;
      if (la > n) n = la;
      if (ln < w) w = ln;
      if (ln > e) e = ln;
    }
    unawaited(_map?.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)),
      80,
    )));
  }

  @override
  void focus(Rider r) {
    final u = ConvoyCamera.focus(r);
    if (u != null) unawaited(_map?.animateCamera(u));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = widget.data;
    final regroup = data.regroup;
    final plan = data.plan;
    return GoogleMap(
      polylines: {
        if (plan != null && plan.route.length >= 2)
          Polyline(
            polylineId: const PolylineId('route'),
            points: [for (final (la, ln) in plan.route) LatLng(la, ln)],
            width: 7,
            zIndex: 0,
            color: scheme.primary.withValues(alpha: plan.approximate ? 0.45 : 0.85),
            patterns: plan.approximate
                ? [PatternItem.dash(20), PatternItem.gap(14)]
                : const <PatternItem>[],
          ),
        for (final r in data.riders)
          if ((data.trails[r.id]?.length ?? 0) >= 2)
            Polyline(
              polylineId: PolylineId(r.id),
              points: [for (final p in data.trails[r.id]!) LatLng(p.lat, p.lng)],
              width: 4,
              color: (r.isLeader ? scheme.primary : scheme.secondary).withValues(alpha: 0.4),
            ),
      },
      onLongPress: widget.onLongPress == null
          ? null
          : (p) => widget.onLongPress!(p.latitude, p.longitude),
      initialCameraPosition: const CameraPosition(target: ConvoyCamera.fallbackCenter, zoom: 13),
      style: Theme.of(context).brightness == Brightness.dark ? _style : null,
      markers: {
        ..._markers,
        if (plan != null) ...[
          Marker(
            markerId: const MarkerId('trip_origin'),
            position: LatLng(plan.origin.lat, plan.origin.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: plan.origin.label),
          ),
          for (var i = 0; i < plan.stops.length; i++)
            Marker(
              markerId: MarkerId('trip_stop_$i'),
              position: LatLng(plan.stops[i].lat, plan.stops[i].lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
              infoWindow: InfoWindow(title: 'Stop ${i + 1}', snippet: plan.stops[i].label),
            ),
          Marker(
            markerId: const MarkerId('trip_destination'),
            position: LatLng(plan.destination.lat, plan.destination.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            infoWindow: InfoWindow(title: plan.destination.label),
          ),
        ],
        if (regroup != null)
          Marker(
            markerId: const MarkerId('regroup'),
            position: LatLng(regroup.lat, regroup.lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            infoWindow: InfoWindow(title: regroup.label),
          ),
      },
      myLocationEnabled: widget.showMyLocation,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: widget.padding,
      onMapCreated: (c) {
        _map = c;
        widget.onReady(this);
      },
    );
  }
}
