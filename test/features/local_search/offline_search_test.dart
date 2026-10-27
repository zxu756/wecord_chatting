import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_protection_card.dart';
import 'package:wecord/features/local_search/offline_search_repository.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/features/search/message_search_models.dart';
import 'package:wecord/features/search/message_search_repository.dart';
import 'package:wecord/features/search/recent_searches.dart';

import '../chats/global_message_search_screen_test.dart'
    show FakeChatsRepository, FakeSearchRepository, MemoryRecentSearchesStore, hit, dm;
import 'local_search_fakes.dart';

class _Failing extends FakeSearchRepository {
  _Failing(this.error);

  final Object error;
  var calls = 0;

  @override
  Future<SearchPage> search(MessageSearchRequest request) async {
    calls++;
    throw error;
  }
}

void main() {
  late LocalSearchWorld world;
  var offline = false;

  OfflineFallbackSearchRepository repositoryOver(MessageSearchRepository online) =>
      OfflineFallbackSearchRepository(
        online: online,
        local: world.search,
        deviceOffline: () => offline,
      );

  setUp(() async {
    offline = false;
    world = LocalSearchWorld();
    await world.cacheChat('c1', [messageRow('m1', 'c1', 'lunch at noon')]);
  });

  group('OfflineFallbackSearchRepository', () {
    test('uses the server alone while it answers', () async {
      final server = FakeSearchRepository()
        ..pages.add(const SearchPage(hits: [], total: 0));

      final page = await repositoryOver(server).search(request('lunch'));

      expect(page.offline, isFalse);
      expect(page.hits, isEmpty, reason: 'the local match is not mixed in');
      expect(server.requests, hasLength(1));
    });

    test('answers from the device when the server cannot be reached', () async {
      for (final error in <Object>[
        const SocketException('no route'),
        TimeoutException('slow'),
      ]) {
        final server = _Failing(error);

        final page = await repositoryOver(server).search(request('lunch'));

        expect(page.offline, isTrue, reason: '$error');
        expect([for (final hit in page.hits) hit.id], ['m1']);
      }
    });

    test('shows a server error as an error, not as local results', () async {
      final server = _Failing(StateError('boom'));

      await expectLater(
        repositoryOver(server).search(request('lunch')),
        throwsStateError,
      );
    });

    test('does not ask the server when the device has no network', () async {
      offline = true;
      final server = _Failing(StateError('should not be asked'));

      final page = await repositoryOver(server).search(request('lunch'));

      expect(page.offline, isTrue);
      expect(server.calls, 0);
    });

    test('the next page goes where the first one came from', () async {
      for (var i = 0; i < 3; i++) {
        await world.cacheChat('c${i + 2}', [
          messageRow('x$i', 'c${i + 2}', 'lunch again $i', minute: i + 1),
        ]);
      }
      offline = true;
      final server = FakeSearchRepository();
      final repository = repositoryOver(server);

      final first = await repository.search(request('lunch', pageSize: 2));
      expect(first.nextCursor, isNotNull);
      // The connection is back, but the cursor is the device's.
      offline = false;
      final second = await repository.search(
        request('lunch', pageSize: 2, cursor: first.nextCursor),
      );
      expect(second.offline, isTrue);
      expect(server.requests, isEmpty);

      // A server cursor goes to the server.
      await repository.search(request('lunch', cursor: const {'rank': 1}));
      expect(server.requests, hasLength(1));
    });

    test('suggestions and context also fall back', () async {
      offline = true;
      final server = _Failing(StateError('should not be asked'));
      final repository = repositoryOver(server);

      expect(await repository.suggestPeople('ba'), isNotEmpty);
      expect((await repository.context('m1')).before, isEmpty);
    });
  });

  group('the search page', () {
    Future<void> pump(
      WidgetTester tester,
      FakeSearchRepository search,
    ) async {
      final router = GoRouter(
        initialLocation: GlobalMessageSearchScreen.path,
        routes: [
          GoRoute(
            path: GlobalMessageSearchScreen.path,
            builder: (context, state) => GlobalMessageSearchScreen(
              launch: GlobalMessageSearchScreen.launchFrom(
                state.uri.queryParameters,
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(FakeChatsRepository()),
            messageSearchRepositoryProvider.overrideWithValue(search),
            recentSearchesStoreProvider.overrideWithValue(
              MemoryRecentSearchesStore(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('message-search-field')),
        'ship',
      );
      await tester.pump(MessageSearchController.debounce);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('says the results are offline results', (tester) async {
      final search = FakeSearchRepository()
        ..pages.add(
          SearchPage(
            hits: [hit('m1', 'conv-1', 'Ada', 'We ship it on Friday', place: dm)],
            offline: true,
          ),
        );

      await pump(tester, search);

      expect(find.byKey(const ValueKey('offline-search-notice')), findsOneWidget);
      expect(find.text('Offline results'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-hit-m1')), findsOneWidget);
    });

    testWidgets('says nothing for the server\'s own results', (tester) async {
      final search = FakeSearchRepository()
        ..pages.add(
          SearchPage(
            hits: [hit('m1', 'conv-1', 'Ada', 'We ship it on Friday', place: dm)],
          ),
        );

      await pump(tester, search);

      expect(find.byKey(const ValueKey('offline-search-notice')), findsNothing);
    });
  });

  group('IndexedChatCache.measure', () {
    test('counts the search index in the size of the chat data', () async {
      final bare = await world.inner.measure(meId);

      final withIndex = await world.cache.measure(meId);

      expect(bare.messages['c1'], greaterThan(0));
      expect(withIndex.messages['c1'], greaterThan(bare.messages['c1']!));
    });
  });

  group('LocalProtectionCard', () {
    Future<void> pumpCard(WidgetTester tester, LocalProtection protection) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LocalProtectionGroup(protection: protection),
            ),
          ),
        ),
      );
    }

    testWidgets('says plainly what each platform gives', (tester) async {
      await pumpCard(tester, LocalProtection.keychain);
      expect(find.text('Saved chats are encrypted'), findsOneWidget);

      await pumpCard(tester, LocalProtection.browserKey);
      expect(find.text('Encrypted in this browser, with limits'), findsOneWidget);

      await pumpCard(tester, LocalProtection.session);
      expect(find.text('Encrypted for this session only'), findsOneWidget);

      await pumpCard(tester, LocalProtection.unavailable);
      expect(find.text('Saved chats are switched off'), findsOneWidget);
    });
  });
}
