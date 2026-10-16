// Renders the screens touched by the UI polish pass (sheets, composer
// hints, swipe to reply, previews, drafts, the call strip and the file
// viewer) on a phone (390x844) and a 1440x900 desktop with real fonts, for
// eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/polish_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/polish
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/polish',
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
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
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  /// Shoots [name] on the phone and (unless [desktop] is false) on the
  /// desktop, as `phone-<name>` and `desktop-<name>`.
  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world, bool desktop)
    open, {
    bool phone = true,
    bool desktop = true,
  }) {
    if (phone) {
      testWidgets('phone $name', (tester) async {
        usePhoneViewport(tester, notchedPhone);
        final world = PhoneWorld();
        await open(tester, world, false);
        await shoot(tester, 'phone-$name');
      });
    }
    if (desktop) {
      testWidgets('desktop $name', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(tester, _desktop);
          final world = PhoneWorld();
          await open(tester, world, true);
          await shoot(tester, 'desktop-$name');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openThread(
    WidgetTester tester,
    PhoneWorld world, {
    String id = 'dm-1',
    String? title,
    ConversationType type = ConversationType.direct,
  }) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/$id',
      extra: ChatThreadRouteExtra(title: title ?? bart.displayName, type: type),
    );
  }

  Future<void> openPolls(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = pollMessages();
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.byKey(const ValueKey('chat-message-list'));
    await tester.drag(list, const Offset(0, -5000));
    await tester.pump();
    for (var step = 0; step < 40 && finder.evaluate().isEmpty; step++) {
      await tester.drag(list, const Offset(0, 150));
      await tester.pump();
    }
    await Scrollable.ensureVisible(
      tester.element(finder.first),
      alignment: 0.5,
    );
    await settle(tester);
  }

  Future<void> openMessageMenu(
    WidgetTester tester,
    String text,
    bool desktop,
  ) async {
    final message = find.textContaining(text, findRichText: true);
    await reveal(tester, message);
    if (desktop) {
      await tester.tap(message.first, buttons: 2);
    } else {
      await tester.longPress(message.first);
    }
    await settle(tester);
  }

  // 1. Sheets.
  screen('sheet-pinned', (tester, world, desktop) async {
    await openThread(tester, world);
    if (desktop) {
      await tester.tap(find.byTooltip('Pinned messages'));
    } else {
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Pinned messages'));
    }
  });

  screen('sheet-forward', (tester, world, desktop) async {
    await openThread(tester, world);
    await openMessageMenu(tester, 'Forwarding', desktop);
    await tester.tap(find.text('Forward'));
  });

  screen('sheet-reactors', (tester, world, desktop) async {
    await openThread(tester, world);
    final chip = find.byKey(const ValueKey('reaction-chip-😂'));
    await reveal(tester, chip);
    await tester.longPress(chip);
  });

  screen('sheet-emoji', (tester, world, desktop) async {
    await openThread(tester, world);
    await openMessageMenu(tester, 'Also this', desktop);
    await tester.tap(find.byTooltip('More reactions'));
  });

  screen('sheet-poll-voters', (tester, world, desktop) async {
    await openPolls(tester, world);
    world.chats.pollVoters = {
      'o1': [bart, grace],
      'o2': [me, bart, grace, linus],
    };
    final viewVotes = find.byKey(const ValueKey('poll-view-votes-poll-open'));
    await Scrollable.ensureVisible(tester.element(viewVotes), alignment: 0.5);
    await settle(tester);
    await tester.tap(viewVotes);
  });

  screen('sheet-group-details', (tester, world, desktop) async {
    await openThread(
      tester,
      world,
      id: 'group-1',
      title: groupDetail.title,
      type: ConversationType.group,
    );
    await tester.tap(find.byTooltip('Group details'));
  });

  screen('sheet-new-group', (tester, world, desktop) async {
    await world.open(tester, ChatsScreen.path);
    if (desktop) {
      await tester.tap(find.byTooltip('New group'));
    } else {
      await tester.tap(find.byKey(const ValueKey('phone-home-new')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-new-group')));
    }
  });

  // 2. Composer hints.
  screen('composer-direct', (tester, world, desktop) async {
    await openThread(tester, world);
  });

  screen('composer-channel', (tester, world, desktop) async {
    world.chats.messages = richMessages(withThread: true);
    if (desktop) {
      await world.open(tester, '/circles/circle-1');
    } else {
      await world.open(
        tester,
        '/circles/circle-1/channels/conv-general',
        extra: const ChatThreadRouteExtra(
          title: '# general',
          type: ConversationType.channel,
          circleId: 'circle-1',
        ),
      );
    }
  });

  screen('composer-group', (tester, world, desktop) async {
    await openThread(
      tester,
      world,
      id: 'group-1',
      title: groupDetail.title,
      type: ConversationType.group,
    );
  }, desktop: false);
  // 3. Swipe to reply, held past the threshold.
  screen('swipe-to-reply', (tester, world, desktop) async {
    await openThread(tester, world);
    final incoming = find.textContaining('Forwarding this one');
    await reveal(tester, incoming);
    final gesture = await tester.startGesture(tester.getCenter(incoming));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(16, 0));
      await tester.pump();
    }
    addTearDown(gesture.up);
  }, desktop: false);

  // MARKER: more screens
}
