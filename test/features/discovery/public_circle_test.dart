import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/discovery/circle_discovery_settings_screen.dart';
import 'package:wecord/features/discovery/public_circle_repository.dart';
import 'package:wecord/features/discovery/public_circle_screen.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../circles/announcement_channels_test.dart' show RecordingRpc;
import 'discovery_fakes.dart';

const _detail = CircleDetail(
  circle: CircleSummary(
    id: 'circle-1',
    name: 'Pixel Painters',
    memberCount: 3,
    channelCount: 2,
    currentUserRole: 'owner',
  ),
  members: [],
  channels: [],
  posts: [],
);

Map<String, dynamic> _settings({bool isPublic = true}) => {
  'is_public': isPublic,
  'description': 'Pixel art.',
  'category': 'art',
  'language': 'en',
  'tags': <String>[],
  'listed_at': '2026-10-16T00:00:00Z',
};

void main() {
  group('PublicCircleRepository', () {
    test('reads and writes the short name', () async {
      final rpc = RecordingRpc({
        'get_circle_slug': (_) => {'slug': 'pixel-club'},
        'set_circle_slug': (params) => {'slug': params['new_slug']},
      });
      final repository = PublicCircleRepository(rpc.call);

      expect(await repository.slug('circle-1'), 'pixel-club');
      expect(await repository.setSlug('circle-1', ' pixel-new '), 'pixel-new');
      expect(rpc.calls.last.$2, {
        'target_circle_id': 'circle-1',
        'new_slug': 'pixel-new',
      });
      // Empty removes it.
      await repository.setSlug('circle-1', '  ');
      expect(rpc.calls.last.$2['new_slug'], isNull);
      await repository.setSlug('circle-1', null);
      expect(rpc.calls.last.$2['new_slug'], isNull);
    });

    test('no short name is null, not an empty string', () async {
      final rpc = RecordingRpc({
        'get_circle_slug': (_) => {'slug': null},
        'set_circle_slug': (_) => {'slug': ''},
      });
      final repository = PublicCircleRepository(rpc.call);
      expect(await repository.slug('c'), isNull);
      expect(await repository.setSlug('c', null), isNull);
    });

    test('names why saving failed', () async {
      Future<CircleSlugProblem> problemFor(String message) async {
        final repository = PublicCircleRepository(
          (_, _) async => throw StateError(message),
        );
        try {
          await repository.setSlug('c', 'abc');
        } on CircleSlugException catch (error) {
          return error.problem;
        }
        fail('expected an exception');
      }

      expect(
        await problemFor(
          'PostgrestException(code: 23505, That short name is taken)',
        ),
        CircleSlugProblem.taken,
      );
      expect(
        await problemFor(
          'PostgrestException(code: 22023, That short name is reserved)',
        ),
        CircleSlugProblem.reserved,
      );
      expect(
        await problemFor(
          'PostgrestException(code: 22023, A short name is 3 to 32 letters)',
        ),
        CircleSlugProblem.invalid,
      );
      expect(
        await problemFor(
          'PostgrestException(code: PB429, Too many short name changes)',
        ),
        CircleSlugProblem.rateLimited,
      );
      expect(await problemFor('offline'), CircleSlugProblem.other);
    });

    test('resolving gives the circle, or null for anything hidden', () async {
      final rpc = RecordingRpc({
        'resolve_circle_slug': (params) => params['circle_slug'] == 'pixel-club'
            ? {'circle_id': 'circle-9', 'is_member': true}
            : null,
      });
      final repository = PublicCircleRepository(rpc.call);
      final found = await repository.resolve('pixel-club');
      expect(found?.circleId, 'circle-9');
      expect(found?.isMember, isTrue);
      expect(await repository.resolve('secret-club'), isNull);
    });
  });

  group('the short name in Discovery settings', () {
    Future<RecordingRpc> pump(
      WidgetTester tester, {
      String? slug,
      bool slugFails = false,
      Object? Function(Map<String, dynamic>)? onSet,
    }) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rpc = RecordingRpc({
        'get_circle_discovery': (_) => _settings(),
        'get_circle_slug': (_) =>
            slugFails ? throw StateError('no') : {'slug': slug},
        'set_circle_discovery': (_) => _settings(),
        'set_circle_slug': onSet ?? (params) => {'slug': params['new_slug']},
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      openCircleDiscoverySettings(context, _detail),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return rpc;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('discovery-settings-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the saved name with its link, and copies it', (
      tester,
    ) async {
      await pump(tester, slug: 'pixel-club');
      expect(find.text('Web page'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('discovery-slug-field')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'pixel-club',
      );
      expect(
        find.text('https://wecord.jokebear.fyi/c/pixel-club'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('discovery-slug-copy')), findsOneWidget);
    });

    testWidgets('saves a new name in lower case, after the settings', (
      tester,
    ) async {
      final rpc = await pump(tester);
      expect(find.byKey(const ValueKey('discovery-slug-link')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('discovery-slug-field')),
        'Pixel-Club',
      );
      await tester.pump();
      // Typed but not yet saved: the link shows, "Copy link" waits for Save.
      expect(
        find.text('https://wecord.jokebear.fyi/c/pixel-club'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('discovery-slug-copy')), findsNothing);
      await save(tester);

      final names = [for (final call in rpc.calls) call.$1];
      expect(
        names.indexOf('set_circle_discovery'),
        lessThan(names.indexOf('set_circle_slug')),
      );
      expect(rpc.calls.firstWhere((call) => call.$1 == 'set_circle_slug').$2, {
        'target_circle_id': 'circle-1',
        'new_slug': 'pixel-club',
      });
      // The page closed after saving.
      expect(find.text('Web page'), findsNothing);
    });

    testWidgets('does not call the server for a name that cannot work', (
      tester,
    ) async {
      final rpc = await pump(tester);
      for (final (input, message) in [
        ('ab', 'A short name is 3 to 32 letters, digits and hyphens.'),
        ('-abc', 'A short name is 3 to 32 letters, digits and hyphens.'),
        ('admin', 'That short name is reserved.'),
      ]) {
        await tester.enterText(
          find.byKey(const ValueKey('discovery-slug-field')),
          input,
        );
        await tester.pump();
        await save(tester);
        expect(find.text(message), findsOneWidget, reason: input);
      }
      expect(rpc.calls.any((call) => call.$1 == 'set_circle_slug'), isFalse);
      expect(
        rpc.calls.any((call) => call.$1 == 'set_circle_discovery'),
        isFalse,
      );
    });

    testWidgets('says when the name is taken and stays on the page', (
      tester,
    ) async {
      await pump(
        tester,
        onSet: (_) => throw StateError('code: 23505 That short name is taken'),
      );
      await tester.enterText(
        find.byKey(const ValueKey('discovery-slug-field')),
        'pixel-club',
      );
      await tester.pump();
      await save(tester);
      expect(find.text('That short name is taken.'), findsOneWidget);
      expect(find.text('Web page'), findsOneWidget);
    });

    testWidgets('clearing the name removes it', (tester) async {
      final rpc = await pump(tester, slug: 'pixel-club');
      await tester.enterText(
        find.byKey(const ValueKey('discovery-slug-field')),
        '',
      );
      await tester.pump();
      await save(tester);
      expect(rpc.calls.firstWhere((call) => call.$1 == 'set_circle_slug').$2, {
        'target_circle_id': 'circle-1',
        'new_slug': null,
      });
    });

    testWidgets('an unchanged name is not saved again', (tester) async {
      final rpc = await pump(tester, slug: 'pixel-club');
      await save(tester);
      expect(rpc.calls.any((call) => call.$1 == 'set_circle_slug'), isFalse);
    });

    testWidgets('without the short name feature the rest still works', (
      tester,
    ) async {
      final rpc = await pump(tester, slugFails: true);
      expect(find.text('Web page'), findsNothing);
      expect(find.text('Description'), findsOneWidget);
      await save(tester);
      expect(
        rpc.calls.any((call) => call.$1 == 'set_circle_discovery'),
        isTrue,
      );
      expect(rpc.calls.any((call) => call.$1 == 'set_circle_slug'), isFalse);
    });
  });

  group('/c/<slug> in the app', () {
    Future<GoRouter> pump(WidgetTester tester, RecordingRpc rpc) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/c/pixel-club',
        routes: [
          GoRoute(
            path: '/c/:slug',
            builder: (context, state) =>
                PublicCircleScreen(slug: state.pathParameters['slug']!),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/circles/:id',
            builder: (context, state) =>
                Scaffold(body: Text('circle ${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
          child: MaterialApp.router(
            theme: WeCordTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('a member goes straight into the circle', (tester) async {
      final rpc = RecordingRpc({
        'resolve_circle_slug': (_) => {
          'circle_id': 'circle-9',
          'is_member': true,
        },
      });
      await pump(tester, rpc);
      expect(find.text('circle circle-9'), findsOneWidget);
      expect(rpc.calls.map((c) => c.$1), ['resolve_circle_slug']);
      expect(rpc.calls.single.$2, {'circle_slug': 'pixel-club'});
    });

    testWidgets('anyone else gets the preview, over the circle card', (
      tester,
    ) async {
      final rpc = RecordingRpc({
        'resolve_circle_slug': (_) => {
          'circle_id': 'circle-9',
          'is_member': false,
        },
        'discoverable_circle_preview': (_) => {
          ...previewJson('circle-9'),
          'name': 'Pixel Club',
        },
        'join_public_circle': (params) => params['target_circle_id'],
      });
      await pump(tester, rpc);
      expect(find.text('Pixel Club'), findsWidgets);
      // The preview sheet opened by itself: it has the rules and Join.
      expect(find.text('Be kind'), findsOneWidget);
      expect(
        rpc.calls.map((c) => c.$1),
        contains('discoverable_circle_preview'),
      );

      await tester.tap(find.byKey(const ValueKey('discovery-join')));
      await tester.pumpAndSettle();
      expect(
        rpc.calls.where((call) => call.$1 == 'join_public_circle').single.$2,
        {'target_circle_id': 'circle-9'},
      );
      expect(find.text('circle circle-9'), findsOneWidget);
    });

    testWidgets('a circle that is hidden is just not available', (
      tester,
    ) async {
      final rpc = RecordingRpc({'resolve_circle_slug': (_) => null});
      await pump(tester, rpc);
      expect(find.text('This circle is not available'), findsOneWidget);
      expect(
        find.text('The link may be wrong, or the circle may not be public.'),
        findsOneWidget,
      );
      expect(rpc.calls.map((c) => c.$1), ['resolve_circle_slug']);
      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a failed lookup can be retried', (tester) async {
      var fail = true;
      final rpc = RecordingRpc({
        'resolve_circle_slug': (_) {
          if (fail) {
            throw StateError('offline');
          }
          return null;
        },
      });
      await pump(tester, rpc);
      expect(find.text('Could not load this circle'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('This circle is not available'), findsOneWidget);
    });
  });
}
