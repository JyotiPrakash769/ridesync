import 'package:url_launcher/url_launcher.dart';

import '../../models/trip_plan.dart';

/// Hands turn-by-turn navigation to Google Maps (two-wheeler mode), falling
/// back to the web URL if the Maps app isn't installed.
Future<bool> navigateWithGoogleMaps(TripPlace to) async {
  final app = Uri.parse('google.navigation:q=${to.lat},${to.lng}&mode=l');
  try {
    if (await launchUrl(app, mode: LaunchMode.externalApplication)) return true;
  } catch (_) {}
  final web = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${to.lat},${to.lng}',
    'travelmode': 'two-wheeler',
  });
  return launchUrl(web, mode: LaunchMode.externalApplication);
}

/// Where "Navigate" should go: the next stop ahead, else the destination.
TripPlace navigationTarget(TripPlan plan, TripPlace? nextStop) => nextStop ?? plan.destination;
