import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core/config/env.dart';
import 'core/deep_links.dart';
import 'core/location/background_task.dart';
import 'core/storage/local_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  TrackingService.init();
  await LocalDb.init();
  final app = ProviderScope(child: RideSyncApp(deepLinks: DeepLinks()));
  if (Env.sentryDsn.isEmpty) {
    runApp(app);
    return;
  }
  // Crash reports only: no screenshots, no user data (positions/tokens stay on device).
  await SentryFlutter.init(
    (o) {
      o.dsn = Env.sentryDsn;
      o.sendDefaultPii = false;
      o.tracesSampleRate = 0;
    },
    appRunner: () => runApp(app),
  );
}
