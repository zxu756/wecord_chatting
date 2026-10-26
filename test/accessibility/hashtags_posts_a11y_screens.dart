// Topics and circle posts 2.0 (B8), for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: the circle's posts as a list
// and as a grid, the featured filter, a post on its own page, the edit sheet,
// the topics list of Moments, a topic's page, the composer with topic
// suggestions and the search strip, at large text, narrow and with Care mode
// on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/search/message_search_controller.dart';
import 'package:wecord/shared/models/circle.dart';

import '../features/moments/moments_fakes.dart';
import '../features/wallpapers/wallpaper_fakes.dart' show settleWithImages;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

CirclePost _circlePost(
  String id, {
  String? title,
  String body = 'Some text',
  List<String> tags = const [],
  bool featured = false,
  int minutesAgo = 30,
  bool withComments = false,
  bool own = false,
}) {
  final createdAt = DateTime.now().toUtc().subtract(
    Duration(minutes: minutesAgo),
  );
  return CirclePost(
    id: id,
    circleId: 'circle-1',
    authorId: own ? me.id : bart.id,
    body: body,
    title: title,
    tags: tags,
    featuredAt: featured ? createdAt : null,
    canFeaturePost: true,
    createdAt: createdAt,
    updatedAt: createdAt,
    author: own ? me : bart,
    isOwnPost: own,
    canManagePost: true,
    likeCount: 12,
    commentCount: withComments ? 2 : 0,
    comments: [
      if (withComments) ...[
        CirclePostComment(
          id: '$id-c1',
          postId: id,
          authorId: grace.id,
          body: 'Count me in, I will bring the long lens.',
          createdAt: createdAt,
          updatedAt: createdAt,
          author: grace,
        ),
        CirclePostComment(
          id: '$id-c2',
          postId: id,
          authorId: linus.id,
          body: 'Same.',
          createdAt: createdAt,
          updatedAt: createdAt,
          author: linus,
        ),
      ],
    ],
  );
}

/// The sample circle with posts that have titles, topics and a featured one.
void _posts(PhoneWorld world) {
  final base = circleDetail();
  world.circles.detail = CircleDetail(
    circle: base.circle,
    categories: base.categories,
    channels: base.channels,
    roles: base.roles,
    members: base.members,
    posts: [
      _circlePost(
        'a',
        title: 'Sunrise hike to Mission Peak on Saturday, all levels welcome',
        body:
            'Meet at the trailhead at 5:30. Headlamps required. #hiking #weekend',
        tags: ['hiking', 'weekend'],
        featured: true,
        withComments: true,
        own: true,
      ),
      _circlePost(
        'b',
        title: 'Photo dump',
        body: 'Pictures from the lake last week.',
        tags: ['photos', 'lake'],
        minutesAgo: 300,
      ),
      _circlePost(
        'c',
        body: 'A post without a title or any topic.',
        minutesAgo: 900,
      ),
    ],
  );
}

Future<void> _openPosts(
  WidgetTester tester,
  PhoneWorld world, {
  String location = '/circles/circle-1/posts',
}) async {
  _posts(world);
  world.extraOverrides = [
    ...world.extraOverrides,
    circleRpcProvider.overrideWithValue((name, params) async => true),
  ];
  await world.open(tester, location);
  await settle(tester);
}

Future<void> _grid(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Grid view'));
  await settle(tester);
}

Future<void> _openMoments(
  WidgetTester tester,
  PhoneWorld world,
  String location,
) async {
  final repository =
      FakeMomentsRepository(
          posts: [
            post('p1', body: 'First light on the #lake, then #breakfast.'),
            post(
              'p2',
              authorId: 'user-3',
              authorName: 'Grace Hopper',
              body:
                  'Packing for the #lake trip: tent, stove, warm layers, a good book '
                  'and far too many snacks for two nights.',
              minutesAgo: 240,
            ),
          ],
        )
        ..topicList = [
          for (final (tag, count) in [
            ('lake', 4),
            ('breakfast', 2),
            ('a-topic-with-quite-a-long-name', 1),
          ])
            MomentTopic(
              tag: tag,
              postCount: count,
              lastAt: DateTime.utc(2026, 10, 27, 8),
            ),
        ];
  world.extraOverrides = momentsOverrides(repository: repository);
  await world.open(tester, location);
  await settleWithImages(tester);
}

final hashtagsPostsA11yScreens = <A11yScreen>[
  A11yScreen('circle-posts-list', (tester, world) async {
    await _openPosts(tester, world);
  }),
  A11yScreen('circle-posts-list-large-text', (tester, world) async {
    await _openPosts(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('circle-posts-list-narrow', (tester, world) async {
    await _openPosts(tester, world);
  }, viewport: smallPhone),
  A11yScreen('circle-posts-list-care-mode', (tester, world) async {
    _care(world);
    await _openPosts(tester, world);
  }),
  A11yScreen('circle-posts-grid', (tester, world) async {
    await _openPosts(tester, world);
    await _grid(tester);
  }),
  A11yScreen('circle-posts-grid-narrow', (tester, world) async {
    await _openPosts(tester, world);
    await _grid(tester);
  }, viewport: smallPhone),
  A11yScreen('circle-posts-grid-large-text', (tester, world) async {
    await _openPosts(tester, world);
    await _grid(tester);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('circle-posts-featured', (tester, world) async {
    await _openPosts(
      tester,
      world,
      location: '/circles/circle-1/posts?featured=1',
    );
  }),
  A11yScreen('circle-posts-topic', (tester, world) async {
    await _openPosts(
      tester,
      world,
      location: '/circles/circle-1/posts?tag=lake',
    );
  }),
  A11yScreen('circle-post-page', (tester, world) async {
    await _openPosts(tester, world, location: '/circles/circle-1/posts/a');
  }),
  A11yScreen('circle-post-page-narrow', (tester, world) async {
    await _openPosts(tester, world, location: '/circles/circle-1/posts/a');
  }, viewport: smallPhone),
  A11yScreen('circle-post-menu', (tester, world) async {
    await _openPosts(tester, world);
    await tester.tap(find.byTooltip('Post actions').first);
    await settle(tester);
  }),
  A11yScreen('circle-post-edit-sheet', (tester, world) async {
    await _openPosts(tester, world);
    await tester.tap(find.byTooltip('Post actions').first);
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
  }),
  A11yScreen('circle-post-edit-sheet-narrow', (tester, world) async {
    await _openPosts(tester, world);
    await tester.tap(find.byTooltip('Post actions').first);
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
  }, viewport: smallPhone),
  A11yScreen('moment-topics', (tester, world) async {
    await _openMoments(tester, world, '/moments/topics');
  }),
  A11yScreen('moment-topics-large-text', (tester, world) async {
    await _openMoments(tester, world, '/moments/topics');
  }, viewport: notchedPhoneLargeText),
  A11yScreen('moment-topics-narrow', (tester, world) async {
    await _openMoments(tester, world, '/moments/topics');
  }, viewport: smallPhone),
  A11yScreen('moment-topics-care-mode', (tester, world) async {
    _care(world);
    await _openMoments(tester, world, '/moments/topics');
  }),
  A11yScreen('moment-topics-empty', (tester, world) async {
    world.extraOverrides = momentsOverrides(
      repository: FakeMomentsRepository(),
    );
    await world.open(tester, '/moments/topics');
    await settle(tester);
  }),
  A11yScreen('moment-tag-page', (tester, world) async {
    await _openMoments(tester, world, '/moments/tag/lake');
  }),
  A11yScreen('moment-tag-page-narrow', (tester, world) async {
    await _openMoments(tester, world, '/moments/tag/lake');
  }, viewport: smallPhone),
  A11yScreen('moment-tag-page-empty', (tester, world) async {
    await _openMoments(tester, world, '/moments/tag/nothing');
  }),
  A11yScreen('moment-composer-topics', (tester, world) async {
    await _openMoments(tester, world, '/moments/compose');
    await tester.enterText(
      find.byKey(const ValueKey('moment-text')),
      'Morning walk #sunrise',
    );
    await tester.pump();
  }),
  A11yScreen('message-search-topic', (tester, world) async {
    world.extraOverrides = [
      ...world.extraOverrides,
      circleRpcProvider.overrideWithValue((name, params) async {
        return {
          'tag': 'lake',
          'moments': 3,
          'circles': [
            {'circle_id': 'circle-1', 'name': 'Close Friends', 'post_count': 5},
          ],
        };
      }),
    ];
    await world.open(tester, GlobalMessageSearchScreen.path);
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      '#lake',
    );
    await tester.pump(MessageSearchController.debounce);
    await settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
  }),
];
