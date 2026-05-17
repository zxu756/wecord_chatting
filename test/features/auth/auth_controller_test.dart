import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_controller.dart';
import 'package:wecord/features/auth/auth_repository.dart';

void main() {
  test('signIn trims the email before calling the repository', () async {
    final repository = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .signIn('  Ada@Example.COM  ', 'password123');

    expect(repository.signInCalls, [
      const SignInCall(email: 'Ada@Example.COM', password: 'password123'),
    ]);
    expect(container.read(authControllerProvider).errorMessage, isNull);
  });

  test('signIn exposes loading while the repository call is pending', () async {
    final repository = FakeAuthRepository();
    final signInCompleter = Completer<void>();
    repository.onSignIn = () => signInCompleter.future;
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final future = container
        .read(authControllerProvider.notifier)
        .signIn('me@example.com', 'password123');

    expect(container.read(authControllerProvider).isLoading, isTrue);

    signInCompleter.complete();
    await future;

    expect(container.read(authControllerProvider).isLoading, isFalse);
  });

  test(
    'signUp validates required fields before calling the repository',
    () async {
      final repository = FakeAuthRepository();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      await container
          .read(authControllerProvider.notifier)
          .signUp('', 'Display Name', 'me@example.com', 'password123');

      expect(repository.signUpCalls, isEmpty);
      expect(
        container.read(authControllerProvider).errorMessage,
        'Username is required.',
      );
    },
  );

  test('signUp passes valid account details to the repository', () async {
    final repository = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .signUp('Ada_L', 'Ada Lovelace', 'ada@example.com', 'password123');

    expect(repository.signUpCalls, [
      const SignUpCall(
        username: 'ada_l',
        displayName: 'Ada Lovelace',
        email: 'ada@example.com',
        password: 'password123',
      ),
    ]);
    expect(container.read(authControllerProvider).errorMessage, isNull);
  });

  test('signUp rejects usernames that do not match profile rules', () async {
    final repository = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    for (final username in ['ab', 'ada-l', 'ada.lovelace', 'a' * 25]) {
      await container
          .read(authControllerProvider.notifier)
          .signUp(username, 'Ada Lovelace', 'ada@example.com', 'password123');
    }

    expect(repository.signUpCalls, isEmpty);
    expect(
      container.read(authControllerProvider).errorMessage,
      'Username must be 3-24 characters using lowercase letters, numbers, or underscores.',
    );
  });

  test('repository failures are exposed as form errors', () async {
    final repository = FakeAuthRepository();
    repository.onSignIn = () => throw Exception('Bad credentials');
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .signIn('me@example.com', 'wrong-password');

    expect(container.read(authControllerProvider).isLoading, isFalse);
    expect(
      container.read(authControllerProvider).errorMessage,
      'Bad credentials',
    );
  });

  test('profile bootstrap failures surface through provider state', () async {
    final repository = FakeAuthRepository();
    final authState = StreamController<AuthUser?>();
    repository.onEnsureCurrentUserProfile = () {
      throw StateError('duplicate username');
    };
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWith((ref) => authState.stream),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(authState.close);

    final errorState = Completer<AsyncValue<void>>();
    container.listen<AsyncValue<void>>(authProfileBootstrapProvider, (_, next) {
      if (next.hasError && !errorState.isCompleted) {
        errorState.complete(next);
      }
    }, fireImmediately: true);

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    final bootstrap = await errorState.future;

    expect(repository.ensureProfileCalls, 1);
    expect(
      bootstrap.error,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'duplicate username',
      ),
    );
  });
}

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();

  Future<void> Function()? onSignIn;
  Future<void> Function()? onSignUp;
  Future<void> Function()? onSignOut;
  Future<void> Function()? onEnsureCurrentUserProfile;
  AuthUser? user;
  var ensureProfileCalls = 0;
  final signInCalls = <SignInCall>[];
  final signUpCalls = <SignUpCall>[];

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {
    signInCalls.add(SignInCall(email: email, password: password));
    await onSignIn?.call();
  }

  @override
  Future<void> signOut() async {
    await onSignOut?.call();
  }

  @override
  Future<void> ensureCurrentUserProfile() async {
    ensureProfileCalls += 1;
    await onEnsureCurrentUserProfile?.call();
  }

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {
    signUpCalls.add(
      SignUpCall(
        email: email,
        password: password,
        username: username,
        displayName: displayName,
      ),
    );
    await onSignUp?.call();
  }
}

class SignInCall {
  const SignInCall({required this.email, required this.password});

  final String email;
  final String password;

  @override
  bool operator ==(Object other) {
    return other is SignInCall &&
        other.email == email &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(email, password);
}

class SignUpCall {
  const SignUpCall({
    required this.email,
    required this.password,
    required this.username,
    required this.displayName,
  });

  final String email;
  final String password;
  final String username;
  final String displayName;

  @override
  bool operator ==(Object other) {
    return other is SignUpCall &&
        other.email == email &&
        other.password == password &&
        other.username == username &&
        other.displayName == displayName;
  }

  @override
  int get hashCode => Object.hash(email, password, username, displayName);
}
