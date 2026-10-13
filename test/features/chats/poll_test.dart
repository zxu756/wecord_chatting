import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/profile.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

ChatMessage pollMessage({
  String id = 'poll-1',
  String senderId = 'user-2',
  bool multi = false,
  DateTime? endsAt,
  PollResults? results,
  DateTime? recalledAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.poll,
    body: 'Lunch?',
    createdAt: DateTime.utc(2026, 10, 13, 9),
    recalledAt: recalledAt,
    attachment: {
      'kind': 'poll',
      'question': 'Lunch?',
      'options': [
        {'id': 'o1', 'text': 'Pizza'},
        {'id': 'o2', 'text': 'Sushi'},
        {'id': 'o3', 'text': 'Tacos'},
      ],
      'multi': multi,
      'ends_at': endsAt?.toIso8601String(),
    },
    pollResults:
        results ??
        const PollResults(
          counts: {'o1': 1, 'o2': 3},
          totalVoters: 4,
          myVotes: {'o2'},
        ),
  );
}

void main() {
  group('models', () {
    test('parse poll attachments and results', () {
      final message = ChatMessage.fromJson({
        'id': 'poll-1',
        'conversation_id': 'conversation-1',
        'sender_id': 'user-2',
        'type': 'poll',
        'body': 'Lunch?',
        'created_at': '2026-10-13T09:00:00Z',
        'attachment': {
          'kind': 'poll',
          'question': 'Lunch?',
          'options': [
            {'id': 'o1', 'text': 'Pizza'},
            {'id': 'o2', 'text': 'Sushi'},
            {'id': 7, 'text': 'broken'},
          ],
          'multi': true,
          'ends_at': '2026-10-14T09:00:00Z',
        },
        'poll_results': {
          'counts': {'o1': 2, 'o2': 1},
          'total_voters': 2,
          'my_votes': ['o1'],
          'closed': false,
        },
      });

      expect(message.type, MessageType.poll);
      final poll = message.pollAttachment!;
      expect(poll.question, 'Lunch?');
      expect(poll.options.map((option) => option.text), ['Pizza', 'Sushi']);
      expect(poll.multi, isTrue);
      expect(poll.endsAt, DateTime.utc(2026, 10, 14, 9));
      expect(poll.hasEndedAt(DateTime.utc(2026, 10, 14, 9)), isTrue);
      expect(poll.hasEndedAt(DateTime.utc(2026, 10, 14, 8)), isFalse);
      final results = message.pollResults!;
      expect(results.countFor('o1'), 2);
      expect(results.countFor('o3'), 0);
      expect(results.shareOf('o1'), 1);
      expect(results.shareOf('o2'), 0.5);
      expect(results.myVotes, {'o1'});
      expect(MessageType.poll.toJson(), 'poll');
      expect(const PollResults().shareOf('o1'), 0);
    });

    test('labels durations, endings and previews', () {
      expect(pollDurationHours.map(pollDurationLabel), [
        'No end',
        '1 hour',
        '4 hours',
        '8 hours',
        '1 day',
        '3 days',
        '7 days',
      ]);
      final now = DateTime.utc(2026, 10, 13, 9);
      expect(
        pollEndsInLabel(now.add(const Duration(seconds: 30)), now: now),
        'Ending',
      );
      expect(
        pollEndsInLabel(now.add(const Duration(minutes: 5)), now: now),
        'Ends in 5m',
      );
      expect(
        pollEndsInLabel(now.add(const Duration(hours: 3)), now: now),
        'Ends in 3h',
      );
      expect(
        pollEndsInLabel(now.add(const Duration(days: 2)), now: now),
        'Ends in 2d',
      );
      expect(pollPreviewText(' Lunch? '), '📊 Poll: Lunch?');
      expect(pollPreviewText(''), '📊 Poll');
    });

    test('thread search matches poll options', () {
      final repository = SupabaseChatsRepository.withDataSource(
        _NoDataSource(),
        currentUserId: () => 'user-1',
      );
      final matches = repository.searchThreadMessages([pollMessage()], 'tacos');
      expect(matches.map((message) => message.id), ['poll-1']);
    });
  });

  group('poll bubble', () {
    testWidgets('shows shares, my vote, voters and the end', (tester) async {
      final world = _World()
        ..chats.messages = [
          pollMessage(
            endsAt: DateTime.now().toUtc().add(
              const Duration(hours: 3, minutes: 5),
            ),
          ),
        ];
      await tester.pumpWidget(world.app());
      await tester.pump();

      expect(find.text('Lunch?'), findsOneWidget);
      expect(find.text('Select one answer'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('4 votes · Ends in 3h'), findsOneWidget);
      expect(find.text('View votes'), findsOneWidget);
      expect(find.text('End poll'), findsNothing, reason: 'not the author');
    });

    testWidgets('tapping options votes, again withdraws', (tester) async {
      final world = _World()..chats.messages = [pollMessage()];
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('poll-option-poll-1-o1')));
      await tester.pump();
      expect(world.chats.pollVotes.last.$1, 'poll-1');
      expect(world.chats.pollVotes.last.$2, ['o1']);

      // Until the thread reloads with new results, the bubble shows the
      // vote just made; tapping it again withdraws it.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('poll-option-poll-1-o1')));
      await tester.pump();
      expect(world.chats.pollVotes.last.$1, 'poll-1');
      expect(world.chats.pollVotes.last.$2, <String>[]);
    });

    testWidgets('multiple-answer polls toggle each option', (tester) async {
      final world = _World()..chats.messages = [pollMessage(multi: true)];
      await tester.pumpWidget(world.app());
      await tester.pump();

      expect(find.text('Select one or more answers'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('poll-option-poll-1-o3')));
      await tester.pump();
      expect(world.chats.pollVotes.last.$1, 'poll-1');
      expect(world.chats.pollVotes.last.$2, ['o2', 'o3']);
    });

    testWidgets('closed polls take no votes', (tester) async {
      final world = _World()
        ..chats.messages = [
          pollMessage(
            senderId: 'user-1',
            results: const PollResults(
              counts: {'o1': 1},
              totalVoters: 1,
              closed: true,
            ),
          ),
        ];
      await tester.pumpWidget(world.app());
      await tester.pump();

      expect(find.text('Final results'), findsOneWidget);
      expect(find.text('1 vote · Closed'), findsOneWidget);
      expect(find.text('End poll'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('poll-option-poll-1-o2')));
      await tester.pump();
      expect(world.chats.pollVotes, isEmpty);
    });

    testWidgets('a past end closes the poll without waiting for results', (
      tester,
    ) async {
      final world = _World()
        ..chats.messages = [
          pollMessage(
            endsAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
          ),
        ];
      await tester.pumpWidget(world.app());
      await tester.pump();

      expect(find.text('4 votes · Closed'), findsOneWidget);
    });

    testWidgets('authors end their polls after confirming', (tester) async {
      final world = _World()
        ..chats.messages = [pollMessage(senderId: 'user-1')];
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.tap(find.text('End poll'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('poll-end-confirm')));
      await tester.pumpAndSettle();
      expect(world.chats.endedPolls, ['poll-1']);
    });

    testWidgets('moderators may end others\' polls', (tester) async {
      final world = _World()
        ..chats.messages = [pollMessage()]
        ..chats.canModeratePollsValue = true;
      await tester.pumpWidget(world.app());
      await tester.pump();

      expect(find.text('End poll'), findsOneWidget);
    });

    testWidgets('view votes lists voters per option', (tester) async {
      final world = _World()
        ..chats.messages = [pollMessage()]
        ..chats.pollVoters = {
          'o1': [_profile('user-3', 'grace', 'Grace Hopper')],
          'o2': [_profile('user-2', 'ada', 'Ada Lovelace')],
        };
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.tap(find.text('View votes'));
      await tester.pumpAndSettle();
      expect(find.text('Votes'), findsOneWidget);
      expect(find.text('Pizza (1)'), findsOneWidget);
      expect(find.text('Grace Hopper'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('poll-voters-option-o2')));
      await tester.pumpAndSettle();
      expect(find.text('@ada'), findsOneWidget);
      expect(find.text('Grace Hopper'), findsNothing);
    });

    testWidgets('polls cannot be forwarded or copied', (tester) async {
      final world = _World()..chats.messages = [pollMessage()];
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.longPress(find.text('Lunch?'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('replies quote the poll question', (tester) async {
      final world = _World()..chats.messages = [pollMessage()];
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.longPress(find.text('Lunch?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to 📊 Poll: Lunch?'), findsOneWidget);
    });
  });

  group('poll composer', () {
    Future<void> openFromAttach(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create poll'));
      await tester.pumpAndSettle();
    }

    testWidgets('posts a poll with its answers, choice and duration', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();
      await openFromAttach(tester);

      expect(find.text('Create poll'), findsWidgets);
      await tester.enterText(
        find.byKey(const ValueKey('poll-question-field')),
        ' Where to? ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-0')),
        'Beach',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-1')),
        'Hills',
      );
      await tester.tap(find.byKey(const ValueKey('poll-add-option')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-2')),
        'Home',
      );
      await tester.tap(find.byKey(const ValueKey('poll-multi-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('poll-duration-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 days').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-post-button')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-post-button')));
      await tester.pumpAndSettle();

      expect(world.chats.createdPolls, hasLength(1));
      final poll = world.chats.createdPolls.single;
      expect(poll.conversationId, 'conversation-1');
      expect(poll.question, 'Where to?');
      expect(poll.options, ['Beach', 'Hills', 'Home']);
      expect(poll.multi, isTrue);
      expect(poll.durationHours, 72);
      expect(find.byKey(const ValueKey('poll-question-field')), findsNothing);
    });

    testWidgets('needs a question and two different answers', (tester) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();
      await openFromAttach(tester);

      Future<void> post() async {
        await tester.ensureVisible(
          find.byKey(const ValueKey('poll-post-button')),
        );
        await tester.tap(find.byKey(const ValueKey('poll-post-button')));
        await tester.pump();
      }

      await post();
      expect(find.text('Ask a question.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('poll-question-field')),
        'Tea?',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-0')),
        'Yes',
      );
      await post();
      expect(find.text('Add at least 2 answers.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-1')),
        'YES',
      );
      await post();
      expect(find.text('Answers must be different.'), findsOneWidget);
      expect(world.chats.createdPolls, isEmpty);

      // Two answers stay; removing is offered only above that.
      final remove = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline).first,
      );
      expect(remove.onPressed, isNull);
    });

    testWidgets('/poll opens the poll form', (tester) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        '/po',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('slash-command-poll')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('poll-question-field')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        '/poll',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('poll-question-field')), findsOneWidget);
      expect(world.chats.sentMessages, isEmpty);
    });
  });
}

Profile _profile(String id, String username, String displayName) {
  return Profile(
    id: id,
    username: username,
    displayName: displayName,
    bio: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

class _NoDataSource implements ChatsDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _World {
  _World() {
    chats.conversations = [
      const ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.group,
        unreadCount: 0,
        title: 'Lunch club',
      ),
    ];
  }

  final chats = chat_fakes.FakeChatsRepository();

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
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
