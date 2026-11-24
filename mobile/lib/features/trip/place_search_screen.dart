import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip_plan.dart';
import '../../shared/widgets/error_text.dart';
import '../../state/ride_session_provider.dart';

/// Search a place (Google via the backend). Pops with a TripPlace.
class PlaceSearchScreen extends ConsumerStatefulWidget {
  const PlaceSearchScreen({
    super.key,
    required this.title,
    this.nearLat,
    this.nearLng,
    this.offerMyLocation = false,
  });

  final String title;
  final double? nearLat;
  final double? nearLng;

  /// Show a "My location" row (for the start point).
  final bool offerMyLocation;

  @override
  ConsumerState<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

/// Sentinel returned for "My location".
const TripPlace myLocationPlace = TripPlace(lat: double.nan, lng: double.nan, label: 'My location');

class _PlaceSearchScreenState extends ConsumerState<PlaceSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(text.trim()));
  }

  Future<void> _search(String q) async {
    final session = ref.read(rideSessionProvider);
    if (session == null) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(apiClientProvider).searchPlaces(session.rideId, session.auth, q,
          nearLat: widget.nearLat, nearLng: widget.nearLng);
      if (mounted && seq == _seq) setState(() => _results = r);
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('placeSearchField'),
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (t) => t.trim().length >= 2 ? _search(t.trim()) : null,
              decoration: InputDecoration(
                hintText: 'Search a place, town or landmark',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: InlineError(_error!)),
          Expanded(
            child: ListView(
              children: [
                if (widget.offerMyLocation)
                  ListTile(
                    minTileHeight: AppTokens.minTouch,
                    leading: Icon(Icons.my_location, color: scheme.primary),
                    title: const Text('My location'),
                    onTap: () => Navigator.pop(context, myLocationPlace),
                  ),
                for (final r in _results)
                  ListTile(
                    minTileHeight: AppTokens.minTouch,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(r.name),
                    subtitle: r.address.isEmpty
                        ? null
                        : Text(r.address, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(
                      context,
                      TripPlace(lat: r.lat, lng: r.lng, label: r.name),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
