// Drives the running app end-to-end via the Dart VM service (no OS-level
// tap/click needed — works in headless environments). Verifies the recent
// batch of UI changes: consolidated Home/Map nav, the upload flow (File
// Number, Priority Level, Successful Attempt, Serve To picker), the Log
// filter sheet, and the Earnings hero split.
//
// NOTE: this app has a continuously-pulsing "current location" marker on
// the map, so `pumpAndSettle()` never sees zero pending frames and times
// out after its internal 10-minute ceiling. Every wait below uses a
// bounded number of fixed pumps instead.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_tracker/main.dart' as app;

/// Pumps a fixed number of frames instead of pumpAndSettle (which never
/// converges while the map's location-pulse animation keeps repeating).
Future<void> _settle(WidgetTester tester, {int pumps = 8}) async {
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Dismisses a one-off AlertDialog by its action-button text, if present.
/// Used for dialogs that only appear conditionally (resume-draft prompt,
/// nearby-pin prompt) depending on what's already in local storage / nearby
/// the simulator's default location.
Future<void> _dismissIfPresent(WidgetTester tester, String buttonText) async {
  final finder = find.text(buttonText);
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first);
    await _settle(tester, pumps: 5);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nav, upload, log, and earnings reflect the latest changes',
      (tester) async {
    app.main();
    await _settle(tester, pumps: 12); // splash (2s) + first route

    // Fresh install/test run — no persisted auth, so onboarding + login
    // show first. Skip onboarding, then log in with the demo credentials.
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
      // Login + first-login permission requests + route to the map.
      await _settle(tester, pumps: 20);
    }

    // Splash holds 2s, then GPS stabilization takes ~3-4s before the map
    // (now the Home tab) finishes its first load — give this generous room.
    await _settle(tester, pumps: 40);

    // ── Bottom nav: Home + Map consolidated into a single Home tab ──
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Earnings'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Map'), findsNothing);

    // ── Upload tab ──
    // The "Upload" label in the bottom nav is a plain, non-tappable Text —
    // the actual nav trigger is the circular FAB icon above it.
    await tester.tap(find.byIcon(Icons.upload_rounded));
    // Upload's initState re-fetches GPS (~3-4s to stabilize) and then
    // fires a nearby-pin check against the live backend — give this the
    // same generous room as the initial app load.
    await _settle(tester, pumps: 40);

    // A resume-draft prompt or nearby-pin prompt may fire depending on
    // simulator state — clear either so the form below is reachable.
    await _dismissIfPresent(tester, 'Discard');
    await _settle(tester, pumps: 10);
    await _dismissIfPresent(tester, 'New Pin');
    await _settle(tester, pumps: 10);

    expect(find.text('File Number'), findsOneWidget);
    expect(find.text('Priority Level'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    expect(find.text('Successful Attempt'), findsOneWidget);

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    final successfulSwitch = tester.widget<Switch>(switchFinder);
    expect(successfulSwitch.value, isTrue,
        reason: 'Successful Attempt must default to true');

    // Pay Rate must exist as its own section (moved out from Details).
    expect(find.text('Pay Rate (\$)'), findsOneWidget);

    // ── Serve To picker ──
    final servedToRow = find.text('Select who was served');
    expect(servedToRow, findsOneWidget);
    await tester.ensureVisible(servedToRow);
    await _settle(tester, pumps: 3);
    await tester.tap(servedToRow);
    await _settle(tester, pumps: 8);

    expect(find.text('Same as profile'), findsOneWidget);
    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('New name'), findsOneWidget);

    // Picking a specific name should require Relation To.
    await tester.tap(find.text('John Doe'));
    await _settle(tester, pumps: 5);
    expect(find.text('Relation To'), findsOneWidget);

    // Picking "Same as profile" should NOT require Relation To.
    await tester.tap(find.text('John Doe').hitTestable().first);
    await _settle(tester, pumps: 8);
    await tester.tap(find.text('Same as profile'));
    await _settle(tester, pumps: 5);
    expect(find.text('Relation To'), findsNothing);

    // Toggling Successful Attempt off hides Served To (and Relation To).
    await tester.tap(switchFinder);
    await _settle(tester, pumps: 5);
    expect(find.text('Served To'), findsNothing);
    expect(find.text('Relation To'), findsNothing);
    // Restore it so we don't leave the form in a weird state.
    await tester.tap(switchFinder);
    await _settle(tester, pumps: 5);

    // ── Log tab ──
    await tester.tap(find.text('Log'));
    await _settle(tester, pumps: 15);

    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
    await _settle(tester, pumps: 8);
    expect(find.text('PRIORITY LEVEL'), findsOneWidget);
    expect(find.text('SERVICE TYPE'), findsNothing);

    // Close the filter sheet before switching tabs.
    await tester.tapAt(const Offset(50, 50));
    await _settle(tester, pumps: 5);

    // ── Earnings tab ──
    await tester.tap(find.text('Earnings'));
    await _settle(tester, pumps: 15);
    expect(find.text('Total Earnings'), findsOneWidget);
    expect(find.text('Total Available Earnings'), findsOneWidget);

    // ── Home tab shows the map (not the old feed) with View List/Fit All ──
    await tester.tap(find.text('Home').first);
    await _settle(tester, pumps: 15);
    expect(find.text('Fit All'), findsOneWidget);
    expect(find.text('View List'), findsOneWidget);
  });
}
