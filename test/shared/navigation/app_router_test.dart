import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/circles/circle_channel_thread_screen.dart';
import 'package:wecord/features/circles/circle_invite_screen.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/navigation/app_router.dart';

void main() {
  test('auth updates for the same user do not refresh the router', () {
    final notifier = AuthRouterNotifier(
      const AsyncData(AuthUser(id: 'user-1', email: 'ada@example.com')),
    );
    var refreshes = 0;
    notifier.addListener(() => refreshes++);

    // A token refresh or a re-read user reports the same account again.
    notifier.authState = const AsyncData(
      AuthUser(id: 'user-1', email: 'ada@example.com'),
    );
    expect(refreshes, 0);

    notifier.authState = const AsyncData(null);
    expect(refreshes, 1);
    notifier.authState = const AsyncData(AuthUser(id: 'user-2'));
    expect(refreshes, 2);
    notifier.authState = const AsyncLoading();
    expect(refreshes, 3);
  });

  testWidgets('opens loading before auth resolves to signed out', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: const WeCordApp(),
      ),
    );

    await tester.pump();
    expect(find.text('Loading'), findsOneWidget);

    authState.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('opens Home as the default screen when signed in', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: const WeCordApp(),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    // Phones get the edge-to-edge home without a tab bar.
    expect(find.byKey(const ValueKey('phone-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-user-panel')), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(repository.ensureProfileCalls, 1);
  });

  testWidgets(
    'signed-in bootstrap failure shows retryable error instead of Home',
    (tester) async {
      final repository = FakeAuthRepository()
        ..ensureProfileError = StateError('duplicate username');
      final authState = StreamController<AuthUser?>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            authStateProvider.overrideWith((ref) => authState.stream),
          ],
          child: const WeCordApp(),
        ),
      );

      authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
      await tester.pumpAndSettle();

      expect(find.text('Profile setup failed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-home')), findsNothing);
      expect(repository.ensureProfileCalls, 1);

      repository.ensureProfileError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('phone-home')), findsOneWidget);
      expect(find.text('No conversations yet'), findsOneWidget);
      expect(repository.ensureProfileCalls, 2);
    },
  );

  testWidgets('incomplete profile bootstrap metadata blocks the shell', (
    tester,
  ) async {
    final repository = FakeAuthRepository()
      ..ensureProfileError = StateError(
        'Profile setup is incomplete. Please sign out and sign up again, '
        'or try again after your profile metadata is fixed.',
      );
    final authState = StreamController<AuthUser?>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: const WeCordApp(),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    expect(find.text('Profile setup failed'), findsOneWidget);
    expect(find.textContaining('Profile setup is incomplete'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Chats'), findsNothing);
    expect(find.text('No conversations yet'), findsNothing);
    expect(repository.ensureProfileCalls, 1);
  });

  test('appRouterProvider returns a stable router across auth changes', () {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWith((ref) => authState.stream),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);

    authState.add(null);
    container.pump();
    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    container.pump();

    expect(container.read(appRouterProvider), same(router));
  });

  testWidgets('routes signed-in users to global message search', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    router.go(GlobalMessageSearchScreen.path);
    await tester.pumpAndSettle();

    expect(find.byType(GlobalMessageSearchScreen), findsOneWidget);
  });

  testWidgets('circle channels open with the circle member list', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    router.go(
      '/chats/conversation-1',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircleChannelThreadScreen), findsOneWidget);
    expect(find.byType(ChatThreadScreen), findsOneWidget);

    router.go(
      '/chats/conversation-2',
      extra: const ChatThreadRouteExtra(
        title: 'Ada',
        type: ConversationType.direct,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircleChannelThreadScreen), findsNothing);
    expect(find.byType(ChatThreadScreen), findsOneWidget);
  });

  testWidgets('circle channels open full screen over the phone home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();
    Finder phoneHome() => find.byKey(const ValueKey('phone-home'));
    expect(phoneHome(), findsOneWidget);

    // Deep link without extras still opens the circle channel.
    router.go('/circles/circle-1/channels/conversation-1');
    await tester.pump();
    await tester.pump();
    final screen = tester.widget<CircleChannelThreadScreen>(
      find.byType(CircleChannelThreadScreen),
    );
    expect(screen.circleId, 'circle-1');
    expect(screen.conversationId, 'conversation-1');
    expect(find.byType(ChatThreadScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(phoneHome(), findsNothing);

    // The old Messages tab's link lands on the phone home.
    router.go('/chats');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CircleChannelThreadScreen), findsNothing);
    expect(phoneHome(), findsOneWidget);

    router.push(
      CircleChannelThreadScreen.pathFor('circle-1', 'conversation-1'),
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<CircleChannelThreadScreen>(
            find.byType(CircleChannelThreadScreen),
          )
          .title,
      '# general',
    );

    // Threads of a circle channel open on the same route, as threads.
    router.push(
      CircleChannelThreadScreen.pathFor('circle-1', 'thread-conversation-1'),
      extra: const ChatThreadRouteExtra(
        title: 'Plans',
        type: ConversationType.thread,
        circleId: 'circle-1',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widget<CircleChannelThreadScreen>(
            find.byType(CircleChannelThreadScreen).last,
          )
          .conversationType,
      ConversationType.thread,
    );
  });

  testWidgets('routes signed-in users to profile pages', (tester) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    final profileDataSource = FakeProfileDataSource()
      ..rpcResult = [
        {
          'id': 'user-2',
          'username': 'ada',
          'display_name': 'Ada',
          'alias': null,
          'avatar_url': null,
          'bio': '',
          'relationship_status': 'none',
          'incoming_request_id': null,
          'outgoing_request_id': null,
          'is_blocked_by_me': false,
          'has_blocked_me': false,
        },
      ];
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
          profileRepositoryProvider.overrideWithValue(
            ProfileRepository.withDataSource(profileDataSource),
          ),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    router.go('/profile/user-2');
    await tester.pumpAndSettle();

    expect(find.byType(UserProfileScreen), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
  });

  testWidgets('invite links opened signed out return after sign-in', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
          circleInvitePreviewProvider.overrideWith(
            (ref, code) async => CircleInvitePreview(
              code: code,
              alreadyMember: false,
              circle: const CircleInvitePreviewCircle(
                id: 'circle-1',
                name: 'Book Club',
                memberCount: 2,
              ),
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    router.go('/invite/abcdefgh23');
    await tester.pump();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/loading?from=%2Finvite%2Fabcdefgh23',
    );

    authState.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/auth?from=%2Finvite%2Fabcdefgh23',
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/invite/abcdefgh23',
    );
    expect(find.byType(CircleInviteScreen), findsOneWidget);
    expect(find.text('Book Club'), findsOneWidget);
  });

  testWidgets('signed-out redirects ignore non-invite locations', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(null);
    await tester.pumpAndSettle();
    router.go('/auth?from=%2Fsettings');
    await tester.pumpAndSettle();

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
  });
}

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  var ensureProfileCalls = 0;
  Object? ensureProfileError;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> ensureCurrentUserProfile() async {
    ensureProfileCalls += 1;
    if (ensureProfileError case final error?) {
      throw error;
    }
  }

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}

class FakeProfileDataSource implements ProfileDataSource {
  Object? rpcResult;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    return rpcResult;
  }
}
