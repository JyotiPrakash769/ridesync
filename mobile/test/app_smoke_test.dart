import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/app.dart';

void main() {
  testWidgets('app boots with M3 dark theme', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RideSyncApp()));
    expect(find.text('RideSync'), findsOneWidget);
  });
}
