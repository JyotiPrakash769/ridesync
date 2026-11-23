import 'package:material_ui/material_ui.dart';

import 'core/theme/app_theme.dart';

class RideSyncApp extends StatelessWidget {
  const RideSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const _ScaffoldPlaceholder(),
    );
  }
}

/// Phase 0 placeholder; replaced by the create/join flow in Phase 1.
class _ScaffoldPlaceholder extends StatelessWidget {
  const _ScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(child: Text('RideSync', style: text.headlineMedium)),
    );
  }
}
