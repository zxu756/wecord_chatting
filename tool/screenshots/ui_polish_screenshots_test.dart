// Renders the screens of the second UI polish pass (Settings truncation,
// group chat headers, the circle menu, the desktop chat header, badge
// colors, Saved on phones) for before/after comparison. Not part of
// `flutter test`; run it with:
//
//   flutter test tool/screenshots/ui_polish_screenshots_test.dart \
//     --dart-define=POLISH_DIR=build/polish/before
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (files end in
// -dark instead of -light) and --dart-define=PHONE_SCREENS_ZH=true for
// Chinese (-zh).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'POLISH_DIR',
  defaultValue: 'build/polish/after',
);

const _suffix =
    '${bool.fromEnvironment('PHONE_SCREENS_DARK') ? '-dark' : '-light'}'
    '${bool.fromEnvironment('PHONE_SCREENS_ZH') ? '-zh' : ''}';

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

const _desktopLargeText = PhoneViewport(
  name: 'desktop text 1.3',
  size: Size(1440, 900),
  devicePixelRatio: 1,
  textScale: 1.3,
);

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name$_suffix.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  /// One screen as `<prefix>-<name>`; the prefix says which viewport.
  void screen(
    String name,
    PhoneViewport viewport,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    final wide = viewport.size.width > 800;
    final prefix = wide ? 'desktop' : 'phone';
    final scale = viewport.textScale == 1 ? '' : '-text13';
    testWidgets('$prefix $name$scale', (tester) async {
      if (wide) {
        // The Chinese font fallback of the screenshot fonts is the Windows
        // one.
        debugDefaultTargetPlatformOverride =
            const bool.fromEnvironment('PHONE_SCREENS_ZH')
            ? TargetPlatform.windows
            : TargetPlatform.macOS;
      }
      try {
        usePhoneViewport(tester, viewport);
        final world = PhoneWorld();
        await open(tester, world);
        await shoot(tester, '$prefix-$name$scale');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  void phone(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) => screen(name, notchedPhone, open);

  void phoneLarge(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) => screen(name, notchedPhoneLargeText, open);

  void desktop(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) => screen(name, _desktop, open);

  Future<void> openDm(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  Future<void> openGroup(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/group-1',
      extra: ChatThreadRouteExtra(
        title: groupDetail.title,
        type: ConversationType.group,
      ),
    );
  }

  Future<void> openChannel(
    WidgetTester tester,
    PhoneWorld world, {
    required bool wide,
  }) async {
    world.chats.messages = richMessages(withThread: true);
    await world.open(tester, '/circles/circle-1');
    if (!wide) {
      await tester.tap(find.text('general').first);
      await settle(tester);
    }
  }

  Future<void> openCircleMenu(WidgetTester tester, PhoneWorld world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip(tr('Circle menu')));
    await settle(tester);
  }

  Future<void> scrollSettingsTo(WidgetTester tester, String text) async {
    final finder = find.text(tr(text)).first;
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.6);
    await settle(tester);
  }

  // Settings (item 1).
  phone('settings', (tester, world) async {
    await world.open(tester, '/me');
  });
  phone('settings-appearance', (tester, world) async {
    await world.open(tester, '/me');
    await scrollSettingsTo(tester, 'Density');
  });
  phoneLarge('settings-appearance', (tester, world) async {
    await world.open(tester, '/me');
    await scrollSettingsTo(tester, 'Density');
  });
  Future<void> windowSection(
    WidgetTester tester,
    PhoneWorld world,
    String section,
  ) async {
    await world.open(tester, '/me');
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('settings-nav-$section')));
  }

  for (final section in [
    'profile',
    'privacy',
    'appearance',
    'voice',
    'ai',
    'chats',
    'notifications',
    'shortcuts',
    'language',
  ]) {
    desktop('settings-$section', (tester, world) async {
      await windowSection(tester, world, section);
    });
    screen('settings-$section', _desktopLargeText, (tester, world) async {
      await windowSection(tester, world, section);
    });
  }

  // Headers (items 2 and 4).
  phone('dm-header', openDm);
  phone('group-header', openGroup);
  phone('circle-channel', (tester, world) async {
    await openChannel(tester, world, wide: false);
  });
  desktop('dm-header', openDm);
  desktop('group-header', openGroup);
  desktop('circle-channel', (tester, world) async {
    await openChannel(tester, world, wide: true);
  });

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('chat-header-more')));
    await settle(tester);
  }

  desktop('dm-header-more', (tester, world) async {
    await openDm(tester, world);
    await openMore(tester);
  });
  desktop('circle-channel-more', (tester, world) async {
    await openChannel(tester, world, wide: true);
    await openMore(tester);
  });

  // A channel without a topic.
  phone('circle-channel-notopic', (tester, world) async {
    world.chats.messages = richMessages();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.text('announcements').first);
    await settle(tester);
  });
  desktop('circle-channel-notopic', (tester, world) async {
    world.chats.messages = richMessages();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.text('announcements').first);
    await settle(tester);
  });

  // The circle menu (items 3 and 5).
  phone('circle-menu', openCircleMenu);
  desktop('circle-menu', openCircleMenu);
  phone('circle-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip(tr('Circle menu')));
    await settle(tester);
    await tester.ensureVisible(find.text(tr('Circle settings')));
    await tester.tap(find.text(tr('Circle settings')));
  });

  // Badges and Saved (items 6 and 7).
  phone('home', (tester, world) async {
    await world.open(tester, '/home');
  });
  phone('circle-home', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  });
  phone('inbox', (tester, world) async {
    await world.open(tester, '/notifications');
  });
  desktop('sidebar', (tester, world) async {
    await world.open(tester, '/home');
  });
  desktop('circle-sidebar', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  });
}
