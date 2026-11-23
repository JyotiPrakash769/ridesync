import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../state/settings.dart';

Future<void> showSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SettingsSheet(),
    );

/// Theme, handlebar mode and alert preferences.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: text.titleLarge),
            const SizedBox(height: 16),
            Text('Theme', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(minimumSize: const Size(0, AppTokens.minTouch)),
              segments: const [
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                ButtonSegment(
                    value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Phone')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => n.update((x) => x.copyWith(themeMode: v.single)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.wb_sunny),
              title: const Text('Handlebar mode'),
              subtitle: const Text('Bigger text and stronger contrast for sunlight and phone mounts'),
              value: s.handlebarMode,
              onChanged: (v) => n.update((x) => x.copyWith(handlebarMode: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.record_voice_over),
              title: const Text('Spoken alerts'),
              subtitle: const Text('Say "Ravi is falling behind" out loud'),
              value: s.voiceAlerts,
              onChanged: (v) => n.update((x) => x.copyWith(voiceAlerts: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.vibration),
              title: const Text('Vibrate on alerts'),
              value: s.vibrationAlerts,
              onChanged: (v) => n.update((x) => x.copyWith(vibrationAlerts: v)),
            ),
          ],
        ),
      ),
    );
  }
}
