import 'package:material_ui/material_ui.dart';

import '../../core/network/api_client.dart';

/// User-facing copy for API failures. 404 and 410 get distinct messages.
String apiErrorMessage(Object e, {String? rideId}) {
  if (e is ApiException) {
    return switch (e.kind) {
      ApiErrorKind.notFound => rideId == null
          ? 'Ride not found. Check the code and try again.'
          : 'No ride with code $rideId. Check the code and try again.',
      ApiErrorKind.gone => 'This ride has ended.',
      ApiErrorKind.forbidden => 'Only the ride leader can do that.',
      ApiErrorKind.invalid => 'That doesn\'t look right. Check and try again.',
      ApiErrorKind.network => 'Can\'t reach RideSync. Check your connection.',
      ApiErrorKind.server => 'Something went wrong on our side. Try again.',
    };
  }
  return 'Something went wrong. Try again.';
}

/// Inline error line with an icon (never color alone).
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
