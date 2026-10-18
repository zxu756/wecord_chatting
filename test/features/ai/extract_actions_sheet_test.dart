import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/actions/extract_actions_repository.dart';
import 'package:wecord/features/ai/actions/extract_actions_sheet.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/lists/lists_repository.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/events/chat_events_test.dart' show FakeChatEventsRepository;
import '../workspace/workspace_fakes.dart';

class _FakeExtract implements ExtractActionsRepository {
  _FakeExtract(this.result);

  ExtractedActions result;
  Object? error;
  Completer<void>? gate;
  final calls = <List<String>>[];

  @override
  Future<ExtractedActions> extract({
    required String conversationId,
    required List<String> messageIds,
    DateTime? now,
  }) async {
    calls.add(messageIds);
    await gate?.future;
    if (error case final error?) {
      throw error;
    }
    return result;
  }
}

GroupMember _member(String id, String name) => GroupMember(
  profile: Profile(
    id: id,
    username: name.toLowerCase(),
    displayName: name,
    bio: '',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  role: 'member',
);

ChatMessage _message(String id, String body) => ChatMessage(
  id: id,
  conversationId: 'c1',
  senderId: 'user-1',
  type: MessageType.text,
  body: body,
  createdAt: DateTime.utc(2026, 10, 19, 10),
);

ExtractedActions _found() => ExtractedActions(
  messageCount: 2,
  items: [
    const ExtractedAction(
      title: 'Book the train',
      assignees: ['user-2'],
      sourceMessageId: 'm1',
    ),
    ExtractedAction(
      title: 'Team dinner',
      due: DateTime(2099, 1, 5, 19),
      dueHasTime: true,
      kind: ExtractedKind.event,
    ),
    const ExtractedAction(title: 'Buy snacks'),
  ],
);

void main() {
  late _FakeExtract extract;
  late FakeListsRepository lists;
  late FakeChatEventsRepository events;
  bool? result;

  Future<void> open(
    WidgetTester tester, {
    List<ChatMessage>? messages,
    List<ExtractedAction>? preset,
    bool settle = true,
  }) async {
    result = null;
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extractActionsRepositoryProvider.overrideWithValue(extract),
          listsRepositoryProvider.overrideWithValue(lists),
          chatEventsRepositoryProvider.overrideWithValue(events),
          conversationMembersProvider('c1').overrideWith(
            (ref) async => [_member('user-1', 'Ada'), _member('user-2', 'Bob')],
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showExtractActionsSheet(
                      context,
                      conversationId: 'c1',
                      messages: messages ?? [_message('m1', 'Bob, book it')],
                      preset: preset,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  setUp(() {
    extract = _FakeExtract(_found());
    lists = FakeListsRepository();
    events = FakeChatEventsRepository([]);
  });

  testWidgets('shows what it is reading, then the items to confirm', (
    tester,
  ) async {
    extract.gate = Completer<void>();
    await open(
      tester,
      messages: [_message('m1', 'a'), _message('m2', 'b')],
      settle: false,
    );
    expect(find.byKey(const ValueKey('extract-loading')), findsOneWidget);
    expect(find.text('Reading 2 messages…'), findsOneWidget);
    expect(extract.calls.single, ['m1', 'm2']);

    extract.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('extract-item-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('extract-item-2')), findsOneWidget);
    expect(find.text('Book the train'), findsOneWidget);
    // The assignee is shown by name, and the event keeps its time.
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Create 3 items'), findsOneWidget);
    // Nothing was made yet.
    expect(lists.upserts, isEmpty);
    expect(events.created, isEmpty);
  });

  testWidgets('creates what is ticked: tasks as tasks, events as events', (
    tester,
  ) async {
    await open(tester);
    // Not "Buy snacks".
    await tester.tap(find.byKey(const ValueKey('extract-item-tick-2')));
    await tester.pump();
    expect(find.text('Create 2 items'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();

    expect(lists.upserts, hasLength(1));
    expect(lists.upserts.single['title'], 'Book the train');
    expect(lists.upserts.single['assignees'], ['user-2']);
    expect(lists.upserts.single['source_message_id'], 'm1');
    expect(events.created.single.title, 'Team dinner');
    expect(events.created.single.startsAt, DateTime(2099, 1, 5, 19));
    expect(result, isTrue);
    expect(find.text('1 task and 1 event created.'), findsOneWidget);
    expect(find.text('Book the train'), findsNothing);
  });

  testWidgets('a title can be changed before creating', (tester) async {
    await open(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('extract-item-title-0')),
        matching: find.byType(EditableText),
      ),
      'Book the 9am train',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();
    expect(lists.upserts.first['title'], 'Book the 9am train');
  });

  testWidgets('an event can be turned into a task', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('extract-item-task-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();
    expect(events.created, isEmpty);
    expect(
      lists.upserts.map((fields) => fields['title']),
      contains('Team dinner'),
    );
  });

  testWidgets('nothing selected, nothing to create', (tester) async {
    await open(tester);
    for (final index in [0, 1, 2]) {
      await tester.tap(find.byKey(ValueKey('extract-item-tick-$index')));
      await tester.pump();
    }
    expect(find.text('Nothing selected'), findsOneWidget);
    final button = tester.widget<Widget>(
      find.byKey(const ValueKey('extract-create')),
    );
    expect(button, isNotNull);
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pump();
    expect(lists.upserts, isEmpty);
  });

  testWidgets('what could not be created stays for another try', (
    tester,
  ) async {
    lists.failUpserts = true;
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();
    // The event was made; the two tasks were not.
    expect(events.created, hasLength(1));
    expect(result, isNull);
    expect(find.byKey(const ValueKey('extract-item-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('extract-item-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('extract-item-2')), findsNothing);
    expect(find.text('Create 2 items'), findsOneWidget);

    lists.failUpserts = false;
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();
    expect(lists.upserts, hasLength(2));
    // The event is not made twice.
    expect(events.created, hasLength(1));
    expect(result, isTrue);
  });

  testWidgets('says so when nothing was found', (tester) async {
    extract.result = const ExtractedActions(items: [], messageCount: 1);
    await open(tester);
    expect(find.byKey(const ValueKey('extract-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('extract-create')), findsNothing);
  });

  testWidgets('explains an error and offers another try', (tester) async {
    extract.error = const AiLimitReachedException(limit: 50);
    await open(tester);
    expect(find.byKey(const ValueKey('extract-error')), findsOneWidget);
    expect(find.textContaining("today's AI limit of 50"), findsOneWidget);
    extract.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('extract-item-0')), findsOneWidget);
    expect(extract.calls, hasLength(2));
  });

  testWidgets('a circle with AI off gets no retry button', (tester) async {
    extract.error = const AiDisabledInCircleException();
    await open(tester);
    expect(
      find.text('AI features are turned off in this circle.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a list WeCord AI wrote is confirmed without asking the AI', (
    tester,
  ) async {
    await open(
      tester,
      messages: const [],
      preset: const [
        ExtractedAction(title: 'Order cake', assignees: ['user-1']),
      ],
    );
    expect(extract.calls, isEmpty);
    expect(find.text('Order cake'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extract-create')));
    await tester.pumpAndSettle();
    expect(lists.upserts.single['title'], 'Order cake');
    expect(lists.upserts.single['assignees'], ['user-1']);
    expect(result, isTrue);
  });

  testWidgets('only readable text can be extracted from', (tester) async {
    expect(canExtractFrom(_message('m1', 'hello')), isTrue);
    expect(canExtractFrom(_message('m1', '  ')), isFalse);
    expect(
      canExtractFrom(_message('m1', 'hi').copyWith(recalledAt: DateTime(2026))),
      isFalse,
    );
    expect(
      canExtractFrom(
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          senderId: 'u',
          type: MessageType.image,
          body: 'caption',
          createdAt: DateTime(2026),
        ),
      ),
      isFalse,
    );
  });
}
