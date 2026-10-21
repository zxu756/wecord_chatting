import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/features/inbox/inbox_repository.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../chats/global_message_search_screen_test.dart'
    show FakeSearchRepository, dm, general, hit;
import 'lock_fakes.dart';

Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ConversationSummary _chat(String id, {bool locked = false}) =>
    ConversationSummary(
      id: id,
      type: ConversationType.direct,
      unreadCount: 3,
      title: 'Chat $id',
      lastMessageBody: 'the secret plan',
      lastMessageSenderId: 'user-2',
      lastMessageAt: DateTime(2026, 10, 21, 11),
      isLocked: locked,
    );

class _FakeInbox implements InboxRepository {
  @override
  Future<List<InboxItem>> listInbox({int limit = 50}) async => [
    for (final id in ['locked', 'open'])
      InboxItem(
        messageId: 'm-$id',
        conversationId: id,
        senderId: 'user-2',
        senderName: 'Bob',
        body: 'the secret plan',
        type: MessageType.text,
        createdAt: DateTime(2026, 10, 21, 11),
        reason: InboxReason.mention,
        isUnread: true,
      ),
  ];
}

void main() {
  group('the latest message in a list', () {
    test('is replaced for a locked chat', () {
      final preview = conversationPreview(_chat('a', locked: true));
      expect(preview?.text, 'Locked chat');
      expect(preview?.icon, Icons.lock_outline_rounded);
      expect(
        conversationPreviewText(_chat('a', locked: true), currentUserId: 'me'),
        'Locked chat',
      );
    });

    test('is the message otherwise', () {
      expect(conversationPreview(_chat('a'))?.text, 'the secret plan');
    });

    test('is never read out loud for a locked chat', () {
      final locked = _chat('a', locked: true);
      final label = conversationRowLabel(
        locked,
        title: 'Chat a',
        preview: conversationPreviewText(locked),
        now: DateTime(2026, 10, 21, 12),
      );
      expect(label, contains('Locked chat'));
      expect(label, isNot(contains('secret')));
    });
  });

  group('the lists', () {
    late LockWorld lock;

    setUp(() => lock = LockWorld());

    ProviderContainer containerFor() {
      final container = ProviderContainer(
        overrides: [
          ...lock.overrides,
          conversationsProvider.overrideWith(
            (ref) async => [
              for (final id in ['a', 'b', 'c'])
                _chat(
                  id,
                  locked: ref.watch(lockedConversationIdsProvider).contains(id),
                ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('list every chat when none is hidden', () async {
      lock.repository.locked.add('b');
      final container = containerFor();
      container.listen(listedConversationsProvider, (previous, next) {});
      await _settle();
      final listed = container.read(listedConversationsProvider).value!;
      expect([for (final c in listed) c.id], ['a', 'b', 'c']);
      expect(listed[1].isLocked, isTrue);
    });

    test('leave out the hidden chats until the code is typed', () async {
      lock.repository.locked.add('b');
      final container = containerFor();
      container.listen(listedConversationsProvider, (previous, next) {});
      await _settle();
      final chatLock = container.read(chatLockProvider.notifier);
      await chatLock.setSecretCode('letmein');
      await chatLock.setHideLocked(true);
      await _settle();
      expect(
        [
          for (final c in container.read(listedConversationsProvider).value!)
            c.id,
        ],
        ['a', 'c'],
      );
      // The full list is still there, for a page that looks a chat up by id.
      expect(container.read(conversationsProvider).value, hasLength(3));

      chatLock.tryReveal('letmein');
      await _settle();
      expect(
        [
          for (final c in container.read(listedConversationsProvider).value!)
            c.id,
        ],
        ['a', 'b', 'c'],
      );
    });

    test('the inbox shows no text of a mention in a locked chat', () async {
      lock.repository.locked.add('locked');
      final container = ProviderContainer(
        overrides: [
          ...lock.overrides,
          inboxRepositoryProvider.overrideWithValue(_FakeInbox()),
          conversationsProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);
      container.listen(chatLockProvider, (previous, next) {});
      await _settle();
      container.listen(inboxProvider, (previous, next) {});
      final items = await container.read(inboxProvider.future);

      final locked = items.firstWhere(
        (item) => item.conversationId == 'locked',
      );
      final open = items.firstWhere((item) => item.conversationId == 'open');
      expect(locked.locked, isTrue);
      expect(inboxPreviewText(locked), 'Locked chat');
      expect(locked.body, isEmpty);
      expect(open.locked, isFalse);
      expect(inboxPreviewText(open), 'the secret plan');
    });
  });

  group('message search', () {
    late LockWorld lock;
    late FakeSearchRepository search;

    setUp(() {
      lock = LockWorld();
      search = FakeSearchRepository();
    });

    Future<MessageSearchController> start(
      ProviderContainer container, {
      MessageSearchLaunch launch = const MessageSearchLaunch(),
    }) async {
      container.listen(chatLockProvider, (previous, next) {});
      container.listen(messageSearchControllerProvider, (previous, next) {});
      await _settle();
      final controller = container.read(
        messageSearchControllerProvider.notifier,
      );
      controller.open(launch);
      return controller;
    }

    ProviderContainer container() {
      final container = ProviderContainer(
        overrides: [
          ...lock.overrides,
          messageSearchRepositoryProvider.overrideWithValue(search),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    SearchPage page() => SearchPage(
      hits: [
        hit('m1', 'conv-1', 'Ada', 'We ship it on Friday', place: dm),
        hit('m2', 'conv-2', 'Grace', 'Ship notes are up', place: general),
        hit('m3', 'conv-1', 'Ada', 'ship ship ship', place: dm),
      ],
      total: 12,
      conversationCounts: const {'conv-1': 9, 'conv-2': 3},
    );

    test('leaves out the messages of a locked chat', () async {
      lock.repository.locked.add('conv-1');
      search.pages.add(page());
      final c = container();
      final controller = await start(c);
      controller.setInput('ship');
      await controller.search();

      final state = c.read(messageSearchControllerProvider);
      expect([for (final h in state.hits) h.id], ['m2']);
      expect(state.conversationCounts, {'conv-2': 3});
      expect(state.total, 3);
    });

    test('is as it was when nothing is locked', () async {
      search.pages.add(page());
      final c = container();
      final controller = await start(c);
      controller.setInput('ship');
      await controller.search();

      final state = c.read(messageSearchControllerProvider);
      expect(state.hits, hasLength(3));
      expect(state.total, 12);
    });

    test('also leaves them out of the next pages', () async {
      lock.repository.locked.add('conv-1');
      search.pages.add(
        SearchPage(
          hits: [hit('m2', 'conv-2', 'Grace', 'Ship notes', place: general)],
          total: 12,
          nextCursor: const {'after': 'x'},
          conversationCounts: const {'conv-1': 9, 'conv-2': 3},
        ),
      );
      search.pages.add(
        SearchPage(
          hits: [
            hit('m4', 'conv-1', 'Ada', 'ship again', place: dm),
            hit('m5', 'conv-2', 'Grace', 'ship twice', place: general),
          ],
        ),
      );
      final c = container();
      final controller = await start(c);
      controller.setInput('ship');
      await controller.search();
      await controller.loadMore();

      final state = c.read(messageSearchControllerProvider);
      expect([for (final h in state.hits) h.id], ['m2', 'm5']);
    });

    test('is not applied inside the chat that is open', () async {
      lock.repository.locked.add('conv-1');
      search.pages.add(page());
      final c = container();
      final controller = await start(
        c,
        launch: const MessageSearchLaunch(
          conversationId: 'conv-1',
          conversationTitle: 'Ada Lovelace',
          conversationType: ConversationType.direct,
        ),
      );
      controller.setInput('ship');
      await controller.search();

      expect(c.read(messageSearchControllerProvider).hits, hasLength(3));
    });
  });
}
