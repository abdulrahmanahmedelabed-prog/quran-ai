// Screenshots the main screens on a real device, emulator or simulator:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/emulator_tour_test.dart -d <device>
// Screenshots are written to app/screenshots/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'tour.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen tour', (tester) async {
    final setup = await tourServices();
    var surfaceReady = !Platform.isAndroid;
    await runTour(
      tester,
      setup: setup,
      shot: (name) async {
        if (!surfaceReady) {
          // Android renders to a surface that must be switched to an image
          // before screenshots can be taken.
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          surfaceReady = true;
        }
        await binding.takeScreenshot(name);
      },
      settle: () async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await tester.pump();
        }
      },
    );
  });
}
