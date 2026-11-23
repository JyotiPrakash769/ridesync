import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'core/deep_links.dart';
import 'core/location/background_task.dart';
import 'core/storage/local_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  TrackingService.init();
  await LocalDb.init();
  runApp(ProviderScope(child: RideSyncApp(deepLinks: DeepLinks())));
}
