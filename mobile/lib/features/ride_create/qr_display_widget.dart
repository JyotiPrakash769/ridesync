import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// QR (deep-link payload) + the ride ID as selectable text with a copy button.
class QrDisplayWidget extends StatelessWidget {
  const QrDisplayWidget({super.key, required this.rideId, required this.payload});

  final String rideId;
  final String payload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // QR codes need dark-on-light with a quiet zone to scan reliably,
        // so this one surface is pure white in both themes on purpose.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: payload,
            size: 220,
            semanticsLabel: 'QR code to join ride $rideId',
          ),
        ),
        const SizedBox(height: 20),
        Text('Ride code', style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SelectableText(
              rideId,
              style: text.displaySmall?.copyWith(letterSpacing: 6),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Copy ride code',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: rideId));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Ride code copied')));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.share),
          label: const Text('Share invite'),
          onPressed: () => SharePlus.instance.share(ShareParams(
            subject: 'Join my RideSync ride',
            text: 'Join my ride on RideSync! Code: $rideId\n$payload',
          )),
        ),
      ],
    );
  }
}
