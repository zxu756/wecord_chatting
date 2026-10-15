import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/features/auth/set_new_password_screen.dart';

import '../../shared/navigation/app_router_test.dart' as router_fakes;

class FakePasswordRecoveryRepository implements PasswordRecoveryRepository {
  final resetEmails = <String>[];
  final newPasswords = <String>[];
  final events = StreamController<void>.broadcast();
  Object? error;

  @override
  Future<void> sendPasswordReset(String email) async {
    if (error case final error?) {
      throw error;
    }
    resetEmails.add(email);
  }

  @override
  Stream<void> recoveries() => events.stream;

  @override
  Future<void> updatePassword(String password) async {
    if (error case final error?) {
      throw error;
    }
    newPasswords.add(password);
  }
}

class _RecordingHttpClient extends http.BaseClient {
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode('{}')),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  test('reset emails link back to the web app', () async {
    final httpClient = _RecordingHttpClient();
    final repository = SupabasePasswordRecoveryRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: httpClient,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      ),
      redirectUrl: () => 'https://wecord.jokebear.fyi',
    );

    await repository.sendPasswordReset('  ada@example.com ');

    final request = httpClient.requests.single;
    expect(request.url.path, '/auth/v1/recover');
    expect(
      request.url.queryParameters['redirect_to'],
      'https://wecord.jokebear.fyi',
    );
    expect(jsonDecode(request.body)['email'], 'ada@example.com');
  });

  test('new passwords are checked before saving', () {
    expect(newPasswordProblem('', ''), 'Password is required.');
    expect(
      newPasswordProblem('abc', 'abc'),
      'Passwords must be at least 6 characters.',
    );
    expect(
      newPasswordProblem('secret123', 'secret124'),
      'The passwords do not match.',
    );
    expect(newPasswordProblem('secret123', 'secret123'), isNull);
  });

  test('a reset link marks the recovery as pending until finished', () async {
    final recovery = FakePasswordRecoveryRepository();
    final container = ProviderContainer(
      overrides: [
        passwordRecoveryRepositoryProvider.overrideWithValue(recovery),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(passwordRecoveryPendingProvider), isFalse);
    recovery.events.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(passwordRecoveryPendingProvider), isTrue);

    container.read(passwordRecoveryPendingProvider.notifier).finish();
    expect(container.read(passwordRecoveryPendingProvider), isFalse);
  });

  testWidgets('forgot password sends a reset link to the typed email', (
    tester,
  ) async {
    final recovery = FakePasswordRecoveryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            router_fakes.FakeAuthRepository(),
          ),
          passwordRecoveryRepositoryProvider.overrideWithValue(recovery),
        ],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ada@example.com',
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Reset your password'), findsOneWidget);
    final field = find.byKey(const ValueKey('forgot-password-email'));
    expect(tester.widget<TextField>(field).controller!.text, 'ada@example.com');

    await tester.enterText(field, '');
    await tester.tap(find.text('Send link'));
    await tester.pump();
    expect(find.text('Email is required.'), findsOneWidget);
    expect(recovery.resetEmails, isEmpty);

    await tester.enterText(field, ' grace@example.com ');
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(recovery.resetEmails, ['grace@example.com']);
    expect(find.text('Reset your password'), findsNothing);
    expect(
      find.text('Check your email for a link to reset your password.'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password is only offered for signing in', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            router_fakes.FakeAuthRepository(),
          ),
        ],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Create account'));
    await tester.pump();
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('opening a reset link asks for a new password, then goes home', (
    tester,
  ) async {
    final recovery = FakePasswordRecoveryRepository();
    final authState = StreamController<AuthUser?>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            router_fakes.FakeAuthRepository(),
          ),
          authStateProvider.overrideWith((ref) => authState.stream),
          passwordRecoveryRepositoryProvider.overrideWithValue(recovery),
        ],
        child: const WeCordApp(),
      ),
    );

    // The link signs the user in and reports the recovery.
    authState.add(const AuthUser(id: 'user-1', email: 'ada@example.com'));
    recovery.events.add(null);
    await tester.pumpAndSettle();

    expect(find.byType(SetNewPasswordScreen), findsOneWidget);
    expect(
      find.text('Choose a new password for ada@example.com.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('new-password')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-new-password')),
      'secret12',
    );
    await tester.tap(find.text('Save password'));
    await tester.pump();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(recovery.newPasswords, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('confirm-new-password')),
      'secret123',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(recovery.newPasswords, ['secret123']);
    expect(find.byType(SetNewPasswordScreen), findsNothing);
    expect(find.text('Your password was changed.'), findsOneWidget);
    expect(find.text('Find or start a conversation'), findsOneWidget);
  });

  testWidgets('a failed password change keeps the page with the error', (
    tester,
  ) async {
    final recovery = FakePasswordRecoveryRepository()
      ..error = const AuthException(
        'New password should be different from the old password.',
      );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthUser(id: 'user-1', email: 'ada@example.com'),
            ),
          ),
          passwordRecoveryRepositoryProvider.overrideWithValue(recovery),
        ],
        child: const MaterialApp(home: SetNewPasswordScreen()),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('new-password')),
      'secret123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-new-password')),
      'secret123',
    );
    await tester.tap(find.text('Save password'));
    await tester.pumpAndSettle();

    expect(
      find.text('New password should be different from the old password.'),
      findsOneWidget,
    );
    expect(find.text('Save password'), findsOneWidget);
  });
}
