import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';

void main() {
  testWidgets('opens auth as the default screen when signed out', (
    tester,
  ) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const WeCordApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('opens Chats as the default screen when signed in', (
    tester,
  ) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthUser(id: 'user-1', email: 'me@example.com'),
            ),
          ),
        ],
        child: const WeCordApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('No conversations yet'), findsOneWidget);
  });
}

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}
