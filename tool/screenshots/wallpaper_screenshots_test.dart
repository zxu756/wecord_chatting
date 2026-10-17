// Renders chat wallpapers (the picker, every built-in in a chat, a photo, a
// channel) on a phone and a desktop, light and dark, with real fonts, and
// writes PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/wallpaper_screenshots_test.dart \
//     --dart-define=WALLPAPER_SCREENS_DIR=build/wallpapers
//
// Pick screens with --dart-define=WALLPAPER_ONLY=picker,presets,photo,channel.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_picker.dart';
import 'package:wecord/features/wallpapers/wallpaper_presets.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/wallpapers/wallpaper_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'WALLPAPER_SCREENS_DIR',
  defaultValue: 'build/wallpapers',
);
const _only = String.fromEnvironment('WALLPAPER_ONLY');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

class _Variant {
  const _Variant(this.name, this.viewport, this.dark);

  final String name;
  final PhoneViewport viewport;
  final bool dark;

  bool get desktop => viewport == _desktop;
}

const _variants = [
  _Variant('phone-light', notchedPhone, false),
  _Variant('phone-dark', notchedPhone, true),
  _Variant('desktop-light', _desktop, false),
  _Variant('desktop-dark', _desktop, true),
];

const _photoPath = 'user-1/00000000-0000-4000-8000-00000000f0f0.jpg';

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settleWithImages(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  final only = _only.isEmpty ? null : _only.split(',').toSet();

  void screen(
    String group,
    String name,
    ChatWallpaper? wallpaper,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      _Variant variant,
    )
    open, {
    List<String> variants = const [
      'phone-light',
      'phone-dark',
      'desktop-light',
      'desktop-dark',
    ],
  }) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      if (!variants.contains(variant.name)) {
        continue;
      }
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          final stores = WallpaperTestStores();
          stores.photos.photos[_photoPath] = samplePhotoBytes();
          if (wallpaper != null) {
            stores.repository.settings = WallpaperSettings(
              defaultWallpaper: wallpaper,
            );
            stores.cache.values['user-1'] = stores.repository.settings;
          }
          world.extraOverrides = stores.overrides;
          await open(tester, world, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(WidgetTester tester, PhoneWorld world) async {
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
    await settleWithImages(tester);
  }

  Future<void> openPicker(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(showWallpaperPicker(context, conversationId: 'dm-1'));
    await settleWithImages(tester);
  }

  // ----------------------------------------------------------- built-ins

  for (final preset in wallpaperPresets) {
    screen(
      'presets',
      'preset-${preset.id}',
      ChatWallpaper.preset(preset.id),
      (tester, world, variant) => openDirect(tester, world),
      // Desktop shows a few of them; the phone shows all.
      variants: const ['phone-light', 'phone-dark'],
    );
  }
  for (final id in ['dawn', 'dots', 'haze', 'sage']) {
    screen(
      'desktop',
      'preset-$id',
      ChatWallpaper.preset(id),
      (tester, world, variant) => openDirect(tester, world),
      variants: const ['desktop-light', 'desktop-dark'],
    );
  }

  // --------------------------------------------------------------- photo

  screen(
    'photo',
    'photo',
    const ChatWallpaper.photo(_photoPath),
    (tester, world, variant) => openDirect(tester, world),
  );
  screen(
    'photo',
    'photo-blur',
    const ChatWallpaper.photo(_photoPath, blur: true),
    (tester, world, variant) => openDirect(tester, world),
    variants: const ['phone-light', 'phone-dark'],
  );

  // -------------------------------------------------------------- picker

  screen('picker', 'picker-preset', const ChatWallpaper.preset('dawn'), (
    tester,
    world,
    variant,
  ) async {
    await openDirect(tester, world);
    await openPicker(tester);
  });
  screen('picker', 'picker-none', null, (tester, world, variant) async {
    await openDirect(tester, world);
    await openPicker(tester);
  }, variants: const ['phone-light', 'phone-dark']);
  screen(
    'picker',
    'picker-photo',
    const ChatWallpaper.photo(_photoPath, blur: true, focusX: 0.4),
    (tester, world, variant) async {
      await openDirect(tester, world);
      await openPicker(tester);
      await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    },
  );

  // --------------------------------------------------------------- group

  for (final entry in {
    'group-dusk': const ChatWallpaper.preset('dusk'),
    'group-photo': const ChatWallpaper.photo(_photoPath),
  }.entries) {
    screen('group', entry.key, entry.value, (tester, world, variant) async {
      world.chats.messages = richMessages(withThread: true);
      await world.open(
        tester,
        '${ChatsScreen.path}/group-1',
        extra: ChatThreadRouteExtra(
          title: groupDetail.title,
          type: ConversationType.group,
        ),
      );
      await settleWithImages(tester);
    }, variants: const ['phone-light', 'phone-dark']);
  }

  // ------------------------------------------------------------- channel

  screen('channel', 'channel', const ChatWallpaper.preset('lagoon'), (
    tester,
    world,
    variant,
  ) async {
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await settleWithImages(tester);
  });

  // ------------------------------------------------------------ settings

  screen('settings', 'settings', const ChatWallpaper.preset('sage'), (
    tester,
    world,
    variant,
  ) async {
    await world.open(tester, '/me');
    await settleWithImages(tester);
  }, variants: const ['phone-light', 'phone-dark']);
}
