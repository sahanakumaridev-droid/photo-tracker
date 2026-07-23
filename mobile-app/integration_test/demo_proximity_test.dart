// One-off demo script (not part of the regular test suite): drives the app
// to (1) the main Upload tab's profile picker and (2) the map-tap upload
// sheet's profile picker, holding at each so an external
// `xcrun simctl io booted screenshot` can capture the "Nearby · within 1 mi"
// section live. Prints a marker line each time it's ready to be
// screenshotted, so the driving shell script can wait on that instead of
// guessing timing. Requires the simulator's simulated GPS location to be set
// near a real profile (see `xcrun simctl location <device> set <lat>,<lng>`)
// or the Nearby section will legitimately be empty.
import 'package:flutter/material.dart';
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

  testWidgets('demo: show Nearby · within 1 mi on both profile pickers',
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

    // ── 1) Main Upload tab profile picker ──
    await tester.tap(find.byIcon(Icons.upload_rounded));
    await _settle(tester, pumps: 40);

    await _dismissIfPresent(tester, 'Discard');
    await _settle(tester, pumps: 10);
    await _dismissIfPresent(tester, 'New Pin');
    await _settle(tester, pumps: 10);

    final profileRow = find.text('Select a profile');
    if (profileRow.evaluate().isNotEmpty) {
      await tester.ensureVisible(profileRow);
      await _settle(tester, pumps: 3);
      await tester.tap(profileRow);
      await _settle(tester, pumps: 8);
    }

    // ignore: avoid_print
    print('READY_FOR_SCREENSHOT_1_MAIN_UPLOAD');
    await _settle(tester, pumps: 25);

    // Close the picker sheet, then go back to the map (Home tab).
    await tester.tapAt(const Offset(50, 100));
    await _settle(tester, pumps: 5);
    await tester.tap(find.text('Home').first);
    await _settle(tester, pumps: 20);

    // ── 2) Map-tap upload sheet's profile picker ──
    final mapFinder = find.byType(FlutterMap);
    if (mapFinder.evaluate().isNotEmpty) {
      final center = tester.getCenter(mapFinder.first);
      await tester.tapAt(center);
      await _settle(tester, pumps: 15);

      // ignore: avoid_print
      print('READY_FOR_SCREENSHOT_2_MAP_TAP');
      await _settle(tester, pumps: 25);
    } else {
      // ignore: avoid_print
      print('NO_MAP_FOUND');
    }
  });
}
