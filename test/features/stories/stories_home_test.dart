import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/home_sidebar.dart' show DailySidebarRow;
import 'package:wecord/features/home/phone_messages_panel.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/story_ring.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../home/phone_messages_panel_test.dart'
    show FakeChatsRepository, FakeSettingsRepository;
import 'stories_fakes.dart';

Profile _friend(String id, String name) {
  final now = DateTime.utc(2026, 5, 18);
  return Profile(
    id: id,
    username: name.toLowerCase().replaceAll(' ', ''),
    displayName: name,
    bio: '',
    createdAt: now,
    updatedAt: now,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: PhoneMessagesPanel()),
      ),
      GoRoute(
        path: '${ChatsScreen.path}/:conversationId',
        builder: (context, state) =>
            Text('Thread ${state.pathParameters['conversationId']}'),
      ),
    ],
  );
}

Widget _app(
  FakeStoriesRepository stories, {
  List<Profile> friends = const [],
  FakeStoryMediaPicker? picker,
  GoRouter? router,
  Widget? home,
}) {
  final chats = FakeChatsRepository()
    ..conversations = [
      const ConversationSummary(
        id: 'conversation-ada',
        type: ConversationType.direct,
        title: 'Ada Lovelace',
        unreadCount: 0,
        directUserId: 'user-2',
      ),
    ];
  return ProviderScope(
    overrides: [
      ...storiesOverrides(repository: stories, picker: picker),
      chatsRepositoryProvider.overrideWithValue(chats),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      authStateProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(id: 'user-1')),
      ),
      friendsProvider.overrideWith((ref) async => friends),
      friendStatusesProvider.overrideWith(
        (ref) async => const <String, FriendStatus>{},
      ),
      incomingFriendRequestsProvider.overrideWith((ref) async => const []),
      onlineUserIdsProvider.overrideWith((ref) => Stream.value(const {})),
      presenceStatusesProvider.overrideWith(
        (ref) => Stream.value(const <String, PresenceStatus>{}),
      ),
    ],
    child: router == null
        ? MaterialApp(
            theme: WeCordTheme.light(),
            home: home ?? const Scaffold(body: PhoneMessagesPanel()),
          )
        : MaterialApp.router(theme: WeCordTheme.light(), routerConfig: router),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late FakeStoriesRepository stories;
  final friends = [
    _friend('user-2', 'Ada Lovelace'),
    _friend('user-3', 'Grace Hopper'),
    _friend('user-4', 'Linus Pauling'),
  ];

  setUp(() {
    stories = FakeStoriesRepository()
      ..tray_ = [
        entry('user-2', name: 'Ada Lovelace', stories: 2, unseen: 1),
        entry('user-4', name: 'Linus Pauling', stories: 1, unseen: 0),
      ]
      ..stories['user-2'] = [
        story('a1', viewed: true, caption: 'Ada first'),
        story('a2', caption: 'Ada second'),
      ];
  });

  group('the row of friends', () {
    testWidgets('a friend with something new has an accent ring, '
        'one all seen a faint one, the others none', (tester) async {
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('story-ring-new-user-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-ring-seen-user-4')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('story-ring-new-user-3')), findsNothing);
      expect(
        find.byKey(const ValueKey('story-ring-seen-user-3')),
        findsNothing,
      );

      final ring = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('story-ring-new-user-2')),
      );
      final border = (ring.decoration as BoxDecoration).border! as Border;
      final context = tester.element(find.byType(PhoneMessagesPanel));
      final colors = Theme.of(context);
      // The accent, never the red of what needs the person.
      expect(border.top.color, isNot(colors.colorScheme.error));
      expect(border.top.width, 2.5);
    });

    testWidgets('the ring does not move the avatars', (tester) async {
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);
      final withRing = tester.getSize(
        find.byKey(const ValueKey('phone-friend-user-2')),
      );
      final without = tester.getSize(
        find.byKey(const ValueKey('phone-friend-user-3')),
      );
      expect(withRing, without);
    });

    testWidgets('a tap on a friend with a daily watches it', (tester) async {
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('phone-friend-user-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
      expect(find.text('Ada second'), findsOneWidget);
      expect(stories.viewed, ['a2']);
    });

    testWidgets('a friend with nothing up still opens the chat', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(stories, friends: friends, router: router));
      await _settle(tester);

      await tester.tap(find.byKey(const ValueKey('phone-friend-user-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
    });

    testWidgets('a long press on a friend with a daily opens the chat', (
      tester,
    ) async {
      final router = _router();
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(stories, friends: friends, router: router));
      await _settle(tester);

      await tester.longPress(find.byKey(const ValueKey('phone-friend-user-2')));
      await tester.pumpAndSettle();
      expect(find.text('Thread conversation-ada'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-viewer')), findsNothing);
    });

    testWidgets('the friend says there is a daily to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);
      expect(
        find.bySemanticsLabel('Ada Lovelace: new daily. Opens the daily.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Linus Pauling: daily. Opens the daily.'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('my own daily in the row', () {
    testWidgets('with none up, Daily is a way to post one', (tester) async {
      final picker = FakeStoryMediaPicker();
      await tester.pumpWidget(_app(stories, friends: friends, picker: picker));
      await _settle(tester);

      expect(find.byKey(const ValueKey('phone-home-daily')), findsOneWidget);
      expect(find.text('Daily'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('phone-home-daily')));
      await tester.pumpAndSettle();
      expect(find.text('New daily'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-source-photo')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-source-video')), findsOneWidget);
      // No camera on this device: only the library.
      expect(
        find.byKey(const ValueKey('story-source-camera-photo')),
        findsNothing,
      );
    });

    testWidgets('a phone with a camera offers it', (tester) async {
      final picker = FakeStoryMediaPicker(hasCamera: true);
      await tester.pumpWidget(_app(stories, friends: friends, picker: picker));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('phone-home-daily')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('story-source-camera-photo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('story-source-camera-video')),
        findsOneWidget,
      );
    });

    testWidgets('with some up, a tap watches them and a hold posts another', (
      tester,
    ) async {
      stories.tray_ = [
        entry('user-1', name: 'Me', stories: 1, unseen: 0, isMe: true),
        ...stories.tray_,
      ];
      stories.stories['user-1'] = [
        story('mine', authorId: 'user-1', caption: 'My own'),
      ];
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('story-ring-seen-user-1')),
        findsOneWidget,
      );
      await tester.longPress(find.byKey(const ValueKey('phone-home-daily')));
      await tester.pumpAndSettle();
      expect(find.text('New daily'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('phone-home-daily')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
      expect(find.text('My own'), findsOneWidget);
      // Nothing is marked viewed on my own.
      expect(stories.viewed, isEmpty);
    });

    testWidgets('Daily sits after Moments and before the friends', (
      tester,
    ) async {
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);
      double left(String key) =>
          tester.getTopLeft(find.byKey(ValueKey(key))).dx;
      expect(left('phone-home-moments'), lessThan(left('phone-home-daily')));
      expect(left('phone-home-daily'), lessThan(left('phone-friend-user-2')));
    });
  });

  group('the ring row of the desktop sidebar', () {
    Widget cluster() => const Scaffold(body: Center(child: StoryRingCluster()));

    testWidgets('shows friends with something new, a few at most', (
      tester,
    ) async {
      stories.tray_ = [
        entry('user-1', name: 'Me', isMe: true, unseen: 0),
        entry('user-2', name: 'Ada'),
        entry('user-3', name: 'Grace'),
        entry('user-4', name: 'Linus'),
        entry('user-5', name: 'Edsger'),
        entry('user-6', name: 'Seen', unseen: 0),
      ];
      await tester.pumpWidget(_app(stories, home: cluster()));
      await _settle(tester);

      expect(find.byKey(const ValueKey('story-ring-user-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-ring-user-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-ring-user-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-ring-user-5')), findsNothing);
      expect(find.byKey(const ValueKey('story-ring-user-6')), findsNothing);
      expect(find.byKey(const ValueKey('story-ring-user-1')), findsNothing);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('shows nothing when nobody has anything new', (tester) async {
      stories.tray_ = [entry('user-6', unseen: 0)];
      await tester.pumpWidget(_app(stories, home: cluster()));
      await _settle(tester);
      expect(find.byKey(const ValueKey('story-ring-cluster')), findsNothing);
    });

    testWidgets('a tap on a ring watches that friend', (tester) async {
      await tester.pumpWidget(_app(stories, home: cluster()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('story-ring-user-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
    });
  });

  group('Daily in the desktop sidebar', () {
    Widget row() => const Scaffold(
      body: Center(child: SizedBox(width: 260, child: DailySidebarRow())),
    );

    testWidgets('a click posts one, with no ring while none are up', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(stories, picker: FakeStoryMediaPicker(), home: row()),
      );
      await _settle(tester);
      expect(find.text('Daily'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-daily-mine')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home-daily')));
      await tester.pumpAndSettle();
      expect(find.text('New daily'), findsOneWidget);
    });

    testWidgets('with some up, my own ring watches them', (tester) async {
      stories.tray_ = [entry('user-1', name: 'Me', isMe: true, unseen: 0)];
      stories.stories['user-1'] = [
        story('mine', authorId: 'user-1', caption: 'My own'),
      ];
      await tester.pumpWidget(_app(stories, home: row()));
      await _settle(tester);

      expect(
        find.byKey(const ValueKey('story-ring-seen-user-1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('home-daily-mine')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
      expect(find.text('My own'), findsOneWidget);
    });
  });

  group('the row reads again', () {
    testWidgets('when the server says a daily appeared', (tester) async {
      stories.tray_ = [];
      await tester.pumpWidget(_app(stories, friends: friends));
      await _settle(tester);
      expect(find.byKey(const ValueKey('story-ring-new-user-2')), findsNothing);
      final before = stories.trayCalls;

      stories
        ..tray_ = [entry('user-2', name: 'Ada Lovelace')]
        ..signal(const StorySignal(StorySignalKind.story, 'a9'));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);

      expect(stories.trayCalls, greaterThan(before));
      expect(
        find.byKey(const ValueKey('story-ring-new-user-2')),
        findsOneWidget,
      );
    });
  });
}
