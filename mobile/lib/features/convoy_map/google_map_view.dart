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
    required this.riders,
    required this.onReady,
    required this.padding,
    required this.showMyLocation,
  });

  final List<Rider> riders;
  final ValueChanged<ConvoyMapHandle> onReady;
  final EdgeInsets padding;
  final bool showMyLocation;

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
    if (!identical(old.riders, widget.riders)) unawaited(_rebuild());
  }

  Future<void> _rebuild() async {
    final factory = _factory;
    if (factory == null) return;
    final next = <Marker>{};
    for (final r in widget.riders) {
      if (!r.hasPosition) continue;
      next.add(Marker(
        markerId: MarkerId(r.id),
        position: LatLng(r.lat!, r.lng!),
        icon: await factory.build(name: r.name, leader: r.isLeader),
        anchor: RiderMarkerFactory.anchorFor(),
        alpha: r.status == RiderStatus.offline ? 0.5 : 1,
        zIndexInt: r.isLeader ? 2 : 1,
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
  void focus(Rider r) {
    final u = ConvoyCamera.focus(r);
    if (u != null) unawaited(_map?.animateCamera(u));
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: const CameraPosition(target: ConvoyCamera.fallbackCenter, zoom: 13),
      style: Theme.of(context).brightness == Brightness.dark ? _style : null,
      markers: _markers,
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
