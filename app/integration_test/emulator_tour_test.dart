// Screenshots the main screens on a real device, emulator, simulator or
// desktop:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/emulator_tour_test.dart -d <device>
// Mobile screenshots go through the driver to app/screenshots/. On desktop,
// where the driver can't capture the screen, the app writes them itself to
// --dart-define=SCREENSHOT_DIR (default: screenshots/ in the working dir).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'tour.dart';

const _desktopShotDir = String.fromEnvironment('SCREENSHOT_DIR', defaultValue: 'screenshots');

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

Future<void> _saveDesktopShot(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(Offset.zero & view.size, pixelRatio: view.flutterView.devicePixelRatio);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  File('$_desktopShotDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screen tour', (tester) async {
    final setup = await tourServices();
    var surfaceReady = !Platform.isAndroid;
    await runTour(
      tester,
      setup: setup,
      shot: (name) async {
        if (!_isMobile) return _saveDesktopShot(tester, name);
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
