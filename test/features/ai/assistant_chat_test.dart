import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/actions/extract_actions_chat.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/assistant/assistant_chat.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/features/ai/assistant/group_ai_row.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/selection/selection_actions.dart'
    show SelectionEnvironment;
import 'package:wecord/features/chats/selection/selection_registrations.dart';
import 'package:wecord/features/chats/selection/selection_registry.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_registrations.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import '../workspace/workspace_fakes.dart';
import 'ai_fakes.dart';

class _FakeAssistant implements AssistantRepository {
  final statuses = <String, AssistantJobStatus?>{};
  final polled = <String>[];
  var groupEnabled = true;
  Object? setError;
  final sets = <bool>[];

  @override
  Future<AssistantJobStatus?> jobStatus(String messageId) async {
    polled.add(messageId);
    return statuses[messageId];
  }

  @override
  Future<bool> groupAssistantEnabled(String conversationId) async =>
      groupEnabled;

  @override
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  }) async {
    if (setError case final error?) {
      throw error;
    }
    sets.add(enabled);
    groupEnabled = enabled;
  }
}

ChatMessage _message(
  String id, {
  String body = 'hello',
  String sender = 'user-1',
  MessageType type = MessageType.text,
  DateTime? createdAt,
  MessageAiReply? aiReply,
  DateTime? recalledAt,
}) => ChatMessage(
  id: id,
  conversationId: 'c1',
  senderId: sender,
  type: type,
  body: body,
  createdAt: createdAt ?? DateTime.now(),
  aiReply: aiReply,
  recalledAt: recalledAt,
);

const _todos = MessageAiReply(
  kind: AiReplyKind.todos,
  requesterId: 'user-1',
  requesterName: 'Ada',
  items: [
    {'title': 'Book the train', 'assignee': 'user-2', 'kind': 'task'},
    {'title': 'Buy snacks', 'kind': 'task'},
  ],
);

Future<void> _noop() async {}

void main() {
  late FakeAiRepository ai;
  late _FakeAssistant assistant;
  late FakeListsRepository lists;
  late chat_fakes.FakeChatsRepository chats;

  setUp(() {
    ai = FakeAiRepository();
    assistant = _FakeAssistant();
    lists = FakeListsRepository();
    chats = chat_fakes.FakeChatsRepository();
  });

  List<Override> overrides({bool aiOn = true}) => [
    aiRepositoryProvider.overrideWithValue(ai),
    aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore(aiOn)),
    assistantRepositoryProvider.overrideWithValue(assistant),
    assistantPollIntervalProvider.overrideWithValue(
      const Duration(milliseconds: 20),
    ),
    listsRepositoryProvider.overrideWithValue(lists),
    chatsRepositoryProvider.overrideWithValue(chats),
    conversationMembersProvider('c1').overrideWith((ref) async => const []),
  ];

  Future<void> pumpHost(
    WidgetTester tester,
    Widget Function(BuildContext context) build, {
    List<Override>? extra,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A fresh scope, also when a test looks at several cases in a row.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: extra ?? overrides(),
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                // The chat already watches these (the composer's AI button),
                // so by the time a menu opens they are loaded.
                for (final circle in [null, 'circle-1', 'circle-2']) {
                  ref.watch(aiAvailableProvider(circle));
                }
                return Builder(builder: build);
              },
            ),
          ),
        ),
      ),
    );
    // aiStatusProvider and the circle switch load.
    await tester.pump();
    await tester.pump();
  }

  BubbleFooterContext footerContext(
    BuildContext context,
    ChatMessage message, {
    bool mine = false,
  }) => BubbleFooterContext(
    context: context,
    message: message,
    isCurrentUser: mine,
    cards: false,
    desktop: false,
    textColor: Colors.black,
    previewUrl: null,
    showReadReceipt: false,
    onToggleReaction: (_, _) async {},
    onShowReactors: (_, _) {},
  );

  Widget footers(
    BuildContext context,
    ChatMessage message, {
    bool mine = false,
  }) {
    final registry = BubbleFooterRegistry([
      aiReplyFooterEntry,
      assistantRequestFooterEntry,
    ]);
    return Column(
      children: [
        for (final item in registry.below(
          footerContext(context, message, mine: mine),
        ))
          item.child,
      ],
    );
  }

  group('under an AI answer', () {
    testWidgets('says it is AI-generated, and who asked', (tester) async {
      await pumpHost(
        tester,
        (context) => footers(
          context,
          _message(
            'a1',
            sender: 'ai',
            aiReply: const MessageAiReply(
              kind: AiReplyKind.summary,
              requesterName: 'Ada',
            ),
          ),
        ),
      );
      expect(find.text('AI-generated · asked by Ada'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-reply-make-tasks')), findsNothing);
    });

    testWidgets('a to-do list offers Make tasks, which opens the review', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context) =>
            footers(context, _message('a2', sender: 'ai', aiReply: _todos)),
      );
      expect(find.text('AI-generated · asked by Ada'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-reply-make-tasks')));
      await tester.pumpAndSettle();
      expect(find.text('To-dos from the chat'), findsOneWidget);
      expect(find.text('Book the train'), findsOneWidget);
      expect(find.text('Buy snacks'), findsOneWidget);
      // Nothing is created until it is confirmed, and the AI is not asked
      // again for a list it already wrote.
      expect(lists.upserts, isEmpty);
      await tester.tap(find.byKey(const ValueKey('extract-create')));
      await tester.pumpAndSettle();
      expect(lists.upserts.map((f) => f['title']), [
        'Book the train',
        'Buy snacks',
      ]);
      expect(lists.upserts.first['assignees'], ['user-2']);
    });

    testWidgets('an ordinary message and a deleted answer have no mark', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context) => Column(
          children: [
            footers(context, _message('p1')),
            footers(
              context,
              _message('a3', aiReply: _todos, recalledAt: DateTime(2026)),
            ),
          ],
        ),
      );
      expect(find.textContaining('AI-generated'), findsNothing);
    });
  });

  group('under your own question', () {
    final question = '@WeCord AI /20 what did we decide?';

    testWidgets('says WeCord AI is thinking while it works', (tester) async {
      assistant.statuses['q1'] = const AssistantJobStatus(status: 'running');
      await pumpHost(
        tester,
        (context) =>
            footers(context, _message('q1', body: question), mine: true),
      );
      expect(find.text('WeCord AI is thinking…'), findsOneWidget);
      // Looked at again until it is over.
      assistant.statuses['q1'] = const AssistantJobStatus(status: 'done');
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('WeCord AI is thinking…'), findsNothing);
      expect(assistant.polled.length, greaterThanOrEqualTo(2));
    });

    testWidgets('says why there was no answer', (tester) async {
      for (final (reason, status, text) in <(String, String, String)>[
        ('group_off', 'skipped', 'The group owner turned off WeCord AI here.'),
        ('circle_off', 'skipped', 'AI features are turned off in this circle.'),
        (
          'limit',
          'limited',
          "You've reached today's AI limit. It resets tomorrow.",
        ),
        ('provider', 'failed', "WeCord AI couldn't answer. Try again."),
      ]) {
        assistant.statuses['q2'] = AssistantJobStatus(
          status: status,
          reason: reason,
        );
        await pumpHost(
          tester,
          (context) =>
              footers(context, _message('q2', body: question), mine: true),
        );
        expect(find.text(text), findsOneWidget, reason: reason);
      }
    });

    testWidgets('says nothing once answered, or for a question that is gone', (
      tester,
    ) async {
      assistant.statuses['q3'] = const AssistantJobStatus(status: 'done');
      assistant.statuses['q4'] = const AssistantJobStatus(
        status: 'skipped',
        reason: 'message_gone',
      );
      await pumpHost(
        tester,
        (context) => Column(
          children: [
            footers(context, _message('q3', body: question), mine: true),
            footers(context, _message('q4', body: question), mine: true),
          ],
        ),
      );
      expect(find.byKey(const ValueKey('ai-request-status')), findsNothing);
    });

    testWidgets('is not looked up for other people, old or plain messages', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context) => Column(
          children: [
            // Somebody else's question.
            footers(context, _message('o1', body: question, sender: 'user-2')),
            // Older than the status window.
            footers(
              context,
              _message(
                'o2',
                body: question,
                createdAt: DateTime.now().subtract(const Duration(hours: 1)),
              ),
              mine: true,
            ),
            // Not a question to the assistant.
            footers(context, _message('o3', body: 'lunch?'), mine: true),
          ],
        ),
      );
      expect(assistant.polled, isEmpty);
    });
  });

  group('the message menu', () {
    MessageActionContext actionContext(
      BuildContext context,
      ChatMessage message, {
      bool canCompose = true,
      String? circleId,
    }) => MessageActionContext(
      context: context,
      message: message,
      isCurrentUser: false,
      canCompose: canCompose,
      canPin: false,
      canStartThread: false,
      canModerate: false,
      isSaved: false,
      circleId: circleId,
      previewUrl: null,
      onReply: (_) {},
      onEdit: (_) {},
      onForward: (_) {},
      onDelete: (_) async {},
      onPreviewImage: (_) async {},
      onTogglePin: (_) async {},
      onRemoveEmbed: (_) async {},
    );

    Future<List<String>> labels(
      WidgetTester tester,
      ChatMessage message, {
      bool canCompose = true,
      String? circleId,
      List<Override>? extra,
    }) async {
      late List<String> found;
      await pumpHost(tester, (context) {
        found = [
          for (final action
              in MessageActionRegistry([
                makeTasksAction,
                askAssistantAction,
              ]).actionsFor(
                actionContext(
                  context,
                  message,
                  canCompose: canCompose,
                  circleId: circleId,
                ),
              ))
            action.label,
        ];
        return const SizedBox();
      }, extra: extra);
      return found;
    }

    testWidgets('offers Ask WeCord AI on a text message', (tester) async {
      expect(await labels(tester, _message('m1')), ['Ask WeCord AI']);
    });

    testWidgets('offers Make tasks on an AI to-do list, nothing to ask about', (
      tester,
    ) async {
      expect(
        await labels(tester, _message('m2', sender: 'ai', aiReply: _todos)),
        ['Make tasks'],
      );
      // A summary has no items to turn into tasks.
      expect(
        await labels(
          tester,
          _message(
            'm3',
            sender: 'ai',
            aiReply: const MessageAiReply(kind: AiReplyKind.summary),
          ),
        ),
        isEmpty,
      );
    });

    testWidgets('is silent where it cannot help', (tester) async {
      expect(await labels(tester, _message('m4', body: '')), isEmpty);
      expect(
        await labels(tester, _message('m5', type: MessageType.image)),
        isEmpty,
      );
      expect(
        await labels(tester, _message('m6', recalledAt: DateTime(2026))),
        isEmpty,
      );
      expect(await labels(tester, _message('m7'), canCompose: false), isEmpty);
    });

    testWidgets('is silent when AI is off for the person', (tester) async {
      expect(
        await labels(tester, _message('m8'), extra: overrides(aiOn: false)),
        isEmpty,
      );
    });

    testWidgets('is silent where AI is not set up', (tester) async {
      ai.statusError = const AiNotConfiguredException();
      expect(await labels(tester, _message('m9')), isEmpty);
    });

    testWidgets('is silent in a circle that turned AI off', (tester) async {
      ai.disabledCircles.add('circle-1');
      expect(
        await labels(tester, _message('m10'), circleId: 'circle-1'),
        isEmpty,
      );
      expect(await labels(tester, _message('m11'), circleId: 'circle-2'), [
        'Ask WeCord AI',
      ]);
    });
  });

  group('the composer menu', () {
    final actions = ComposerMenuActions(
      pickPhotosAndVideos: _noop,
      pickFiles: _noop,
      createPoll: _noop,
      createChain: _noop,
      sendContactCard: _noop,
      sendLocation: _noop,
      shareLiveLocation: _noop,
      scheduleMessage: _noop,
      insertTime: _noop,
      showEvents: _noop,
      changeWallpaper: () {},
      pickSticker: _noop,
      pickGif: _noop,
    );

    Future<List<String>> entries(
      WidgetTester tester, {
      List<Override>? extra,
    }) async {
      late List<String> found;
      await pumpHost(tester, (context) {
        found = [
          for (final entry
              in ComposerMenuRegistry([askAssistantEntry]).entriesFor(
                ComposerMenuContext(
                  context: context,
                  conversationId: 'c1',
                  conversationType: ConversationType.group,
                  compact: true,
                  gifAvailable: true,
                  actions: actions,
                ),
              ))
            entry.label,
        ];
        return const SizedBox();
      }, extra: extra);
      return found;
    }

    testWidgets('has Ask WeCord AI where AI is on', (tester) async {
      expect(await entries(tester), ['Ask WeCord AI']);
    });

    testWidgets('does not where the person or the server has it off', (
      tester,
    ) async {
      expect(await entries(tester, extra: overrides(aiOn: false)), isEmpty);
      ai.statusError = const AiNotConfiguredException();
      expect(await entries(tester), isEmpty);
    });
  });

  group('the registrations', () {
    test('the features are in the registries', () {
      expect(
        bubbleFooterExtensions.map((entry) => entry.id),
        containsAll(['ai-reply', 'ai-request-status']),
      );
      expect(
        messageActionExtensions.map((c) => c.id),
        containsAll(['ai-make-tasks', 'ask-wecord-ai']),
      );
      expect(
        composerMenuExtensions.map((c) => c.id),
        contains('ask-wecord-ai'),
      );
      expect(
        selectionBarExtensions.map((c) => c.id),
        contains('extract-actions'),
      );
    });
  });

  group('the selection bar', () {
    Future<SelectionBarEntry?> button(
      WidgetTester tester,
      List<ChatMessage> messages, {
      List<Override>? extra,
    }) async {
      SelectionBarEntry? found;
      await pumpHost(tester, (context) {
        final entries = SelectionBarRegistry([extractActionsSelectionButton])
            .entriesFor(
              SelectionBarContext(
                context: context,
                environment: SelectionEnvironment(
                  conversationId: 'c1',
                  conversationTitle: 'Plan',
                  currentUserId: 'user-1',
                  canModerate: (_) => false,
                  senderName: (_) => 'Ada',
                  onChanged: () {},
                ),
                messages: messages,
                leaveSelection: () {},
              ),
            );
        found = entries.firstOrNull;
        return const SizedBox();
      }, extra: extra);
      return found;
    }

    testWidgets('has Extract to-dos for readable text', (tester) async {
      final entry = await button(tester, [_message('m1'), _message('m2')]);
      expect(entry, isNotNull);
      expect(entry!.label, 'Extract to-dos');
      expect(entry.onPressed, isNotNull);
    });

    testWidgets('is disabled with nothing to read, and gone with AI off', (
      tester,
    ) async {
      final pictures = await button(tester, [
        _message('m1', type: MessageType.image),
      ]);
      expect(pictures!.onPressed, isNull);
      expect(
        await button(tester, [_message('m1')], extra: overrides(aiOn: false)),
        isNull,
      );
    });

    testWidgets('is disabled past 50 messages, and says so', (tester) async {
      final entry = await button(tester, [
        for (var i = 0; i < 51; i++) _message('m$i'),
      ]);
      expect(entry!.onPressed, isNull);
      expect(entry.hint, 'Pick up to 50 messages.');
    });
  });

  group('the group owner\'s switch', () {
    Future<void> pumpRow(WidgetTester tester) async {
      await pumpHost(
        tester,
        (context) => const AiAssistantGroupRow(conversationId: 'c1'),
      );
      await tester.pump();
    }

    testWidgets('shows the current state and turns it off', (tester) async {
      await pumpRow(tester);
      expect(find.text('WeCord AI in this group'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-detail-ai')));
      await tester.pump();
      expect(assistant.sets, [false]);
      expect(assistant.groupEnabled, isFalse);
    });

    testWidgets('puts the switch back when saving fails', (tester) async {
      assistant.setError = StateError('offline');
      await pumpRow(tester);
      await tester.tap(find.byKey(const ValueKey('group-detail-ai')));
      await tester.pump();
      await tester.pump();
      expect(assistant.sets, isEmpty);
      expect(find.text('Could not save. Try again.'), findsOneWidget);
    });

    testWidgets('is hidden where AI is not set up', (tester) async {
      ai.statusError = const AiNotConfiguredException();
      await pumpRow(tester);
      expect(find.byKey(const ValueKey('group-detail-ai')), findsNothing);
    });
  });
}
