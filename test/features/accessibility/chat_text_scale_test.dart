import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/accessibility/chat_text_scale.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';

void main() {
  test('sizes snap to the nearest option, and the middle one is no change', () {
    expect(nearestChatTextScale(1.0), 1.0);
    expect(nearestChatTextScale(1.2), 1.15);
    expect(nearestChatTextScale(5), 1.5);
    expect(nearestChatTextScale(0), chatTextScaleOptions.first);
    expect(chatTextSizeName(1.0), 'Default');
    expect(chatTextSizeName(1.5), 'Largest');
  });

  testWidgets('adds to the size the system already asks for', (tester) async {
    final store = InMemoryChatTextScaleStore(1.3);
    double? seen;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatTextScaleStoreProvider.overrideWithValue(store)],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ChatTextScale(
            child: Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context).scale(10);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // 10 × 2 (system) × 1.3 (chat).
    expect(seen, closeTo(26, 0.001));
  });

  testWidgets('the default size leaves the text alone', (tester) async {
    double? seen;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatTextScaleStoreProvider.overrideWithValue(
            InMemoryChatTextScaleStore(),
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: ChatTextScale(
            child: Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context).scale(10);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(seen, closeTo(16, 0.001));
  });

  testWidgets('the slider changes the size and remembers it', (tester) async {
    final store = InMemoryChatTextScaleStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatTextScaleStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: ChatTextSizeRow()),
        ),
      ),
    );
    expect(find.text('Default'), findsOneWidget);

    // Two steps right: Larger.
    final slider = tester.getRect(find.byKey(ChatTextSizeRow.sliderKey));
    await tester.tapAt(Offset(slider.right - 24, slider.center.dy));
    await tester.pumpAndSettle();

    expect(store.factor, 1.5);
    expect(find.text('Largest'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatTextSizeRow)),
    );
    expect(container.read(chatTextScaleProvider), 1.5);
  });

  testWidgets('messages in a chat grow with it; the header does not', (
    tester,
  ) async {
    Future<(Size, Size)> sizes(double factor) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld()
        ..extraOverrides = [
          chatTextScaleStoreProvider.overrideWithValue(
            InMemoryChatTextScaleStore(factor),
          ),
        ];
      world.chats.messages = [
        phoneMessage(
          'm1',
          bart,
          'Dinner at seven works for me, shall we meet at the station?',
          minutesAgo: 5,
        ),
      ];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      await settle(tester);
      final message = tester.getSize(
        find.textContaining('Dinner at seven', findRichText: true).first,
      );
      final header = tester.getSize(find.text(bart.displayName).first);
      await world.close(tester);
      return (message, header);
    }

    final normal = await sizes(1.0);
    final larger = await sizes(1.5);

    expect(larger.$1.height, greaterThan(normal.$1.height * 1.3));
    expect(larger.$2.height, normal.$2.height);
  });
}
