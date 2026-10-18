import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/features/privacy/devices_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/config/site_url.dart';
import 'package:wecord/shared/l10n/l10n.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final authProfileBootstrapProvider = FutureProvider<void>((ref) async {
  // Only a different person re-runs this: a token refresh must not, since
  // the gate would swap the whole app for a spinner while it runs.
  final userId = ref.watch(
    authStateProvider.select((state) => state.value?.id),
  );
  if (userId == null) {
    return;
  }

  await ref.watch(authRepositoryProvider).ensureCurrentUserProfile();
  // Tells the server what this device is, for the Devices list.
  unawaited(
    ref
        .read(devicesRepositoryProvider)
        .registerCurrentDevice()
        .catchError((Object _) {}),
  );
});

/// The signed-in person. Equal by value: Auth re-emits the same person on
/// every token refresh and user re-read, and those must not look like a
/// change to the providers and pages that watch [authStateProvider].
class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

abstract interface class AuthRepository {
  AuthUser? get currentUser;

  Stream<AuthUser?> authStateChanges();

  Future<void> signIn(String email, String password);

  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  );

  Future<void> ensureCurrentUserProfile();

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(
    this._client, {
    this._redirectUrl = authRedirectUrl,
  });

  final SupabaseClient _client;

  /// Where links in auth emails lead back to (see [authRedirectUrl]).
  final String Function() _redirectUrl;

  @override
  AuthUser? get currentUser => _toAuthUser(_client.auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield currentUser;
    yield* _client.auth.onAuthStateChange.map((state) {
      return _toAuthUser(state.session?.user);
    });
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    // Asked for: the signed-out event that follows is not an anomaly.
    errorReporter.expectSignOut();
    // Live location shares end with the session: nothing keeps sending (or
    // looks as if it does) once this person is signed out.
    try {
      await _client
          .rpc<void>('stop_my_live_locations')
          .timeout(const Duration(seconds: 3));
    } on Object {
      // Offline: the shares end at their time.
    }
    await _client.auth.signOut();
  }

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      // The confirmation link opens the web app.
      emailRedirectTo: _redirectUrl(),
      data: {
        'username': username.trim().toLowerCase(),
        'display_name': displayName.trim(),
      },
    );
  }

  @override
  Future<void> ensureCurrentUserProfile() async {
    if (_client.auth.currentSession == null) {
      return;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final username = (metadata['username'] as String?)?.trim().toLowerCase();
    final displayName = (metadata['display_name'] as String?)?.trim();

    if (username == null ||
        displayName == null ||
        username.isEmpty ||
        displayName.isEmpty) {
      throw StateError(
        tr(
          'Profile setup is incomplete. Please sign out and sign up again, '
          'or try again after your profile metadata is fixed.',
        ),
      );
    }

    final existingProfile = await _client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existingProfile != null) {
      return;
    }

    await _client.from('profiles').insert({
      'id': user.id,
      'username': username,
      'display_name': displayName,
      'bio': '',
    });
  }
}

AuthUser? _toAuthUser(User? user) {
  if (user == null) {
    return null;
  }
  return AuthUser(id: user.id, email: user.email);
}
