// Personal stickers, for the accessibility guard (guidelines_test.dart) and
// the accessibility screenshot tool: a chat with stickers in it, the "Mine"
// tab of the sticker picker, "Add to stickers" and the cut-out, and the My
// stickers page.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/stickers/sticker_management_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../features/stickers/sticker_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// Lets the images of a screen load: they come from memory, decoding takes
/// real time.
Future<void> _letImagesLoad(WidgetTester tester) async {
  for (var round = 0; round < 5; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

/// A short library: two still stickers and a moving one.
List<Override> _stickerWorld(
  PhoneWorld world, {
  bool empty = false,
  bool cutoutAvailable = true,
}) {
  final library = FakeUserStickersRepository(
    empty
        ? []
        : [
            userSticker('s1', sortKey: 1),
            userSticker('s2', animated: true, sortKey: 2),
            userSticker('s3', sortKey: 3),
            userSticker('s4', sortKey: 4),
            userSticker('s5', sortKey: 5),
          ],
  );
  library.files['dm-1/photo.png'] = samplePhotoPng();
  return [
    ...stickerOverrides(
      library,
      cutout: FakeStickerCutout(available: cutoutAvailable),
    ),
    chatImageProviderFactoryProvider.overrideWithValue(
      (url) => MemoryImage(samplePhotoPng(width: 600, height: 400)),
    ),
  ];
}

Future<void> _openChat(
  WidgetTester tester,
  PhoneWorld world, {
  bool empty = false,
  bool cutoutAvailable = true,
}) async {
  world.chats.messages = [
    phoneMessage('m0', bart, 'Look what I found', minutesAgo: 30),
    phoneMessage(
      'm1',
      bart,
      '',
      minutesAgo: 28,
      type: MessageType.image,
      attachment: const {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'dm-1/photo.png',
        'mime_type': 'image/png',
        'size': 1024,
        'width': 600,
        'height': 400,
      },
    ),
    phoneMessage(
      'm2',
      bart,
      '',
      minutesAgo: 20,
      type: MessageType.sticker,
      attachment: const {
        'kind': 'sticker',
        'personal': true,
        'bucket': 'chat-images',
        'path': 'dm-1/sticker-1.png',
        'mime_type': 'image/png',
        'width': 256,
        'height': 256,
        'animated': false,
      },
    ),
    phoneMessage('m3', me, 'Ha! Stealing that one', minutesAgo: 10),
  ];
  world.extraOverrides = _stickerWorld(
    world,
    empty: empty,
    cutoutAvailable: cutoutAvailable,
  );
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
  await _letImagesLoad(tester);
}

Future<void> _openPicker(
  WidgetTester tester,
  PhoneWorld world, {
  bool empty = false,
  bool circlesTab = false,
}) async {
  await _openChat(tester, world, empty: empty);
  await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
  await settle(tester);
  await tester.tap(find.text('Send sticker'));
  await settle(tester);
  if (circlesTab) {
    await tester.tap(find.byKey(const ValueKey('sticker-tab-circles')));
    await settle(tester);
  }
  await _letImagesLoad(tester);
}

Future<void> _longPressPhoto(WidgetTester tester) async {
  final photo = find.byType(Image).first;
  if (debugDefaultTargetPlatformOverride == TargetPlatform.macOS) {
    await tester.tap(photo, buttons: kSecondaryButton);
  } else {
    await tester.longPress(photo);
  }
  await settle(tester);
}

Future<void> _openAddSheet(
  WidgetTester tester,
  PhoneWorld world, {
  bool cutout = false,
  bool cutoutAvailable = true,
}) async {
  await _openChat(tester, world, cutoutAvailable: cutoutAvailable);
  await _longPressPhoto(tester);
  await tester.tap(find.byKey(const ValueKey('message-add-to-stickers')));
  await _letImagesLoad(tester);
  if (cutout) {
    await tester.tap(find.byKey(const ValueKey('add-sticker-cutout-switch')));
    await _letImagesLoad(tester);
  }
  await settle(tester);
}

Future<void> _openManagement(
  WidgetTester tester,
  PhoneWorld world, {
  bool empty = false,
}) async {
  await pumpStandalone(
    tester,
    world,
    const StickerManagementScreen(),
    extraOverrides: _stickerWorld(world, empty: empty),
  );
  await _letImagesLoad(tester);
}

final stickersA11yScreens = <A11yScreen>[
  A11yScreen('stickers-in-chat', (tester, world) => _openChat(tester, world)),
  A11yScreen('sticker-picker-mine', _openPicker),
  A11yScreen(
    'sticker-picker-mine-empty',
    (tester, world) => _openPicker(tester, world, empty: true),
  ),
  A11yScreen(
    'sticker-picker-circles',
    (tester, world) => _openPicker(tester, world, circlesTab: true),
  ),
  A11yScreen('message-menu-add-to-stickers', (tester, world) async {
    await _openChat(tester, world);
    await _longPressPhoto(tester);
  }),
  A11yScreen('add-to-stickers-sheet', _openAddSheet),
  A11yScreen(
    'add-to-stickers-sheet-cut-out',
    (tester, world) => _openAddSheet(tester, world, cutout: true),
  ),
  A11yScreen(
    'add-to-stickers-sheet-no-cut-out',
    (tester, world) => _openAddSheet(tester, world, cutoutAvailable: false),
  ),
  A11yScreen('my-stickers-page', _openManagement),
  A11yScreen(
    'my-stickers-page-empty',
    (tester, world) => _openManagement(tester, world, empty: true),
  ),
  A11yScreen(
    'sticker-picker-mine-desktop',
    _openPicker,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'add-to-stickers-sheet-desktop',
    (tester, world) => _openAddSheet(tester, world, cutout: true),
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'my-stickers-page-desktop',
    _openManagement,
    viewport: desktopViewport,
    desktop: true,
  ),
];
