import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/actions/apply_extracted_actions.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';

import '../chats/events/chat_events_test.dart' show FakeChatEventsRepository;
import '../workspace/workspace_fakes.dart';

void main() {
  // Monday 19 October 2026, 14:30 local.
  final now = DateTime(2026, 10, 19, 14, 30);

  group('an extracted item', () {
    test('is read from the server\'s JSON', () {
      final item = ExtractedAction.maybeFromJson({
        'title': ' Book the train ',
        'assignee': 'user-2',
        'due': '2026-10-23T07:00:00.000Z',
        'due_has_time': true,
        'due_text': 'Friday 3pm',
        'kind': 'event',
        'source_message_id': 'message-1',
      })!;
      expect(item.title, 'Book the train');
      expect(item.assignees, ['user-2']);
      expect(item.due, DateTime.utc(2026, 10, 23, 7).toLocal());
      expect(item.dueHasTime, isTrue);
      expect(item.dueText, 'Friday 3pm');
      expect(item.kind, ExtractedKind.event);
      expect(item.sourceMessageId, 'message-1');
    });

    test('needs a title and tolerates the rest being absent', () {
      expect(ExtractedAction.maybeFromJson({'title': '  '}), isNull);
      expect(ExtractedAction.maybeFromJson({'assignee': 'x'}), isNull);
      expect(ExtractedAction.maybeFromJson('junk'), isNull);
      final bare = ExtractedAction.maybeFromJson({'title': 'Call Ann'})!;
      expect(bare.assignees, isEmpty);
      expect(bare.due, isNull);
      expect(bare.kind, ExtractedKind.task);
      expect(
        ExtractedAction.maybeFromJson({'title': 'x', 'due': 'soon'})!.due,
        isNull,
      );
    });

    test('keeps the words a date came from out of copies it edits', () {
      final item = ExtractedAction.maybeFromJson({
        'title': 'x',
        'due_text': 'tomorrow 8pm',
      })!;
      expect(item.copyWith(title: 'y').dueText, 'tomorrow 8pm');
      expect(item.copyWith(due: null).due, isNull);
    });
  });

  group('the date is read by the app\'s own time parser when it can', () {
    test('words it understands win over the model\'s guess', () {
      final item = const ExtractedAction(
        title: 'Dinner',
        due: null,
        dueText: 'tomorrow 8pm',
        kind: ExtractedKind.event,
      ).refined(now);
      expect(item.due, DateTime(2026, 10, 20, 20));
      expect(item.dueHasTime, isTrue);
      expect(item.kind, ExtractedKind.event);

      final off = ExtractedAction(
        title: 'Dinner',
        due: DateTime(2026, 10, 25, 20),
        dueHasTime: true,
        dueText: 'tomorrow 8pm',
      ).refined(now);
      expect(off.due, DateTime(2026, 10, 20, 20));
    });

    test('Chinese phrases too', () {
      final item = const ExtractedAction(
        title: '交报告',
        dueText: '明天晚上8点',
      ).refined(now);
      expect(item.due, DateTime(2026, 10, 20, 20));
      expect(item.dueHasTime, isTrue);
    });

    test('words it does not understand leave the server\'s date alone', () {
      final item = ExtractedAction(
        title: 'x',
        due: DateTime(2026, 10, 23, 15),
        dueHasTime: true,
        dueText: 'whenever Ann is back',
      ).refined(now);
      expect(item.due, DateTime(2026, 10, 23, 15));
    });

    test('a date alone keeps having no time of day', () {
      final item = ExtractedAction(
        title: 'x',
        due: DateTime(2026, 10, 20, 9),
        dueText: 'tomorrow',
      ).refined(now);
      expect(item.due, DateTime(2026, 10, 20, 9));
      expect(item.dueHasTime, isFalse);
    });

    test('an event without a time of day is a task', () {
      final dateOnly = ExtractedAction(
        title: 'Party',
        due: DateTime(2026, 10, 24),
        kind: ExtractedKind.event,
      ).refined(now);
      expect(dateOnly.kind, ExtractedKind.task);
      final none = const ExtractedAction(
        title: 'Party',
        kind: ExtractedKind.event,
      ).refined(now);
      expect(none.kind, ExtractedKind.task);
      expect(none.canBeEvent, isFalse);
    });
  });

  group('confirmed items are created through the existing repositories', () {
    late FakeListsRepository lists;
    late FakeChatEventsRepository events;
    var counter = 0;

    setUp(() {
      lists = FakeListsRepository();
      events = FakeChatEventsRepository([]);
      counter = 0;
    });

    String nextId() => 'task-${++counter}';

    test('a task goes into a new list when there is none', () async {
      final outcomes = await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        actions: [
          ExtractedAction(
            title: 'Book the train',
            assignees: const ['user-2'],
            due: DateTime(2026, 10, 23, 15),
            dueHasTime: true,
            sourceMessageId: 'message-1',
          ),
        ],
      );
      expect(outcomes.single, isA<TaskCreated>());
      expect(lists.upserts, hasLength(1));
      final fields = lists.upserts.single;
      expect(fields['id'], 'task-1');
      expect(fields['title'], 'Book the train');
      expect(fields['assignees'], ['user-2']);
      expect(fields['due_has_time'], isTrue);
      expect(fields['source_message_id'], 'message-1');
      expect(
        DateTime.parse('${fields['due_at']}').toLocal(),
        DateTime(2026, 10, 23, 15),
      );
      expect(lists.lists.values.single.title, isNotEmpty);
    });

    test('a date alone is due at the end of that day', () async {
      await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        actions: [
          ExtractedAction(title: 'Pay', due: DateTime(2026, 10, 23, 9)),
        ],
      );
      final fields = lists.upserts.single;
      expect(fields['due_has_time'], isFalse);
      expect(
        DateTime.parse('${fields['due_at']}').toLocal(),
        DateTime(2026, 10, 23, 23, 59, 59),
      );
    });

    test('an event is created in the chat, not as a task', () async {
      final outcomes = await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        actions: [
          ExtractedAction(
            title: 'Team dinner',
            due: DateTime(2026, 10, 24, 19),
            dueHasTime: true,
            kind: ExtractedKind.event,
          ),
        ],
      );
      expect(outcomes.single, isA<EventCreated>());
      expect(events.created.single.title, 'Team dinner');
      expect(events.created.single.startsAt, DateTime(2026, 10, 24, 19));
      expect(lists.upserts, isEmpty);
    });

    test('an event with no time of day becomes a task', () async {
      final outcomes = await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        actions: [
          const ExtractedAction(title: 'Party', kind: ExtractedKind.event),
        ],
      );
      expect(outcomes.single, isA<TaskCreated>());
      expect(events.created, isEmpty);
    });

    test('one failure does not stop the rest, and ids stay put', () async {
      lists.failUpserts = true;
      final first = await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        taskIds: const ['fixed-1', 'fixed-2'],
        actions: const [
          ExtractedAction(title: 'A'),
          ExtractedAction(title: 'B'),
        ],
      );
      expect(first.every((outcome) => outcome is ApplyFailed), isTrue);
      lists.failUpserts = false;
      final again = await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        taskIds: const ['fixed-1', 'fixed-2'],
        actions: const [
          ExtractedAction(title: 'A'),
          ExtractedAction(title: 'B'),
        ],
      );
      expect(again.every((outcome) => outcome is TaskCreated), isTrue);
      expect(lists.upserts.map((fields) => fields['id']), [
        'fixed-1',
        'fixed-2',
      ]);
    });

    test('a refusal is reported for that item only', () async {
      lists.refuseUpserts = true;
      final outcomes = await applyExtractedActions(
        lists: lists,
        events: events,
        conversationId: 'c1',
        newId: nextId,
        actions: [
          const ExtractedAction(title: 'A'),
          ExtractedAction(
            title: 'Dinner',
            due: DateTime(2026, 10, 24, 19),
            dueHasTime: true,
            kind: ExtractedKind.event,
          ),
        ],
      );
      expect(outcomes[0], isA<ApplyFailed>());
      expect(outcomes[1], isA<EventCreated>());
    });
  });
}
