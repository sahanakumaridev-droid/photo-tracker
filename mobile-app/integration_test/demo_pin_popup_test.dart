// One-off demo: taps the existing Del Rio pin (simulator GPS is set to its
// exact coordinates) and opens "+ Add Photo" to show the profile dropdown's
// nearby-first sort + 📍 marker on a real device.
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_tracker/main.dart' as app;

Future<void> _settle(WidgetTester tester, {int pumps = 8}) async {
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _dismissIfPresent(WidgetTester tester, String buttonText) async {
  final finder = find.text(buttonText);
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first);
    await _settle(tester, pumps: 5);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo: pin popup Add Photo dropdown shows nearby marker',
      (tester) async {
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

    final mapFinder = find.byType(FlutterMap);
    if (mapFinder.evaluate().isNotEmpty) {
      final center = tester.getCenter(mapFinder.first);
      await tester.tapAt(center);
      await _settle(tester, pumps: 15);
    }

    await _dismissIfPresent(tester, 'Discard');
    await _settle(tester, pumps: 5);

    final addPhoto = find.text('+ Add Photo');
    if (addPhoto.evaluate().isNotEmpty) {
      await tester.tap(addPhoto.first);
      await _settle(tester, pumps: 10);
    }

    // ignore: avoid_print
    print('READY_FOR_SCREENSHOT_PIN_POPUP');
    await _settle(tester, pumps: 25);
  });
}
