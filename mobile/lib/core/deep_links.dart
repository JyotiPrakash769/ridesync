import 'dart:async';

import 'package:app_links/app_links.dart';

import 'ride_id.dart';

/// Emits ride IDs from incoming join links (https://ridesync.app/join/{id}
/// or ridesync://join/{id}), including the link that launched the app.
class DeepLinks {
  DeepLinks({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  Stream<String> get rideIds => _appLinks.uriLinkStream
      .map((uri) => parseRideIdFromLink(uri.toString()))
      .where((id) => id != null)
      .cast<String>();
}
