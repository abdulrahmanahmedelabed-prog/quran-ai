// Runs the emulator tour (integration_test/tour.dart) headlessly, so it is
// checked on every test run before it reaches a device.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/tour.dart';

void main() {
  testWidgets('tour reaches every screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final shots = <String>[];
    await runTour(
      tester,
      setup: (await tester.runAsync(tourServices))!,
      shot: (name) async => shots.add(name),
      settle: () async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
      // Leaving the recitation page disposes the audio player, which has no
      // platform implementation in widget tests.
      visitPaywall: false,
    );
    expect(shots, ['01_home', '02_reciting', '03_summary', '04_margin', '05_margin_sheet']);
  });
}
