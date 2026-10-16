import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/message.dart';

import '../file_preview/file_preview_fakes.dart';
import 'chat_thread_screen_test.dart' as thread_test;
import 'paged_chat_fakes.dart';

/// A rough benchmark of the chat message list with a long conversation:
/// how long the first frame, scrolling frames, a new message and a typing
/// update take to build and lay out. Widget tests run in debug mode, so
/// the numbers compare runs with each other; they are not device timings.
///
/// Two set-ups: the whole conversation in memory (a repository without
/// paged history, as every chat was before), and paged history (the newest
/// 50 messages, older pages loading while scrolling up, realtime messages
/// merged into the loaded window).
void main() {
  const messageCount = 5000;

  String body(int index) => index % 7 == 0
      ? '**Update $index** with `code` and a _longer_ line of text '
            'that wraps over two lines on a phone'
      : 'Message number $index';
  final start = DateTime.utc(2026, 1, 1, 8);

  List<ChatMessage> longConversation() {
    return [
      for (var index = 0; index < messageCount; index++)
        ChatMessage(
          id: 'message-${index.toString().padLeft(5, '0')}',
          conversationId: 'conversation-1',
          senderId: index % 3 == 0 ? 'user-1' : 'user-${2 + index % 4}',
          type: MessageType.text,
          body: body(index),
          createdAt: start.add(Duration(minutes: index * 7)),
          reactions: index % 11 == 0
              ? const [MessageReaction(emoji: '👍', count: 2)]
              : const [],
        ),
    ];
  }

  List<Map<String, dynamic>> longConversationRows() {
    return [
      for (var index = 0; index < messageCount; index++)
        {
          ...messageRow(
            index,
            id: 'message-${index.toString().padLeft(5, '0')}',
            senderId: index % 3 == 0 ? 'user-1' : 'user-${2 + index % 4}',
            body: body(index),
            createdAt: start.add(Duration(minutes: index * 7)),
          ),
          'reactions': index % 11 == 0
              ? const [
                  {'emoji': '👍', 'count': 2},
                ]
              : const <Object?>[],
        },
    ];
  }

  Widget app(thread_test.FakeChatsRepository repository) {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(repository),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          thread_test.FakeSettingsRepository(),
        ),
        ...filePreviewOverrides(),
        authRepositoryProvider.overrideWithValue(
          thread_test.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: const MaterialApp(
        home: ChatThreadScreen(
          conversationId: 'conversation-1',
          title: 'Benchmark',
        ),
      ),
    );
  }

  String stats(String label, List<int> micros) {
    final sorted = [...micros]..sort();
    final mean = sorted.reduce((a, b) => a + b) / sorted.length;
    final p90 =
        sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    return '$label: mean ${(mean / 1000).toStringAsFixed(2)} ms, '
        'p90 ${(p90 / 1000).toStringAsFixed(2)} ms, '
        'max ${(sorted.last / 1000).toStringAsFixed(2)} ms '
        '(${sorted.length} frames)';
  }

  Future<void> benchmark(
    WidgetTester tester, {
    required String label,
    required thread_test.FakeChatsRepository repository,
    required Future<void> Function(int index) arrive,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final first = Stopwatch()..start();
    await tester.pumpWidget(app(repository));
    await tester.pump();
    await tester.pump();
    first.stop();
    expect(find.text('Message number 4999'), findsOneWidget);

    final list = find.byKey(const ValueKey('chat-message-list'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position;

    // Scroll up through the history a viewport at a time (older pages
    // load on the way with paged history).
    final scrollFrames = <int>[];
    for (var step = 0; step < 80; step++) {
      position.jumpTo(position.pixels + 420);
      final frame = Stopwatch()..start();
      await tester.pump();
      frame.stop();
      scrollFrames.add(frame.elapsedMicroseconds);
    }

    // Back at the latest message, new ones arrive.
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final arrivals = <int>[];
    for (var index = 0; index < 10; index++) {
      final frame = Stopwatch()..start();
      await arrive(index);
      frame.stop();
      arrivals.add(frame.elapsedMicroseconds);
    }
    expect(find.text('Fresh message 9'), findsOneWidget);

    // Someone starts and stops typing: the screen rebuilds.
    final typing = <int>[];
    for (var index = 0; index < 20; index++) {
      repository.emitActivity(
        ConversationActivity(
          typingUserIds: index.isEven ? const {'user-2'} : const {},
        ),
      );
      final frame = Stopwatch()..start();
      await tester.pump();
      frame.stop();
      typing.add(frame.elapsedMicroseconds);
    }

    debugPrint(
      [
        'Message list benchmark, $label ($messageCount messages):',
        '  first frame with messages: '
            '${(first.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms',
        '  ${stats('scroll frame', scrollFrames)}',
        '  ${stats('new message', arrivals)}',
        '  ${stats('typing update', typing)}',
      ].join('\n'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('scrolls $messageCount messages held in memory', (tester) async {
    final repository = thread_test.FakeChatsRepository()
      ..messages = longConversation();
    await benchmark(
      tester,
      label: 'whole conversation',
      repository: repository,
      arrive: (index) async {
        repository.messages = [
          ...repository.messages,
          ChatMessage(
            id: 'message-new-$index',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.text,
            body: 'Fresh message $index',
            createdAt: DateTime.utc(2027).add(Duration(minutes: index)),
          ),
        ];
        repository.emitMessageChange();
        await tester.pump();
        await tester.pump();
      },
    );
  });

  testWidgets('scrolls $messageCount messages in pages', (tester) async {
    final repository = PagedChatsRepository()..rows = longConversationRows();
    await benchmark(
      tester,
      label: 'paged history',
      repository: repository,
      arrive: (index) async {
        final id = 'message-new-$index';
        repository.rows = [
          ...repository.rows,
          messageRow(
            index,
            id: id,
            body: 'Fresh message $index',
            createdAt: DateTime.utc(2027).add(Duration(minutes: index)),
          ),
        ];
        repository.emit(
          ThreadEvent(ThreadEventKind.messageInserted, messageId: id),
        );
        // The realtime batch window, then the frame.
        await tester.pump(const Duration(milliseconds: 70));
        await tester.pump();
      },
    );
  });
}
