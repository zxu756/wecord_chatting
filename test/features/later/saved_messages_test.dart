import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/message.dart';

import '../../mobile/phone_test_support.dart';
import '../chats/chat_thread_screen_test.dart' as thread_test;
import '../file_preview/file_preview_fakes.dart';
import 'later_fakes.dart';

SavedMessage _saved(
  String id, {
  String body = 'Bring the tripod',
  bool done = false,
  bool available = true,
  String conversationId = 'dm-1',
  int minutesAgo = 30,
}) {
  return SavedMessage(
    id: id,
    messageId: available ? 'm-$id' : null,
    conversationId: conversationId,
    savedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
    doneAt: done ? DateTime.now() : null,
    senderId: available ? 'user-2' : null,
    senderName: available ? 'Bart the Bold' : '',
    body: available ? body : '',
    available: available,
  );
}

void main() {
  group('model', () {
    test('parses a server row', () {
      final saved = SavedMessage.fromJson({
        'saved_id': 's1',
        'message_id': 'm1',
        'conversation_id': 'c1',
        'saved_at': '2026-10-17T10:00:00+00:00',
        'done_at': '2026-10-17T11:00:00+00:00',
        'sender_id': 'u2',
        'sender_display_name': 'Bob',
        'sender_avatar_url': null,
        'webhook_name': null,
        'body': 'Bring the tripod',
        'type': 'text',
        'message_created_at': '2026-10-16T10:00:00+00:00',
        'available': true,
      });
      expect(saved.isDone, isTrue);
      expect(saved.senderName, 'Bob');
      expect(saved.savedAt, DateTime.utc(2026, 10, 17, 10));
    });

    test('an unavailable message has neither sender nor text', () {
      final saved = SavedMessage.fromJson({
        'saved_id': 's1',
        'message_id': null,
        'conversation_id': 'c1',
        'saved_at': '2026-10-17T10:00:00+00:00',
        'done_at': null,
        'sender_id': null,
        'sender_display_name': null,
        'sender_avatar_url': null,
        'webhook_name': null,
        'body': null,
        'type': null,
        'message_created_at': null,
        'available': false,
      });
      expect(saved.available, isFalse);
      expect(saved.body, isEmpty);
      expect(saved.isDone, isFalse);
    });

    test('saved ids and the active count come from the list', () async {
      final container = ProviderContainer(
        overrides: [
          savedMessagesRepositoryProvider.overrideWithValue(
            FakeSavedMessagesRepository([
              _saved('a'),
              _saved('b', done: true),
              _saved('c', available: false),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
        ..listen(savedMessageIdsProvider, (_, _) {})
        ..listen(activeSavedCountProvider, (_, _) {});
      await container.read(savedMessagesProvider.future);
      expect(container.read(savedMessageIdsProvider), {'m-a', 'm-b'});
      expect(container.read(activeSavedCountProvider), 2);
    });
  });

  group('saved page', () {
    Future<PhoneWorld> open(
      WidgetTester tester,
      FakeSavedMessagesRepository repository,
    ) async {
      final world = PhoneWorld()
        ..extraOverrides = [
          savedMessagesRepositoryProvider.overrideWithValue(repository),
        ];
      await world.open(tester, '/saved');
      await settle(tester);
      return world;
    }

    testWidgets('lists the active ones first, with the done ones apart', (
      tester,
    ) async {
      final repository = FakeSavedMessagesRepository([
        _saved('a', body: 'Bring the tripod'),
        _saved('b', body: 'Book the cabin', done: true),
      ]);
      await open(tester, repository);

      expect(find.text('Saved'), findsWidgets);
      expect(find.text('Bring the tripod'), findsOneWidget);
      expect(find.text('Book the cabin'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('saved-filter-done')));
      await settle(tester);
      expect(find.text('Book the cabin'), findsOneWidget);
      expect(find.text('Bring the tripod'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('marks done, and undoes it', (tester) async {
      final repository = FakeSavedMessagesRepository([_saved('a')]);
      await open(tester, repository);

      await tester.tap(find.byKey(const ValueKey('saved-done-a')));
      await settle(tester);
      expect(repository.doneCalls, [(id: 'a', done: true)]);
      // It moved to Done.
      expect(find.byKey(const ValueKey('saved-a')), findsNothing);
      expect(find.text('Nothing saved yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('saved-filter-done')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('saved-done-a')));
      await settle(tester);
      expect(repository.doneCalls.last, (id: 'a', done: false));
      expect(find.text('Nothing done yet'), findsOneWidget);
    });

    testWidgets('removes an entry', (tester) async {
      final repository = FakeSavedMessagesRepository([
        _saved('a'),
        _saved('b', body: 'Other'),
      ]);
      await open(tester, repository);

      await tester.tap(find.byKey(const ValueKey('saved-remove-a')));
      await settle(tester);

      expect(repository.removed, ['a']);
      expect(find.byKey(const ValueKey('saved-a')), findsNothing);
      expect(find.byKey(const ValueKey('saved-b')), findsOneWidget);
    });

    testWidgets('a message that is gone says so and can only be removed', (
      tester,
    ) async {
      final repository = FakeSavedMessagesRepository([
        _saved('a', available: false),
      ]);
      await open(tester, repository);

      expect(find.text('Message unavailable'), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-jump-a')), findsNothing);
      expect(find.byKey(const ValueKey('saved-done-a')), findsNothing);
      expect(find.byKey(const ValueKey('saved-remove-a')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('saved-remove-a')));
      await settle(tester);
      expect(repository.removed, ['a']);
    });

    testWidgets('Jump opens the conversation at the message', (tester) async {
      final repository = FakeSavedMessagesRepository([_saved('a')]);
      final world = await open(tester, repository);

      await tester.tap(find.byKey(const ValueKey('saved-jump-a')));
      await settle(tester);

      expect(world.router.state.uri.path, '/chats/dm-1');
    });

    testWidgets('says when nothing is saved', (tester) async {
      await open(tester, FakeSavedMessagesRepository());
      expect(find.text('Nothing saved yet'), findsOneWidget);
    });

    testWidgets('a failing server shows an error and keeps the entry', (
      tester,
    ) async {
      final repository = FakeSavedMessagesRepository([_saved('a')]);
      await open(tester, repository);
      repository.failWrites = true;

      await tester.tap(find.byKey(const ValueKey('saved-done-a')));
      await settle(tester);

      expect(find.byKey(const ValueKey('saved-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-a')), findsOneWidget);
    });

    testWidgets('the Notifications page and Settings lead here', (
      tester,
    ) async {
      final repository = FakeSavedMessagesRepository([_saved('a')]);
      final world = PhoneWorld()
        ..extraOverrides = [
          savedMessagesRepositoryProvider.overrideWithValue(repository),
        ];
      await world.open(tester, '/notifications');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('inbox-saved-button')));
      await settle(tester);
      expect(world.router.state.uri.path, '/saved');
    });
  });

  group('save for later', () {
    Widget app(
      thread_test.FakeChatsRepository chats,
      FakeSavedMessagesRepository saved,
    ) {
      return ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(chats),
          savedMessagesRepositoryProvider.overrideWithValue(saved),
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
            title: 'Ada Lovelace',
          ),
        ),
      );
    }

    thread_test.FakeChatsRepository chat() {
      return thread_test.FakeChatsRepository()
        ..messages = [
          ChatMessage(
            id: 'message-1',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.text,
            body: 'Bring the tripod',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
        ];
    }

    testWidgets('the message menu saves, then offers to remove', (
      tester,
    ) async {
      final saved = FakeSavedMessagesRepository();
      await tester.pumpWidget(app(chat(), saved));
      await tester.pump();

      await tester.longPress(find.text('Bring the tripod'));
      await tester.pumpAndSettle();
      expect(find.text('Save for later'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('message-save')));
      await tester.pumpAndSettle();

      expect(saved.saved, ['message-1']);
      expect(find.text('Saved for later'), findsOneWidget);

      // Saved now: the menu says so and removes it.
      await tester.pump(const Duration(seconds: 5));
      await tester.longPress(find.text('Bring the tripod'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from Saved'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('message-save')));
      await tester.pumpAndSettle();
      expect(saved.removed, hasLength(1));
      expect(saved.entries, isEmpty);
    });

    testWidgets('a failed save says so', (tester) async {
      final saved = FakeSavedMessagesRepository()..failWrites = true;
      await tester.pumpWidget(app(chat(), saved));
      await tester.pump();

      await tester.longPress(find.text('Bring the tripod'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-save')));
      await tester.pumpAndSettle();

      expect(find.text('Could not update Saved. Try again.'), findsOneWidget);
    });
  });
}
