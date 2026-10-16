import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';
import 'package:wecord/features/search/search_highlight.dart';
import 'package:wecord/features/search/search_query.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  group('SupabaseMessageSearchRepository', () {
    late List<(String, Map<String, dynamic>)> calls;
    late Object? Function(String name) respond;
    late SupabaseMessageSearchRepository repository;

    setUp(() {
      calls = [];
      respond = (_) => null;
      repository = SupabaseMessageSearchRepository((name, params) async {
        calls.add((name, params));
        return respond(name);
      });
    });

    test('search sends the query, filters, scope, sort and cursor', () async {
      respond = (_) => {
        'results': [
          {
            'id': 'm1',
            'conversation_id': 'c1',
            'sender_id': 'u1',
            'sender_name': 'Ada',
            'sender_avatar_url': 'avatars/ada.png',
            'type': 'file',
            'body': '',
            'attachment': {
              'kind': 'video',
              'name': 'clip.mp4',
              'mime_type': 'video/mp4',
              'bucket': 'chat-files',
              'path': 'c1/clip.mp4',
              'size': 10,
            },
            'created_at': '2026-10-02T09:01:00+00:00',
            'edited_at': null,
            'rank': 0.25,
            'pinned': true,
            'conversation': {
              'id': 'c1',
              'type': 'thread',
              'title': 'Launch',
              'circle_id': 'circle-1',
              'circle_name': 'Launch Crew',
              'parent_conversation_id': 'c0',
              'parent_title': 'general',
            },
          },
        ],
        'next_cursor': {
          'id': 'm1',
          'created_at': '2026-10-02T09:01:00+00:00',
          'rank': 0.25,
        },
        'total': 1000,
        'total_capped': true,
        'conversations': [
          {'conversation_id': 'c1', 'count': 700},
          {'conversation_id': 'c2', 'count': 300},
        ],
      };
      final page = await repository.search(
        const MessageSearchRequest(
          text: 'ship -draft',
          filters: MessageSearchFilters(
            fromIds: ['u1'],
            mentionIds: ['u2'],
            placeIds: ['c1'],
            has: {SearchHas.video},
            pinned: true,
          ),
          scope: CircleScope(circleId: 'circle-1'),
          sort: MessageSearchSort.relevance,
          pageSize: 10,
          cursor: {'id': 'm0', 'created_at': '2026-10-01T00:00:00Z'},
        ),
      );

      final (name, params) = calls.single;
      expect(name, 'search_messages');
      expect(params, {
        'query': 'ship -draft',
        'filters': {
          'from': ['u1'],
          'mentions': ['u2'],
          'in': ['c1'],
          'has': ['video'],
          'pinned': true,
        },
        'scope': {'type': 'circle', 'id': 'circle-1'},
        'sort': 'relevance',
        'max_results': 10,
        'cursor': {'id': 'm0', 'created_at': '2026-10-01T00:00:00Z'},
      });

      final hit = page.hits.single;
      expect(hit.message.type, MessageType.file);
      expect(hit.message.fileAttachment?.isVideo, isTrue);
      expect(hit.message.isPinned, isTrue);
      expect(hit.senderName, 'Ada');
      expect(hit.rank, 0.25);
      expect(hit.place?.type, ConversationType.thread);
      expect(hit.place?.label, 'Launch');
      expect(hit.place?.subtitle, '# general · Launch Crew');
      expect(page.total, 1000);
      expect(page.totalCapped, isTrue);
      expect(page.nextCursor?['id'], 'm1');
      expect(page.conversationCounts, {'c1': 700, 'c2': 300});
    });

    test('context and suggestions call their functions', () async {
      respond = (name) => switch (name) {
        'search_message_context' => {
          'before': [
            {
              'id': 'm0',
              'conversation_id': 'c1',
              'sender_id': 'u1',
              'sender_name': 'Ada',
              'type': 'text',
              'body': 'before',
              'created_at': '2026-10-02T09:00:00Z',
            },
          ],
          'after': <Object>[],
        },
        _ => [
          {
            'id': 'u1',
            'username': 'ada',
            'display_name': 'Ada',
            'avatar_url': null,
          },
        ],
      };
      final context = await repository.context('m1');
      expect(context.before.single.message.body, 'before');
      expect(context.after, isEmpty);
      expect(calls.last.$2, {
        'target_message_id': 'm1',
        'before_count': 1,
        'after_count': 1,
      });

      final people = await repository.suggestPeople(
        'ad',
        scope: const ConversationScope(conversationId: 'c1'),
      );
      expect(people.single.username, 'ada');
      expect(calls.last.$1, 'search_filter_suggestions');
      expect(calls.last.$2, {
        'kind': 'user',
        'prefix': 'ad',
        'scope': {'type': 'conversation', 'id': 'c1'},
        'max_results': 8,
      });

      respond = (_) => [
        {'id': 'c1', 'type': 'channel', 'title': 'general'},
      ];
      final places = await repository.suggestPlaces('gen');
      expect(places.single.label, '# general');
      expect(places.single.filterValue, 'general');
      expect(calls.last.$2['kind'], 'conversation');
      expect(calls.last.$2['scope'], {'type': 'everywhere'});
    });

    test('an unexpected response is an error', () async {
      respond = (_) => 'nope';
      expect(
        repository.search(const MessageSearchRequest(text: 'x')),
        throwsFormatException,
      );
    });
  });

  group('MessageSearchFilters.toJson', () {
    test('days become local-day instants', () {
      final json = const MessageSearchFilters(
        before: SearchDate(2026, 10, 10),
        after: SearchDate(2026, 10, 1),
      ).toJson();
      // After a day is after it ends; before a day is before it starts.
      expect(
        DateTime.parse(json['after']! as String),
        DateTime(2026, 10, 2).toUtc(),
      );
      expect(
        DateTime.parse(json['before']! as String),
        DateTime(2026, 10, 10).toUtc(),
      );
    });

    test('during narrows a range to the day', () {
      final json = const MessageSearchFilters(
        during: SearchDate(2026, 10, 5),
        after: SearchDate(2026, 9, 1),
      ).toJson();
      expect(
        DateTime.parse(json['after']! as String),
        DateTime(2026, 10, 5).toUtc(),
      );
      expect(
        DateTime.parse(json['before']! as String),
        DateTime(2026, 10, 6).toUtc(),
      );
    });

    test('no filters is an empty object', () {
      expect(const MessageSearchFilters().toJson(), isEmpty);
    });
  });

  group('highlighting', () {
    test('finds terms ignoring case and merges overlaps', () {
      expect(findSearchMatches('Ship it, SHIP it', ['ship']), [
        (start: 0, end: 4),
        (start: 9, end: 13),
      ]);
      expect(findSearchMatches('deployment', ['deploy', 'ploym']), [
        (start: 0, end: 7),
      ]);
      expect(findSearchMatches('我们下周三发布新版本', ['发布']), [(start: 5, end: 7)]);
      expect(findSearchMatches('anything', ['', '  ']), isEmpty);
    });

    test('long texts start near the first match', () {
      final text = '${List.filled(30, 'word').join(' ')} the target here';
      final snippet = searchSnippet(text, ['target']);
      expect(snippet, startsWith('…'));
      expect(snippet, contains('target here'));
      expect(snippet.length, lessThan(text.length));
      expect(searchSnippet('short target', ['target']), 'short target');
    });
  });

  group('recent searches', () {
    test('newest first, unique, at most ten, cleared on demand', () async {
      final store = _MemoryStore(['old']);
      final container = ProviderContainer(
        overrides: [recentSearchesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final recent = container.read(recentSearchesProvider.notifier);
      container.read(recentSearchesProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recentSearchesProvider), ['old']);

      recent.add('ship');
      recent.add('  ');
      recent.add('OLD');
      expect(container.read(recentSearchesProvider), ['OLD', 'ship']);
      for (var i = 0; i < 12; i++) {
        recent.add('q$i');
      }
      expect(container.read(recentSearchesProvider), hasLength(10));
      expect(container.read(recentSearchesProvider).first, 'q11');
      recent.remove('q11');
      expect(container.read(recentSearchesProvider).first, 'q10');
      recent.clear();
      expect(container.read(recentSearchesProvider), isEmpty);
      expect(store.searches, isEmpty);
    });
  });
}

class _MemoryStore implements RecentSearchesStore {
  _MemoryStore(this.searches);

  List<String> searches;

  @override
  Future<List<String>> load() async => searches;

  @override
  Future<void> save(List<String> searches) async => this.searches = searches;
}
