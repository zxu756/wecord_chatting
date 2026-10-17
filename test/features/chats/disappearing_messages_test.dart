import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/disappearing_messages.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

class _FakeDisappearing implements DisappearingRepository {
  _FakeDisappearing([this.seconds]);

  int? seconds;
  final changes = <int?>[];
  var fail = false;

  @override
  Future<int?> timer(String conversationId) async => seconds;

  @override
  Future<void> setTimer(String conversationId, int? value) async {
    if (fail) {
      throw StateError('offline');
    }
    changes.add(value);
    seconds = value;
  }
}

ChatMessage _text(
  String id,
  String body, {
  DateTime? expiresAt,
  String senderId = 'user-2',
  int minute = 0,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.text,
    body: body,
    createdAt: DateTime.utc(2026, 10, 17, 9, minute),
    expiresAt: expiresAt,
  );
}

class _World {
  _World({
    ConversationType type = ConversationType.direct,
    String? role,
    int? seconds,
  }) : timer = _FakeDisappearing(seconds) {
    chats.conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: type,
        unreadCount: 0,
        title: 'Ada',
      ),
    ];
    if (type == ConversationType.group) {
      chats.groupDetail = GroupDetail(
        conversationId: 'conversation-1',
        title: 'Ada',
        members: const [],
        currentUserRole: role,
      );
    }
  }

  final chats = chat_fakes.FakeChatsRepository();
  final _FakeDisappearing timer;

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        disappearingRepositoryProvider.overrideWithValue(timer),
        // A test that lets real time pass would reach for the microphone.
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
      child: const MaterialApp(
        home: ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  test('labels the timers', () {
    expect(disappearingChoices.map(disappearingLabel), [
      'Off',
      '24 hours',
      '7 days',
      '90 days',
    ]);
    expect(disappearingShortLabel(86400), '24h');
    expect(disappearingShortLabel(7776000), '90d');
    final now = DateTime.utc(2026, 10, 17, 9);
    expect(
      disappearsInLabel(now.add(const Duration(seconds: 20)), now: now),
      'Disappearing now',
    );
    expect(
      disappearsInLabel(now.add(const Duration(minutes: 7)), now: now),
      'Disappears in 7m',
    );
    expect(
      disappearsInLabel(now.add(const Duration(hours: 5)), now: now),
      'Disappears in 5h',
    );
    expect(
      disappearsInLabel(now.add(const Duration(days: 3)), now: now),
      'Disappears in 3d',
    );
    expect(
      disappearingNoticeText(604800, 'Ada'),
      'Ada set messages to disappear after 7 days.',
    );
    expect(
      disappearingNoticeText(0, 'Ada'),
      'Ada turned off disappearing messages.',
    );
  });

  test('messages read their expiry and the notice', () {
    final message = ChatMessage.fromJson({
      'id': 'm',
      'conversation_id': 'c',
      'sender_id': 'u',
      'type': 'text',
      'body': 'hi',
      'created_at': '2026-10-17T09:00:00Z',
      'expires_at': '2026-10-18T09:00:00Z',
    });
    expect(message.expiresAt, DateTime.utc(2026, 10, 18, 9));
    expect(message.isDisappearing, isTrue);
    final notice = ChatMessage.fromJson({
      'id': 'n',
      'conversation_id': 'c',
      'sender_id': 'u',
      'type': 'system',
      'body': 'Ada set messages to disappear after 24 hours.',
      'created_at': '2026-10-17T09:00:00Z',
      'attachment': {'kind': 'disappearing', 'seconds': 86400},
    });
    expect(notice.disappearingNoticeSeconds, 86400);
    expect(notice.isDisappearing, isFalse);
  });

  testWidgets('expired messages are gone, live ones show a timer', (
    tester,
  ) async {
    final world = _World(seconds: 86400)
      ..chats.messages = [
        _text(
          'old',
          'Already gone',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
        _text(
          'live',
          'Still here',
          minute: 1,
          expiresAt: DateTime.now().toUtc().add(
            const Duration(hours: 5, minutes: 30),
          ),
        ),
        _text('plain', 'Stays forever', minute: 2),
      ];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Already gone'), findsNothing);
    expect(find.text('Still here'), findsOneWidget);
    expect(find.text('Stays forever'), findsOneWidget);
    expect(find.text('Disappears in 5h'), findsOneWidget);
    expect(find.byKey(const ValueKey('disappearing-mark')), findsOneWidget);
  });

  testWidgets('a message disappears from the open chat when its time comes', (
    tester,
  ) async {
    final world = _World(seconds: 86400)
      ..chats.messages = [
        _text(
          'live',
          'Going soon',
          expiresAt: DateTime.now().toUtc().add(
            const Duration(milliseconds: 2500),
          ),
        ),
      ];
    await tester.pumpWidget(world.app());
    await tester.pump();
    expect(find.text('Going soon'), findsOneWidget);

    // The clock is the real one; the timer is the test's.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2700)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Going soon'), findsNothing);
  });

  testWidgets('the header shows the timer, the sheet changes it', (
    tester,
  ) async {
    final world = _World(seconds: 604800)..chats.messages = [_text('a', 'Hi')];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-thread-timer')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('24 hours'), findsOneWidget);
    expect(find.text('90 days'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('90 days'));
    await tester.pumpAndSettle();
    expect(world.timer.changes, [7776000]);
    expect(find.byType(WeCordSheet), findsNothing);
  });

  testWidgets('turning it off from the sheet', (tester) async {
    final world = _World(seconds: 86400)..chats.messages = [_text('a', 'Hi')];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(world.timer.changes, [null]);
    expect(find.byKey(const ValueKey('chat-thread-timer')), findsNothing);
  });

  testWidgets('group members who are not admins only read it', (tester) async {
    final world = _World(type: ConversationType.group, role: 'member')
      ..chats.messages = [_text('a', 'Hi')];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Only the owner and admins can change this.'),
      findsOneWidget,
    );
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(world.timer.changes, isEmpty);
  });

  testWidgets('group admins can set it', (tester) async {
    final world = _World(type: ConversationType.group, role: 'admin')
      ..chats.messages = [_text('a', 'Hi')];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(world.timer.changes, [604800]);
  });

  testWidgets('a failed change stays open with a message', (tester) async {
    final world = _World()
      ..timer.fail = true
      ..chats.messages = [_text('a', 'Hi')];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disappearing-error')), findsOneWidget);
    expect(find.byType(WeCordSheet), findsOneWidget);
  });

  testWidgets('the system line reads in the reader\'s language', (
    tester,
  ) async {
    final world = _World(seconds: 86400)
      ..chats.messages = [
        ChatMessage(
          id: 'notice',
          conversationId: 'conversation-1',
          senderId: 'user-2',
          type: MessageType.system,
          body: 'Ada set messages to disappear after 24 hours.',
          createdAt: DateTime.utc(2026, 10, 17, 9),
          attachment: const {
            'kind': 'disappearing',
            'seconds': 86400,
            'actor_name': 'Ada',
          },
        ),
      ];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Ada set messages to disappear after 24 hours.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.timer_outlined), findsWidgets);
  });
}
