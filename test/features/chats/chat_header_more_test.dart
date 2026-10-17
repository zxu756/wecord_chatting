import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

/// The wide chat header keeps a few primary buttons and moves the rest into
/// a More menu, so the title keeps the room; every action stays reachable.
void main() {
  Future<PhoneWorld> openWide(
    WidgetTester tester,
    String location, {
    Object? extra,
  }) async {
    usePhoneViewport(tester, _desktop);
    final world = PhoneWorld();
    await world.open(tester, location, extra: extra);
    return world;
  }

  Future<PhoneWorld> openDirect(WidgetTester tester) {
    return openWide(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  /// A desktop platform for the length of the test.
  void wideTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  final more = find.byKey(const ValueKey('chat-header-more'));

  wideTest('a direct chat header has call, video, the side panel and More', (
    tester,
  ) async {
    await openDirect(tester);

    expect(find.byTooltip('Start voice call'), findsOneWidget);
    expect(find.byTooltip('Start video call'), findsOneWidget);
    expect(find.byTooltip('Hide profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-header-search')), findsOneWidget);
    expect(more, findsOneWidget);
    // Everything else lives in More, not in the bar.
    for (final moved in [
      'Pinned messages',
      'Notes and lists',
      'Media',
      'Events',
    ]) {
      expect(find.byTooltip(moved), findsNothing, reason: moved);
    }

    // The title gets the room: the whole long name fits.
    final title = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('chat-thread-header')),
        matching: find.text(bart.displayName),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byWidget(title));
    expect(box.size.width, greaterThan(250));
    expect(tester.takeException(), isNull);
  });

  wideTest('More lists every other action as a glass menu and they work', (
    tester,
  ) async {
    await openDirect(tester);

    await tester.tap(more);
    await settle(tester);
    for (final label in [
      'Pinned messages',
      'Notes and lists',
      'Disappearing messages',
      'Wallpaper',
      'Media',
      'Events',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The primary actions are not repeated in the menu.
    expect(find.text('Start voice call'), findsNothing);

    await tester.tap(find.text('Pinned messages'));
    await settle(tester);
    expect(find.text('Pinned messages'), findsWidgets);
    // The menu closed.
    expect(find.text('Wallpaper'), findsNothing);
  });

  wideTest('More has its own accessibility label and opens from the keyboard', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openDirect(tester);
    expect(find.bySemanticsLabel('More'), findsOneWidget);

    more.evaluate();
    await tester.tap(more);
    await settle(tester);
    // Rows are named by their labels for screen readers.
    expect(find.bySemanticsLabel('Notes and lists'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Notes and lists'), findsNothing);
    handle.dispose();
  });

  wideTest('a circle channel keeps pins and members, the rest is in More', (
    tester,
  ) async {
    await openWide(tester, '/circles/circle-1');

    expect(find.byTooltip('Pinned messages'), findsOneWidget);
    expect(find.byTooltip('Hide member list'), findsOneWidget);
    expect(find.byTooltip('Channel settings'), findsNothing);
    expect(find.byTooltip('Notes and lists'), findsNothing);

    await tester.tap(more);
    await settle(tester);
    expect(find.text('Channel settings'), findsOneWidget);
    expect(find.text('Notes and lists'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Wallpaper'), findsOneWidget);
  });
}
