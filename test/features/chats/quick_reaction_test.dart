import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/quick_reaction.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

ChatMessage _text(
  String id,
  String body, {
  List<MessageReaction> reactions = const [],
  DateTime? recalledAt,
  MessageType type = MessageType.text,
  int minute = 0,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: 'user-2',
    type: type,
    body: body,
    createdAt: DateTime.utc(2026, 10, 17, 9, minute),
    reactions: reactions,
    recalledAt: recalledAt,
  );
}

class _World {
  _World({String? saved}) : store = InMemoryQuickReactionStore(saved) {
    chats.conversations = const [
      ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.group,
        unreadCount: 0,
        title: 'Friends',
      ),
    ];
  }

  final chats = chat_fakes.FakeChatsRepository();
  final InMemoryQuickReactionStore store;

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        quickReactionStoreProvider.overrideWithValue(store),
        voiceMessageRecorderProvider.overrideWithValue(
          chat_fakes.FakeVoiceMessageRecorder(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          chat_fakes.FakeSettingsRepository(),
        ),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        authRepositoryProvider.overrideWithValue(
          chat_fakes.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}

Future<void> _load(WidgetTester tester, _World world) async {
  await tester.pumpWidget(world.app());
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a double tap adds the quick reaction, with a pop', (
    tester,
  ) async {
    final world = _World()..chats.messages = [_text('m1', 'Hello there')];
    await _load(tester, world);

    final bubble = find.text('Hello there');
    await tester.tap(bubble);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(bubble);
    await tester.pump(const Duration(milliseconds: 100));

    expect(world.chats.toggledReactions, [('m1', '👍')]);
    expect(find.byKey(const ValueKey('quick-reaction-pop')), findsOneWidget);
    // The pop leaves again.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('quick-reaction-pop')), findsNothing);
  });

  testWidgets('uses the emoji chosen in settings', (tester) async {
    final world = _World(saved: '🎉')..chats.messages = [_text('m1', 'Hi')];
    await _load(tester, world);
    await tester.pump();

    await tester.tap(find.text('Hi'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Hi'));
    await tester.pump();
    expect(world.chats.toggledReactions, [('m1', '🎉')]);
  });

  testWidgets('one tap, or two far apart, does nothing', (tester) async {
    final world = _World()..chats.messages = [_text('m1', 'Hello there')];
    await _load(tester, world);

    await tester.tap(find.text('Hello there'));
    await tester.pump(const Duration(seconds: 1));
    expect(world.chats.toggledReactions, isEmpty);
    await tester.tap(find.text('Hello there'));
    await tester.pump(const Duration(seconds: 1));
    expect(world.chats.toggledReactions, isEmpty);
  });

  testWidgets('a reaction already made is not taken back', (tester) async {
    final world = _World()
      ..chats.messages = [
        _text(
          'm1',
          'Hello there',
          reactions: const [
            MessageReaction(emoji: '👍', count: 1, reactedByMe: true),
          ],
        ),
      ];
    await _load(tester, world);

    await tester.tap(find.text('Hello there'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Hello there'));
    await tester.pump();
    expect(world.chats.toggledReactions, isEmpty);
  });

  testWidgets('deleted messages and system lines take none', (tester) async {
    final world = _World()
      ..chats.messages = [
        _text('m1', '', recalledAt: DateTime.utc(2026, 10, 17, 10)),
        _text(
          'm2',
          'Ada pinned a message.',
          type: MessageType.system,
          minute: 1,
        ),
      ];
    await _load(tester, world);

    for (final label in ['Message deleted', 'Ada pinned a message.']) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(world.chats.toggledReactions, isEmpty);
  });

  testWidgets('long press still opens the menu', (tester) async {
    final world = _World()..chats.messages = [_text('m1', 'Hello there')];
    await _load(tester, world);

    await tester.longPress(find.text('Hello there'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(world.chats.toggledReactions, isEmpty);
  });

  testWidgets('a double click with a mouse works too', (tester) async {
    final world = _World()..chats.messages = [_text('m1', 'Hello there')];
    await _load(tester, world);

    final center = tester.getCenter(find.text('Hello there'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 2; i++) {
      await mouse.down(center);
      await mouse.up();
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(world.chats.toggledReactions, [('m1', '👍')]);
  });

  testWidgets('dragging between two taps is not a double tap', (tester) async {
    final world = _World()..chats.messages = [_text('m1', 'Hello there')];
    await _load(tester, world);

    final center = tester.getCenter(find.text('Hello there'));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, 40));
    await gesture.up();
    await tester.pump();
    expect(world.chats.toggledReactions, isEmpty);
  });

  testWidgets('with reduced motion there is no pop, but the reaction lands', (
    tester,
  ) async {
    final world = _World()..chats.messages = [_text('m1', 'Hello there')];
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: world.app(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Hello there'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Hello there'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(world.chats.toggledReactions, [('m1', '👍')]);
    expect(find.byKey(const ValueKey('quick-reaction-pop')), findsNothing);
  });

  group('settings', () {
    testWidgets('shows the current emoji and picks another', (tester) async {
      final store = InMemoryQuickReactionStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [quickReactionStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(body: QuickReactionSettingsGroup()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('👍'), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-reaction-reset')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('quick-reaction-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🤔').first);
      await tester.pumpAndSettle();
      expect(await store.load(), '🤔');
      expect(
        find.byKey(const ValueKey('quick-reaction-reset')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('quick-reaction-reset')));
      await tester.pump();
      expect(await store.load(), '👍');
    });
  });
}
