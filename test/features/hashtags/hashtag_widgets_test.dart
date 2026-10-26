// Topic widgets and clients (B8): the editor, the search strip, the posts
// repository, the featured-posts tab kind and the guard / audit words.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_posts_repository.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/group_tabs/group_tab_kind_featured_posts.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/hashtags/hashtag_overview.dart';
import 'package:wecord/features/hashtags/hashtag_widgets.dart';
import 'package:wecord/shared/ui/ui.dart';

typedef _Call = ({String name, Map<String, dynamic> params});

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  group('the topic editor', () {
    testWidgets('adds a cleaned topic, refuses a bad one, removes one', (
      tester,
    ) async {
      var tags = <String>[];
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => HashtagEditor(
              tags: tags,
              onChanged: (next) => setState(() => tags = next),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '#Lake');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tags, ['lake']);

      await tester.enterText(find.byType(TextField), 'two words');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tags, ['lake']);
      expect(
        find.text(
          'A topic is 1 to 30 letters, digits or characters, without spaces.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(WeCordChip, '#lake'));
      await tester.pump();
      expect(tags, isEmpty);
    });

    testWidgets('stops at the most topics a post can have', (tester) async {
      var tags = [for (var i = 0; i < 10; i++) 't$i'];
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => HashtagEditor(
              tags: tags,
              onChanged: (next) => setState(() => tags = next),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'extra');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tags.length, 10);
      expect(find.textContaining('at most'), findsOneWidget);
    });

    testWidgets('a suggestion adds its topic', (tester) async {
      var tags = <String>[];
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => HashtagEditor(
              tags: tags,
              suggestions: const ['city'],
              onChanged: (next) => setState(() => tags = next),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(WeCordChip, '#city'));
      await tester.pump();
      expect(tags, ['city']);
    });
  });

  group('the search strip', () {
    final calls = <_Call>[];

    Future<void> open(WidgetTester tester, String query, Object result) async {
      calls.clear();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: SingleChildScrollView(
                child: HashtagSearchStrip(query: query),
              ),
            ),
          ),
          GoRoute(
            path: '/moments/tag/:tag',
            builder: (c, s) => const Text('T'),
          ),
          GoRoute(
            path: '/circles/:id/posts',
            builder: (c, s) => const Text('P'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            circleRpcProvider.overrideWithValue((name, params) async {
              calls.add((name: name, params: params));
              return result;
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows where a #topic is used and opens it', (tester) async {
      await open(tester, 'trip #Lake', {
        'tag': 'lake',
        'moments': 2,
        'circles': [
          {'circle_id': 'c1', 'name': 'Hikers', 'post_count': 4},
        ],
      });
      expect(calls.single.name, 'hashtag_overview');
      expect(calls.single.params['p_tag'], 'lake');
      expect(find.text('Topic #lake'), findsOneWidget);
      expect(find.text('2 Moments'), findsOneWidget);
      expect(find.text('Hikers'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-topic-circle-c1')));
      await tester.pumpAndSettle();
      expect(find.text('P'), findsOneWidget);
    });

    testWidgets('shows nothing without a #topic or without any use', (
      tester,
    ) async {
      await open(tester, 'plain words', {'tag': 'x', 'moments': 0});
      expect(calls, isEmpty);
      expect(find.byKey(const ValueKey('search-topic-strip')), findsNothing);

      await open(tester, '#quiet', {
        'tag': 'quiet',
        'moments': 0,
        'circles': [],
      });
      expect(calls.single.params['p_tag'], 'quiet');
      expect(find.byKey(const ValueKey('search-topic-strip')), findsNothing);
    });
  });

  group('the posts repository', () {
    test('sends the title and the cleaned topics', () async {
      final calls = <_Call>[];
      final repository = CirclePostsRepository((name, params) async {
        calls.add((name: name, params: params));
        return name == 'create_circle_post' ? 'new-id' : true;
      });

      final id = await repository.create(
        circleId: 'c1',
        body: '  Hello #lake ',
        title: '  A   long\n title ',
        tags: ['#Lake', 'Lake', 'two words'],
      );
      expect(id, 'new-id');
      expect(calls.single.name, 'create_circle_post');
      expect(calls.single.params['target_circle_id'], 'c1');
      expect(calls.single.params['body'], 'Hello #lake');
      expect(calls.single.params['post_title'], 'A long title');
      expect(calls.single.params['post_tags'], ['lake']);

      await repository.create(circleId: 'c1', body: 'x', title: '   ');
      expect(calls.last.params['post_title'], isNull);
      expect(calls.last.params['post_tags'], isEmpty);

      await repository.update(postId: 'p1', body: 'y', tags: ['city']);
      expect(calls.last.name, 'update_circle_post');
      expect(calls.last.params['target_post_id'], 'p1');
      expect(calls.last.params['post_tags'], ['city']);

      expect(await repository.setFeatured(postId: 'p1', featured: true), true);
      expect(calls.last.name, 'set_circle_post_featured');
      expect(calls.last.params, {'target_post_id': 'p1', 'featured': true});
    });
  });

  group('the featured posts tab kind', () {
    testWidgets('is offered in circle channels only and opens the filter', (
      tester,
    ) async {
      late BuildContext inside;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              inside = c;
              return const SizedBox();
            },
          ),
        ),
      );
      GroupTabContext context({String? circleId}) => GroupTabContext(
        context: inside,
        conversationId: 'g',
        title: 'Hike',
        circleId: circleId,
      );

      expect(featuredPostsGroupTabKind.kind, GroupTabKinds.featuredPosts);
      expect(featuredPostsGroupTabKind.canAdd!(context()), isFalse);
      expect(featuredPostsGroupTabKind.canAdd!(context(circleId: 'c')), isTrue);
      expect(featuredPostsGroupTabKind.pick, isNull);
    });

    test('the path of the featured filter', () {
      expect(
        circlePostsPath('c1', featured: true),
        '/circles/c1/posts?featured=1',
      );
      expect(circlePostsPath('c1', tag: 'lake'), '/circles/c1/posts?tag=lake');
      expect(circlePostsPath('c1'), '/circles/c1/posts');
    });
  });

  group('the AI guard', () {
    test('knows circle posts as a kind of item', () {
      expect(GuardItemType.values.map((t) => t.name), contains('circlePost'));
    });
  });
}
