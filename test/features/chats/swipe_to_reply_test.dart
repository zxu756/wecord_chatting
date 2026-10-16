import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/swipe_to_reply.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';

void main() {
  late List<String> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// A list of rows; row 3 swipes to reply. It has a plain header over a
  /// horizontal scroller (like a code block) and reacts to long presses.
  Future<
    ({
      List<int> replies,
      List<int> longPresses,
      ScrollController list,
      ScrollController inner,
    })
  >
  pump(WidgetTester tester, {bool towardsEnd = true}) async {
    final replies = <int>[];
    final longPresses = <int>[];
    final list = ScrollController();
    final inner = ScrollController();
    addTearDown(list.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(
          body: ListView(
            controller: list,
            children: [
              for (var i = 0; i < 12; i++)
                if (i == 3)
                  SwipeToReply(
                    key: const ValueKey('swipe'),
                    towardsEnd: towardsEnd,
                    onReply: () => replies.add(i),
                    child: GestureDetector(
                      onLongPress: () => longPresses.add(i),
                      child: Column(
                        children: [
                          Container(
                            key: const ValueKey('header'),
                            height: 50,
                            color: Colors.green,
                          ),
                          SizedBox(
                            height: 80,
                            child: SingleChildScrollView(
                              key: const ValueKey('inner'),
                              controller: inner,
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (var j = 0; j < 20; j++)
                                    Container(
                                      width: 90,
                                      height: 80,
                                      color: j.isEven
                                          ? Colors.red
                                          : Colors.blue,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SizedBox(height: 120, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    return (
      replies: replies,
      longPresses: longPresses,
      list: list,
      inner: inner,
    );
  }

  Offset messageOffset(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('swipe-reply-message')),
    );
    final t = transform.transform.getTranslation();
    return Offset(t.x, t.y);
  }

  testWidgets('swiping right past the threshold replies and springs back', (
    tester,
  ) async {
    final world = await pump(tester);
    final start = tester.getCenter(find.byKey(const ValueKey('header')));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    // The reply icon grows in as the message moves.
    expect(find.byKey(const ValueKey('swipe-reply-icon')), findsOneWidget);
    expect(messageOffset(tester).dx, greaterThan(0));
    expect(haptics, isEmpty);

    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.selectionClick']);
    expect(messageOffset(tester).dx, lessThanOrEqualTo(SwipeToReply.maxOffset));

    await gesture.up();
    await tester.pump();
    expect(world.replies, [3]);
    await tester.pumpAndSettle();
    expect(messageOffset(tester).dx, closeTo(0, 0.5));
    expect(find.byKey(const ValueKey('swipe-reply-icon')), findsNothing);
    // The inner scroller didn't move.
    expect(world.inner.offset, 0);
  });

  testWidgets('a short swipe springs back without replying', (tester) async {
    final world = await pump(tester);
    final start = tester.getCenter(find.byKey(const ValueKey('header')));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(world.replies, isEmpty);
    expect(haptics, isEmpty);
    expect(messageOffset(tester).dx, closeTo(0, 0.5));
  });

  testWidgets('own messages swipe left', (tester) async {
    final world = await pump(tester, towardsEnd: false);
    final finder = find.byKey(const ValueKey('header'));
    await tester.timedDrag(
      finder,
      const Offset(-120, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(world.replies, [3]);
  });

  testWidgets('the other direction scrolls the message content instead', (
    tester,
  ) async {
    final world = await pump(tester);
    await tester.drag(
      find.byKey(const ValueKey('inner')),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    expect(world.replies, isEmpty);
    expect(world.inner.offset, greaterThan(100));

    // Scrolled in, a right drag scrolls back rather than replying.
    final before = world.inner.offset;
    await tester.drag(
      find.byKey(const ValueKey('inner')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(world.inner.offset, lessThan(before));
    expect(world.replies, isEmpty);
  });

  testWidgets('vertical drags scroll the list', (tester) async {
    final world = await pump(tester);
    await tester.drag(
      find.byKey(const ValueKey('swipe')),
      const Offset(30, -200),
    );
    await tester.pumpAndSettle();
    expect(world.list.offset, greaterThan(100));
    expect(world.replies, isEmpty);
  });

  testWidgets('long presses still work', (tester) async {
    final world = await pump(tester);
    await tester.longPress(find.byKey(const ValueKey('swipe')));
    await tester.pumpAndSettle();
    expect(world.longPresses, [3]);
    expect(world.replies, isEmpty);
  });

  testWidgets('touches at the screen edge are left to the back swipe', (
    tester,
  ) async {
    final world = await pump(tester);
    final row = tester.getRect(find.byKey(const ValueKey('header')));
    await tester.timedDragFrom(
      Offset(SwipeToReply.edgeGuard / 2, row.center.dy),
      const Offset(150, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    expect(world.replies, isEmpty);
  });

  phoneTestWidgets('swiping a message in a chat starts a reply', (
    tester,
    viewport,
  ) async {
    final world = PhoneWorld();
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
    final incoming = find.textContaining('Forwarding this one');
    final list = find.byKey(const ValueKey('chat-message-list'));
    for (var step = 0; step < 30 && incoming.evaluate().isEmpty; step++) {
      await tester.drag(list, const Offset(0, 150));
      await tester.pump();
    }
    await Scrollable.ensureVisible(tester.element(incoming), alignment: 0.5);
    await settle(tester);

    // Own messages don't reply when swiped right.
    final own = find.textContaining('Also this', findRichText: true);
    if (own.evaluate().isNotEmpty) {
      await tester.timedDrag(
        own.first,
        const Offset(140, 0),
        const Duration(milliseconds: 300),
      );
      await settle(tester);
      expect(find.textContaining('Replying to'), findsNothing);
    }

    await tester.timedDrag(
      incoming,
      const Offset(140, 0),
      const Duration(milliseconds: 300),
    );
    await settle(tester);
    expect(find.textContaining('Replying to'), findsOneWidget);
  }, viewports: const [notchedPhone]);
}
