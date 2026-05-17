import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/navigation/app_router.dart';

void main() {
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

  testWidgets('opens Chats as the default screen when signed in', (
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

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(repository.ensureProfileCalls, 1);
  });

  testWidgets(
    'signed-in bootstrap failure shows retryable error instead of Chats',
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
      expect(find.text('Chats'), findsNothing);
      expect(repository.ensureProfileCalls, 1);

      repository.ensureProfileError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Chats'), findsWidgets);
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
