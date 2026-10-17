import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/profile_bootstrap_gate.dart';
import 'package:wecord/features/privacy/devices_repository.dart';

/// Auth that re-emits the signed-in person, as Supabase does on every
/// token refresh: a new AuthUser object with the same id each time.
class _RefreshingAuth implements AuthRepository {
  final _events = StreamController<AuthUser?>.broadcast();
  var ensureProfileCalls = 0;

  void emit(String id) => _events.add(AuthUser(id: id, email: '$id@x.test'));

  @override
  AuthUser? get currentUser => const AuthUser(id: 'u1', email: 'u1@x.test');

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield currentUser;
    yield* _events.stream;
  }

  @override
  Future<void> ensureCurrentUserProfile() async => ensureProfileCalls++;

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}

  @override
  Future<void> signOut() async {}
}

class _NoDevices implements DevicesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  test('the same person re-emitted is equal, a different one is not', () {
    expect(
      const AuthUser(id: 'u1', email: 'a@x.test'),
      const AuthUser(id: 'u1', email: 'a@x.test'),
    );
    expect(
      const AuthUser(id: 'u1', email: 'a@x.test') ==
          const AuthUser(id: 'u2', email: 'a@x.test'),
      isFalse,
    );
  });

  testWidgets(
    'a token refresh neither re-runs the profile bootstrap nor blanks the app',
    (tester) async {
      final auth = _RefreshingAuth();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            devicesRepositoryProvider.overrideWithValue(_NoDevices()),
          ],
          child: const MaterialApp(
            home: ProfileBootstrapGate(child: Text('the app')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('the app'), findsOneWidget);
      expect(auth.ensureProfileCalls, 1);

      // Opening a page used to refresh the token, which re-ran the
      // bootstrap, which swapped the app for a spinner and rebuilt the
      // page, which refreshed the token again: a loop that ended in a
      // rate-limited refresh and a sign-out.
      for (var refresh = 0; refresh < 5; refresh++) {
        auth.emit('u1');
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('the app'), findsOneWidget);
      }
      expect(auth.ensureProfileCalls, 1);
    },
  );

  testWidgets('a different person runs the bootstrap again', (tester) async {
    final auth = _RefreshingAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          devicesRepositoryProvider.overrideWithValue(_NoDevices()),
        ],
        child: const MaterialApp(
          home: ProfileBootstrapGate(child: Text('the app')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(auth.ensureProfileCalls, 1);

    auth.emit('u2');
    await tester.pump();
    await tester.pump();
    expect(auth.ensureProfileCalls, 2);
    expect(find.text('the app'), findsOneWidget);
  });
}
