// The "Share to WeCord" page (Android and ChromeOS share target), for the
// accessibility guard (guidelines_test.dart) and the accessibility screenshot
// tool. The iPad layouts are the app's existing screens at tablet sizes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/share_target/shared_content.dart';

import '../features/share_target/share_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

SharedContent _shared() {
  return SharedContent(
    title: 'How to make a good cup of tea',
    url: 'https://example.com/tea',
    files: [
      sharedFile('tea-menu.pdf', bytes: List.filled(240000, 0)),
      sharedFile('photo.jpg', mimeType: 'image/jpeg', bytes: [1, 2, 3]),
    ],
    skippedFiles: 2,
  );
}

Future<void> _open(
  WidgetTester tester,
  PhoneWorld world,
  SharedContent? content,
) async {
  world.extraOverrides = shareOverrides(FakeShareTargetGateway(content));
  await world.open(tester, '/share');
}

/// The screens, in the order of the flows.
final platformsA11yScreens = <A11yScreen>[
  A11yScreen('share-target', (tester, world) async {
    await _open(tester, world, _shared());
  }),
  A11yScreen('share-target-send-failed', (tester, world) async {
    await _open(tester, world, _shared());
    world.chats.sendError = StateError('down');
    await tester.tap(find.byKey(const ValueKey('share-target-dm-1')));
    await settle(tester);
  }),
  A11yScreen('share-target-empty', (tester, world) async {
    await _open(tester, world, null);
  }),
  A11yScreen(
    'share-target-desktop',
    (tester, world) async {
      await _open(tester, world, _shared());
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
