// One-off demo: navigates to the Upload tab and taps the "Served To" field
// to show the picker sheet (Same as profile / John Doe / Jane Doe / New name).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_tracker/main.dart' as app;

Future<void> _settle(WidgetTester tester, {int pumps = 8}) async {
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo: Served To picker sheet', (tester) async {
    app.main();
    await _settle(tester, pumps: 12);

    final skipButton = find.text('Skip');
    if (skipButton.evaluate().isNotEmpty) {
      await tester.tap(skipButton);
      await _settle(tester, pumps: 6);
    }
    final demoButton = find.text('Demo');
    if (demoButton.evaluate().isNotEmpty) {
      await tester.tap(demoButton);
      await _settle(tester, pumps: 3);
      await tester.tap(find.text('Login'));
      await _settle(tester, pumps: 20);
    }
    await _settle(tester, pumps: 40);

    final uploadTab = find.text('Upload');
    if (uploadTab.evaluate().isNotEmpty) {
      await tester.tap(uploadTab.first);
      await _settle(tester, pumps: 15);
    }

    final servedToField = find.text('Select who was served');
    if (servedToField.evaluate().isNotEmpty) {
      await tester.tap(servedToField.first);
      await _settle(tester, pumps: 10);
    } else {
      // Might already have a value selected — try tapping the field label.
      final label = find.text('Served To');
      if (label.evaluate().isNotEmpty) {
        await tester.tap(label.first);
        await _settle(tester, pumps: 10);
      }
    }

    // ignore: avoid_print
    print('READY_FOR_SCREENSHOT_SERVED_TO');
    await _settle(tester, pumps: 300);
  });
}
