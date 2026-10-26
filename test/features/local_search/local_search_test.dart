import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_search/local_search_index.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/shared/models/conversation.dart';

import 'local_search_fakes.dart';

void main() {
  late LocalSearchWorld world;

  setUp(() => world = LocalSearchWorld());

  group('finding messages', () {
    setUp(() async {
      await world.cacheChat('c1', [
        messageRow('m1', 'c1', '今天去北京吃烤鸭', minute: 1),
        messageRow('m2', 'c1', 'Hello World from Bart', minute: 2),
        messageRow('m3', 'c1', '明天开会，别迟到', sender: userAda, minute: 3),
        messageRow('m4', 'c1', 'ＷｅＣｏｒｄ　is fun', minute: 4),
      ]);
    });

    test('finds Chinese by its characters, with or without spaces', () async {
      expect(await world.ids('北京'), ['m1']);
      expect(await world.ids('烤鸭'), ['m1']);
      // Across what a word splitter would call a boundary.
      expect(await world.ids('京吃'), ['m1']);
      expect(await world.ids('开会'), ['m3']);
      expect(await world.ids('京'), ['m1']);
      expect(await world.ids('上海'), isEmpty);
    });

    test('finds a word whatever its case and width', () async {
      expect(await world.ids('hello'), ['m2']);
      expect(await world.ids('WORLD'), ['m2']);
      expect(await world.ids('wecord'), ['m4']);
      expect(await world.ids('ＷＥＣＯＲＤ'), ['m4']);
    });

    test('needs every word, a whole phrase and none of the excluded', () async {
      expect(await world.ids('hello bart'), ['m2']);
      expect(await world.ids('hello 北京'), isEmpty);
      expect(await world.ids('"hello world"'), ['m2']);
      expect(await world.ids('"world hello"'), isEmpty);
      expect(await world.ids('吃 -北京'), isEmpty);
      expect(await world.ids('吃 -上海'), ['m1']);
      expect(await world.ids('is -hello'), ['m4']);
    });

    test('answers with everything the result list shows', () async {
      final page = await world.search.search(request('北京'));
      final hit = page.hits.single;

      expect(page.offline, isTrue);
      expect(page.total, 1);
      expect(hit.senderName, 'Bart');
      expect(hit.message.body, '今天去北京吃烤鸭');
      expect(hit.message.type.name, 'text');
      expect(page.conversationCounts, {'c1': 1});
    });

    test('lists the newest first, the oldest first, or the most relevant', () async {
      await world.cacheChat('c2', [
        messageRow('n1', 'c2', 'cat', minute: 1, day: 2),
        messageRow('n2', 'c2', 'cat cat cat', minute: 2, day: 2),
        messageRow('n3', 'c2', 'a cat', minute: 3, day: 2),
      ]);

      expect(await world.ids('cat'), ['n3', 'n2', 'n1']);
      expect(
        await world.ids('cat', sort: MessageSearchSort.oldest),
        ['n1', 'n2', 'n3'],
      );
      expect(
        await world.ids('cat', sort: MessageSearchSort.relevance),
        ['n2', 'n3', 'n1'],
      );
    });

    test('pages through the matches', () async {
      await world.cacheChat('c3', [
        for (var index = 0; index < 7; index++)
          messageRow('p$index', 'c3', 'page $index', minute: index, day: 3),
      ]);

      final first = await world.search.search(
        request('page', pageSize: 3),
      );
      expect(first.hits.map((hit) => hit.id), ['p6', 'p5', 'p4']);
      expect(first.total, 7);
      final second = await world.search.search(
        request('page', pageSize: 3, cursor: first.nextCursor),
      );
      expect(second.hits.map((hit) => hit.id), ['p3', 'p2', 'p1']);
      expect(second.total, isNull);
      final third = await world.search.search(
        request('page', pageSize: 3, cursor: second.nextCursor),
      );
      expect(third.hits.map((hit) => hit.id), ['p0']);
      expect(third.nextCursor, isNull);
    });
  });

  group('filters', () {
    setUp(() async {
      await world.inner.writeConversations(meId, [
        conversationRow('c1', 'Weekend plans'),
        conversationRow('c2', 'Work', circleId: 'circle-1'),
        conversationRow('t1', 'A thread', type: 'thread', parent: 'c1'),
      ]);
      await world.cacheChat('c1', [
        messageRow('a1', 'c1', 'lunch at noon', minute: 1, day: 1),
        messageRow(
          'a2',
          'c1',
          'lunch menu',
          sender: userAda,
          minute: 2,
          day: 2,
          pinned: true,
        ),
        messageRow(
          'a3',
          'c1',
          'lunch photo',
          type: 'image',
          attachment: {'kind': 'image', 'bucket': 'b', 'path': 'p/1.jpg'},
          minute: 3,
          day: 3,
        ),
        messageRow(
          'a4',
          'c1',
          'lunch https://example.com/menu',
          minute: 4,
          day: 4,
          mentions: [
            {'user_id': userAda, 'display_name': 'Ada', 'start': 0, 'end': 3},
          ],
        ),
      ]);
      await world.cacheChat('c2', [
        messageRow('b1', 'c2', 'lunch with the team', minute: 1, day: 5),
      ]);
      await world.cacheChat('t1', [
        messageRow('th1', 't1', 'lunch in the thread', minute: 1, day: 6),
      ]);
    });

    test('from, has, pinned and mentions', () async {
      expect(
        await world.ids(
          'lunch',
          filters: const MessageSearchFilters(fromIds: [userAda]),
        ),
        ['a2'],
      );
      expect(
        await world.ids(
          'lunch',
          filters: const MessageSearchFilters(has: {SearchHas.image}),
        ),
        ['a3'],
      );
      expect(
        await world.ids(
          'lunch',
          filters: const MessageSearchFilters(has: {SearchHas.link}),
        ),
        ['a4'],
      );
      expect(
        await world.ids('lunch', filters: const MessageSearchFilters(pinned: true)),
        ['a2'],
      );
      expect(
        await world.ids(
          'lunch',
          filters: const MessageSearchFilters(mentionIds: [userAda]),
        ),
        ['a4'],
      );
    });

    test('by day: before, after and during', () async {
      final day2 = SearchDate(2026, 10, 2);
      final during = await world.ids(
        'lunch',
        filters: MessageSearchFilters(during: day2),
      );
      expect(during, ['a2']);
      expect(
        await world.ids(
          'lunch',
          filters: MessageSearchFilters(before: SearchDate(2026, 10, 3)),
        ),
        ['a2', 'a1'],
      );
      expect(
        await world.ids(
          'lunch',
          filters: MessageSearchFilters(after: SearchDate(2026, 10, 4)),
        ),
        ['th1', 'b1'],
      );
    });

    test('where: a place, a conversation with its threads, a circle', () async {
      expect(
        await world.ids(
          'lunch',
          filters: const MessageSearchFilters(placeIds: ['c2']),
        ),
        ['b1'],
      );
      expect(
        await world.ids(
          'lunch',
          scope: const ConversationScope(conversationId: 'c1'),
        ),
        ['th1', 'a4', 'a3', 'a2', 'a1'],
      );
      expect(
        await world.ids('lunch', scope: const CircleScope(circleId: 'circle-1')),
        ['b1'],
      );
    });

    test('names the places of the hits from the cached chat list', () async {
      final page = await world.search.search(request('thread'));
      final place = page.hits.single.place!;
      expect(place.id, 't1');
      expect(place.type, ConversationType.thread);
      expect(place.parentConversationId, 'c1');
    });

    test('suggests the people and places it has cached', () async {
      final people = await world.search.suggestPeople('ad');
      expect(people.single.username, 'ada');
      expect(people.single.id, userAda);
      expect((await world.search.suggestPeople('@BA')).single.id, userBart);

      final places = await world.search.suggestPlaces('week');
      expect(places.single.id, 'c1');
      expect(places.single.filterValue, 'Weekend plans');
      expect(await world.search.suggestPlaces('nothing'), isEmpty);
    });
  });

  group('what must not be found', () {
    test('a deleted message goes when the chat is written again', () async {
      await world.cacheChat('c1', [
        messageRow('m1', 'c1', 'secret plan'),
        messageRow('m2', 'c1', 'secret garden', minute: 1),
      ]);
      expect(await world.ids('secret'), ['m2', 'm1']);

      await world.cacheChat('c1', [
        messageRow('m1', 'c1', 'secret plan', recalledAt: '2026-10-02T00:00:00Z'),
        messageRow('m2', 'c1', 'secret garden', minute: 1),
      ]);

      expect(await world.ids('secret'), ['m2']);
    });

    test('a message held back or removed by the AI guard is not indexed', () async {
      await world.cacheChat('c1', [
        messageRow('ok', 'c1', 'visible words'),
        messageRow('held', 'c1', 'visible but held', reviewState: 'held'),
        messageRow('gone', 'c1', 'visible but removed', reviewState: 'removed'),
        messageRow('wait', 'c1', 'visible and checking', reviewState: 'checking'),
      ]);

      expect(await world.ids('visible'), ['ok']);
    });

    test('a photo or video that opens once is not indexed', () async {
      await world.cacheChat('c1', [
        messageRow(
          'once',
          'c1',
          'look at this',
          type: 'image',
          attachment: {'kind': 'image', 'view_once': true},
        ),
        messageRow(
          'file',
          'c1',
          'look at this',
          type: 'file',
          attachment: {'kind': 'file', 'name': 'look.pdf'},
          minute: 1,
        ),
      ]);

      expect(await world.ids('look'), ['file']);
    });

    test('an expired message is not indexed, and the sweep drops it', () async {
      await world.cacheChat('c1', [
        messageRow('old', 'c1', 'timed words', expiresAt: '2026-10-27T11:00:00Z'),
        messageRow(
          'soon',
          'c1',
          'timed words soon',
          expiresAt: '2026-10-27T13:00:00Z',
          minute: 1,
        ),
        messageRow('stays', 'c1', 'timed words stay', minute: 2),
      ]);
      expect(await world.ids('timed'), ['stays', 'soon']);

      world.clockNow = DateTime.utc(2026, 10, 27, 14);
      final removed = await world.cache.removeExpired(
        meId,
        world.clockNow,
      );

      expect({for (final row in removed) row['id']}, {'old', 'soon'});
      expect(await world.ids('timed'), ['stays']);
    });

    test('forgetting some messages of a chat, one chat, or everything', () async {
      await world.cacheChat('c1', [
        messageRow('a', 'c1', 'common'),
        messageRow('b', 'c1', 'common', minute: 1),
      ]);
      await world.cacheChat('c2', [messageRow('c', 'c2', 'common', day: 2)]);

      await world.cache.removeMessages(meId, 'c1', ids: {'a'});
      expect(await world.ids('common'), ['c', 'b']);

      await world.cache.removeMessages(meId, 'c1');
      expect(await world.ids('common'), ['c']);

      await world.cacheChat('c1', [messageRow('d', 'c1', 'common')]);
      await world.cache.clearMessages(meId);
      expect(await world.ids('common'), isEmpty);
      expect(await world.indexStore.keys(), isEmpty);

      await world.cacheChat('c1', [messageRow('e', 'c1', 'common')]);
      await world.cache.clear();
      expect(await world.ids('common'), isEmpty);
      expect(await world.indexStore.keys(), isEmpty);
    });

    test('a chat the person locked is left out, unless they search inside it', () async {
      await world.cacheChat('c1', [messageRow('l1', 'c1', 'locked words')]);
      await world.cacheChat('c2', [messageRow('o1', 'c2', 'locked words too')]);
      world.excluded = {'c1'};

      expect(await world.ids('locked'), ['o1']);
      final page = await world.search.search(request('locked'));
      expect(page.total, 1);
      expect(page.conversationCounts, {'c2': 1});
      expect(
        await world.ids(
          'locked',
          scope: const ConversationScope(conversationId: 'c1'),
        ),
        ['l1'],
      );
    });

    test('another user\'s messages are never found', () async {
      await world.cache.writeMessages('someone-else', 'cx', [
        messageRow('x1', 'cx', 'private words'),
      ]);
      expect(await world.ids('private'), isEmpty);
    });
  });

  group('the index at rest', () {
    test('holds nothing readable', () async {
      await world.cacheChat('c1', [
        messageRow('m1', 'c1', '银行卡密码 hunter2'),
      ]);

      final stored = world.indexStore.values.values.single;
      expect(stored, startsWith(sealedPrefix));
      expect(stored, isNot(contains('hunter2')));
      expect(stored, isNot(contains('银行卡')));
      expect(world.indexStore.values.keys.single, 'u/$meId/s/c1');
    });

    test('is read back by a new session with the same key, not with another', () async {
      final cipherWorld = LocalSearchWorld();
      await cipherWorld.cacheChat('c1', [messageRow('m1', 'c1', 'remember me')]);

      final restarted = LocalSearchIndex(
        // A second view of the same stored values and the same key.
        cipherWorld.index.store,
      );
      final loaded = await restarted.load(meId);
      expect(loaded['c1']!.messages.single.text, 'remember me');

      final stranger = LocalSearchWorld();
      stranger.indexStore.values.addAll(cipherWorld.indexStore.values);
      await stranger.inner.writeMessages(meId, 'c1', [
        messageRow('m1', 'c1', 'remember me'),
      ]);
      expect(await stranger.ids('remember'), isEmpty);
    });
  });

  group('building the index for a cache that has none', () {
    test('indexes what the cache holds, a chat at a time, and drops what it lost', () async {
      // Written before there was a search: straight into the cache.
      await world.inner.writeMessages(meId, 'c1', [
        messageRow('m1', 'c1', 'saved before'),
      ]);
      await world.inner.writeMessages(meId, 'c2', [
        messageRow('m2', 'c2', 'saved before too'),
        messageRow('m3', 'c2', 'removed', recalledAt: '2026-10-02T00:00:00Z'),
      ]);
      // An index entry of a chat the cache no longer holds.
      await world.index.replace(
        meId,
        'gone',
        ConversationIndex(messages: [
          IndexedMessage(
            id: 'x',
            createdAtMs: 1,
            senderId: userBart,
            text: 'saved before',
          ),
        ]),
      );
      expect(await world.index.indexedConversations(meId), {'gone'});

      var pauses = 0;
      final indexed = await world.cache.backfill(
        meId,
        pause: () async => pauses++,
      );

      expect(indexed, 2);
      expect(pauses, 2);
      expect(await world.ids('saved'), unorderedEquals(['m1', 'm2']));
      expect(await world.index.indexedConversations(meId), {'c1', 'c2'});
      expect(await world.cache.backfill(meId), 0);
    });

    test('does not overwrite a chat written while it was reading', () async {
      await world.inner.writeMessages(meId, 'c1', [
        messageRow('m1', 'c1', 'old words'),
      ]);
      final version = world.index.versionOf(meId, 'c1');
      await world.cacheChat('c1', [messageRow('m1', 'c1', 'new words')]);

      await world.index.replaceIfUnchanged(
        meId,
        'c1',
        ConversationIndex.fromRows([
          messageRow('m1', 'c1', 'old words'),
        ], world.clockNow),
        version,
      );

      expect(await world.ids('old'), isEmpty);
      expect(await world.ids('new'), ['m1']);
    });
  });

  group('around a result', () {
    test('gives the messages before and after, without the deleted ones', () async {
      await world.cacheChat('c1', [
        messageRow('m1', 'c1', 'one', minute: 1),
        messageRow('m2', 'c1', 'deleted', minute: 2, recalledAt: '2026-10-02T00:00:00Z'),
        messageRow('m3', 'c1', 'three needle', minute: 3),
        messageRow('m4', 'c1', 'four', minute: 4),
      ]);

      final context = await world.search.context('m3');

      expect(context.before.map((hit) => hit.id), ['m1']);
      expect(context.after.map((hit) => hit.id), ['m4']);
      expect((await world.search.context('nope')).before, isEmpty);
    });
  });

  group('with a large cache', () {
    test('writes and searches 100 chats of 100 messages in good time', () async {
      final write = Stopwatch()..start();
      for (var chat = 0; chat < 100; chat++) {
        await world.cacheChat('chat-$chat', [
          for (var index = 0; index < 100; index++)
            messageRow(
              'm-$chat-$index',
              'chat-$chat',
              '第$chat个群里的第$index条消息 message number $index about nothing',
              minute: index % 60,
              day: 1 + index ~/ 60,
            ),
        ]);
      }
      write.stop();

      // Opened cold, as on the first search after the app starts.
      final cold = LocalSearchWorld(reopening: world);
      final read = Stopwatch()..start();
      final first = await cold.ids('第57个群里的第99条');
      read.stop();
      final warm = Stopwatch()..start();
      final second = await cold.ids('about nothing');
      warm.stop();

      expect(first, ['m-57-99']);
      expect(second, hasLength(25));
      // 10,000 messages. These are generous bounds for the debug VM; the
      // numbers are printed so a slowdown shows.
      // ignore: avoid_print
      print(
        'write 100x100: ${write.elapsedMilliseconds} ms, '
        'cold search: ${read.elapsedMilliseconds} ms, '
        'warm search: ${warm.elapsedMilliseconds} ms',
      );
      expect(write.elapsedMilliseconds, lessThan(20000));
      expect(read.elapsedMilliseconds, lessThan(5000));
      expect(warm.elapsedMilliseconds, lessThan(1500));
    });
  });
}
