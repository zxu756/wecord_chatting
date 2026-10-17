import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/polls_repository.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

class _FakePolls implements PollsRepository {
  final created = <PollDraft>[];
  final added = <(String, String)>[];

  @override
  Future<void> createPoll(String conversationId, PollDraft draft) async {
    created.add(draft);
  }

  @override
  Future<String> addOption(String messageId, String text) async {
    added.add((messageId, text));
    return 'o9';
  }
}

ChatMessage _poll({
  String id = 'poll-1',
  String senderId = 'user-2',
  bool quiz = false,
  bool anonymous = false,
  bool allowAdd = false,
  DateTime? endsAt,
  PollResults results = const PollResults(),
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.poll,
    body: 'Capital of France?',
    createdAt: DateTime.utc(2026, 10, 17, 9),
    attachment: {
      'kind': 'poll',
      'question': 'Capital of France?',
      'options': [
        {'id': 'o1', 'text': 'Rome'},
        {'id': 'o2', 'text': 'Paris'},
        {'id': 'o3', 'text': 'Oslo'},
      ],
      'multi': false,
      'ends_at': endsAt?.toIso8601String(),
      'quiz': quiz,
      'anonymous': anonymous,
      'allow_add': allowAdd,
    },
    pollResults: results,
  );
}

class _World {
  _World() {
    chats.conversations = const [
      ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.group,
        unreadCount: 0,
        title: 'Quiz club',
      ),
    ];
  }

  final chats = chat_fakes.FakeChatsRepository();
  final polls = _FakePolls();

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        pollsRepositoryProvider.overrideWithValue(polls),
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
  test('parses quiz, anonymous and add flags and the shown answer', () {
    final poll = PollAttachment.maybeFromJson({
      'kind': 'poll',
      'question': 'q',
      'options': [
        {'id': 'o1', 'text': 'a'},
      ],
      'quiz': true,
      'anonymous': true,
      'allow_add': true,
    })!;
    expect(poll.quiz, isTrue);
    expect(poll.anonymous, isTrue);
    expect(poll.allowAdd, isTrue);
    final plain = PollAttachment.maybeFromJson({
      'kind': 'poll',
      'question': 'q',
      'options': const [],
    })!;
    expect(plain.quiz || plain.anonymous || plain.allowAdd, isFalse);
    final results = PollResults.maybeFromJson({
      'counts': {'o2': 1},
      'total_voters': 1,
      'my_votes': ['o1'],
      'correct': 'o2',
      'explanation': 'Since 987.',
    })!;
    expect(results.correct, 'o2');
    expect(results.explanation, 'Since 987.');
    expect(PollResults.maybeFromJson({'counts': {}})!.correct, isNull);
  });

  test('a draft knows when it needs the newer server', () {
    const plain = PollDraft(question: 'q', options: ['a', 'b']);
    expect(plain.usesNewFeatures, isFalse);
    expect(
      const PollDraft(
        question: 'q',
        options: ['a', 'b'],
        quizCorrectIndex: 0,
      ).usesNewFeatures,
      isTrue,
    );
    expect(
      const PollDraft(
        question: 'q',
        options: ['a', 'b'],
        anonymous: true,
      ).usesNewFeatures,
      isTrue,
    );
    expect(
      PollDraft(
        question: 'q',
        options: const ['a', 'b'],
        closesAt: DateTime.utc(2030),
      ).usesNewFeatures,
      isTrue,
    );
  });

  group('quiz', () {
    testWidgets('before voting nothing gives the answer away', (tester) async {
      final world = _World()..chats.messages = [_poll(quiz: true)];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();

      expect(find.text('Quiz'), findsOneWidget);
      expect(find.text('Pick the right answer'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('after voting the right answer and why show up', (
      tester,
    ) async {
      final world = _World()
        ..chats.messages = [
          _poll(
            quiz: true,
            results: const PollResults(
              counts: {'o1': 2, 'o2': 1},
              totalVoters: 3,
              myVotes: {'o1'},
              correct: 'o2',
              explanation: 'Paris has been the capital since 987.',
            ),
          ),
        ];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();

      expect(find.text('Answer recorded'), findsOneWidget);
      // The right one is marked, and so is my wrong one.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(
        find.text('Paris has been the capital since 987.'),
        findsOneWidget,
      );
      // The answer is final: another tap votes nothing.
      await tester.tap(find.byKey(const ValueKey('poll-option-poll-1-o3')));
      await tester.pump();
      expect(world.chats.pollVotes, isEmpty);
    });

    testWidgets('a vote in a quiz goes through the normal vote call', (
      tester,
    ) async {
      final world = _World()..chats.messages = [_poll(quiz: true)];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('poll-option-poll-1-o2')));
      await tester.pump();
      expect(world.chats.pollVotes.single.$2, ['o2']);
    });
  });

  testWidgets('anonymous polls say so and list no voters', (tester) async {
    final world = _World()
      ..chats.messages = [
        _poll(
          anonymous: true,
          results: const PollResults(counts: {'o2': 2}, totalVoters: 2),
        ),
      ];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.text('2 votes · Anonymous'), findsOneWidget);
    expect(find.text('View votes'), findsNothing);
  });

  group('members adding answers', () {
    testWidgets('offers Add an answer and sends it', (tester) async {
      final world = _World()..chats.messages = [_poll(allowAdd: true)];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('poll-add-option-poll-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('poll-new-option-field')),
        'Berlin',
      );
      await tester.tap(find.byKey(const ValueKey('poll-new-option-add')));
      await tester.pumpAndSettle();
      expect(world.polls.added, [('poll-1', 'Berlin')]);
    });

    testWidgets('not on polls that do not allow it, nor closed ones', (
      tester,
    ) async {
      final world = _World()
        ..chats.messages = [
          _poll(),
          _poll(
            id: 'poll-2',
            allowAdd: true,
            results: const PollResults(closed: true),
          ),
        ];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('poll-add-option-poll-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('poll-add-option-poll-2')),
        findsNothing,
      );
    });
  });

  group('composer', () {
    Future<void> openComposer(WidgetTester tester, _World world) async {
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create poll'));
      await tester.pumpAndSettle();
    }

    Future<void> moreOptions(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-more-options')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-more-options')));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const ValueKey('poll-question-field')),
        'Capital of France?',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-0')),
        'Rome',
      );
      await tester.enterText(
        find.byKey(const ValueKey('poll-option-field-1')),
        'Paris',
      );
    }

    testWidgets('a quiz needs its right answer, then posts it', (tester) async {
      final world = _World();
      await openComposer(tester, world);
      await fill(tester);
      await moreOptions(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-quiz-switch')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-quiz-switch')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-post-button')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-post-button')));
      await tester.pump();
      expect(find.text('Mark the right answer.'), findsOneWidget);
      expect(world.polls.created, isEmpty);

      await tester.ensureVisible(find.byKey(const ValueKey('poll-correct-1')));
      await tester.tap(find.byKey(const ValueKey('poll-correct-1')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('poll-explanation-field')),
        'Since 987.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-post-button')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-post-button')));
      await tester.pumpAndSettle();
      final draft = world.polls.created.single;
      expect(draft.quizCorrectIndex, 1);
      expect(draft.quizExplanation, 'Since 987.');
      expect(draft.multi, isFalse);
      expect(world.chats.createdPolls, isEmpty);
    });

    testWidgets(
      'anonymous and member-added answers post through the new path',
      (tester) async {
        final world = _World();
        await openComposer(tester, world);
        await fill(tester);
        await moreOptions(tester);
        for (final key in ['poll-anonymous-switch', 'poll-allow-add-switch']) {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pump();
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('poll-post-button')),
        );
        await tester.tap(find.byKey(const ValueKey('poll-post-button')));
        await tester.pumpAndSettle();
        final draft = world.polls.created.single;
        expect(draft.anonymous, isTrue);
        expect(draft.allowAddOptions, isTrue);
        expect(draft.isQuiz, isFalse);
      },
    );

    testWidgets('a plain poll still goes the old way', (tester) async {
      final world = _World();
      await openComposer(tester, world);
      await fill(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-post-button')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-post-button')));
      await tester.pumpAndSettle();
      expect(world.polls.created, isEmpty);
      expect(world.chats.createdPolls, hasLength(1));
    });

    testWidgets('a quiz switches multiple answers and adding off', (
      tester,
    ) async {
      final world = _World();
      await openComposer(tester, world);
      await moreOptions(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('poll-quiz-switch')),
      );
      await tester.tap(find.byKey(const ValueKey('poll-quiz-switch')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('poll-multi-switch')),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('poll-allow-add-switch')),
            )
            .onChanged,
        isNull,
      );
    });
  });
}
