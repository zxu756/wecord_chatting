// Screen reader and keyboard behaviour of the shared controls and the chat:
// messages read as one sentence with actions, the context menu key opens a
// message's menu and Esc closes it, Ctrl+J jumps to the message box,
// presence and badges have words, high contrast swaps the theme, and
// animated pictures hold still under reduced motion.
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/message_semantics.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../features/chats/emoji_fixtures.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<void> _openThread(WidgetTester tester, PhoneWorld world) async {
  world.chats.messages = richMessages(withThread: true);
  await world.open(
    tester,
    '/chats/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

void main() {
  group('messages', () {
    testWidgets('read as one sentence with sender, time and reactions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      await _openThread(tester, world);

      await tester.drag(
        find.byKey(const ValueKey('chat-message-list')),
        const Offset(0, 700),
      );
      await settle(tester);
      // The quoted message with 131 reactions and a thread.
      final node = find.bySemanticsLabel(
        RegExp(
          r'^Bartholomew.*, \d+:\d\d(, Pinned)?: .*Shipping is a feature too.*, '
          r'131 reactions, 12 replies in thread$',
          dotAll: true,
        ),
      );
      expect(node, findsOneWidget);
      final data = tester.getSemantics(node).getSemanticsData();
      // Reply, Copy, Forward... and the reaction toggles come as actions.
      expect(data.customSemanticsActionIds, isNotEmpty);

      // The user's own message says "You", and that it was edited.
      expect(
        find.bySemanticsLabel(RegExp(r'^You, \d+:\d\d: .*, edited')),
        findsWidgets,
      );
      await world.close(tester);
      handle.dispose();
    });

    testWidgets('the context menu key opens the menu and Esc closes it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      await _openThread(tester, world);

      // Tab until a message has focus.
      for (var i = 0; i < 60; i++) {
        if (FocusManager.instance.primaryFocus?.debugLabel == 'message') {
          break;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final focused = FocusManager.instance.primaryFocus;
      expect(focused?.debugLabel, 'message');

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await settle(tester);
      expect(find.byType(GlassMenuPanel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(GlassMenuPanel), findsNothing);
      // Focus goes back to the message that opened it.
      expect(FocusManager.instance.primaryFocus, focused);

      // Shift+F10 does the same.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await settle(tester);
      expect(find.byType(GlassMenuPanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      await world.close(tester);
      handle.dispose();
    });

    testWidgets('Ctrl+J jumps to the message box', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        usePhoneViewport(tester, desktopViewport);
        final world = PhoneWorld();
        await world.open(
          tester,
          '/chats/dm-1',
          extra: ChatThreadRouteExtra(
            title: bart.displayName,
            type: ConversationType.direct,
          ),
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          isNot('message box'),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'message box');
        await world.close(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('image descriptions', () {
    test('use a readable file name, otherwise name the sender', () {
      expect(
        messageImageDescription('dm-1/sunset_over_bay.jpg', 'Ada'),
        'Image: sunset over bay',
      );
      expect(
        messageImageDescription(
          'dm-1/3f9a1c2e-77aa-4b1e-9d11-0a1b2c3d4e5f.jpg',
          'Ada',
        ),
        'Image from Ada',
      );
      expect(
        messageImageDescription('dm-1/IMG_0042.jpg', 'Ada'),
        'Image from Ada',
      );
    });
  });

  group('shared controls', () {
    Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? WeCordTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('badges, presence dots and switches have words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CountBadge(count: 150, tone: BadgeTone.unread),
              const CountBadge.dot(),
              PersonAvatar(
                name: 'Ada',
                presence: Colors.green,
                presenceLabel: 'Online',
              ),
              WeCordSwitch(
                value: true,
                onChanged: (_) {},
                semanticLabel: 'Glass effects',
              ),
              WeCordSegmented<int>(
                semanticLabel: 'Density',
                selected: 1,
                onChanged: (_) {},
                segments: const [
                  WeCordSegment(value: 0, label: 'Compact'),
                  WeCordSegment(value: 1, label: 'Default'),
                ],
              ),
            ],
          ),
        ),
      );
      // The real count is read, not "99+".
      expect(find.bySemanticsLabel('150 unread'), findsOneWidget);
      expect(find.bySemanticsLabel('Unread'), findsOneWidget);
      expect(find.bySemanticsLabel('Online'), findsOneWidget);
      final toggle = tester.getSemantics(
        find.bySemanticsLabel('Glass effects'),
      );
      final flags = toggle.getSemanticsData().flagsCollection;
      expect(flags.isToggled, isNot(Tristate.none));
      final selected = tester.getSemantics(find.text('Default'));
      expect(
        selected.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('small controls are padded to the touch target', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          WeCordButton(
            label: 'Accept',
            size: WeCordButtonSize.small,
            onPressed: () {},
          ),
        ),
      );
      // 32 tall to look at, 48 to tap on Android (what tests run as).
      expect(tester.getSize(find.byType(WeCordButton)).height, 48);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        host(
          WeCordButton(
            label: 'Accept',
            size: WeCordButtonSize.small,
            onPressed: () {},
          ),
          theme: WeCordTheme.light().copyWith(platform: TargetPlatform.macOS),
        ),
      );
      expect(tester.getSize(find.byType(WeCordButton)).height, 32);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('high contrast', () {
    testWidgets('the platform setting selects the high contrast tokens', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(highContrast: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      late WeCordTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          highContrastTheme: WeCordTheme.light(highContrast: true),
          home: Builder(
            builder: (context) {
              tokens = context.tokens;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(tokens.highContrast, isTrue);
      expect(tokens.colors.muted, WeCordPalette.lightHighContrast.muted);
    });
  });

  group('reduced motion', () {
    testWidgets('an animated picture holds still behind a play button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Scaffold(
              body: Center(
                child: MotionSafeImage(
                  image: MemoryImage(partyParrotPng),
                  width: 64,
                  height: 64,
                  semanticLabel: 'GIF',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.byTooltip('Play animation'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      await tester.tap(find.byTooltip('Play animation'));
      await tester.pump();
      expect(find.byTooltip('Play animation'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
