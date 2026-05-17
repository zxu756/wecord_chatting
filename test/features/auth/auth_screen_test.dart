import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';

void main() {
  testWidgets('submits sign in credentials', (tester) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      '  ada@example.com  ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(repository.signInCalls, [
      const SignInCall(email: 'ada@example.com', password: 'password123'),
    ]);
  });

  testWidgets('toggles to create account and submits profile details', (
    tester,
  ) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Create account'));
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'ada');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Ada Lovelace',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ada@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();

    expect(repository.signUpCalls, [
      const SignUpCall(
        email: 'ada@example.com',
        password: 'password123',
        username: 'ada',
        displayName: 'Ada Lovelace',
      ),
    ]);
  });

  testWidgets('shows controller validation errors', (tester) async {
    final repository = FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Create account'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();

    expect(find.text('Username is required.'), findsOneWidget);
    expect(repository.signUpCalls, isEmpty);
  });
}

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();

  AuthUser? user;
  final signInCalls = <SignInCall>[];
  final signUpCalls = <SignUpCall>[];

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {
    signInCalls.add(SignInCall(email: email, password: password));
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> ensureCurrentUserProfile() async {}

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
