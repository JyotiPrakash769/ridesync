import 'package:material_ui/material_ui.dart';

import '../../shared/widgets/centered_form.dart';
import '../ride_create/create_ride_screen.dart';
import '../ride_join/join_ride_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return CenteredForm(
      children: [
        Icon(Icons.two_wheeler, size: 64, color: scheme.primary),
        const SizedBox(height: 16),
        Text('RideSync', style: text.displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          'Ride together. See your whole convoy live.',
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const CreateRideScreen())),
          icon: const Icon(Icons.add_road),
          label: const Text('Create a ride'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const JoinRideScreen())),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Join a ride'),
        ),
      ],
    );
  }
}
