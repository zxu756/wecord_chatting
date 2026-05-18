import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wecord/shared/api/supabase_providers.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final authProfileBootstrapProvider = FutureProvider<void>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.valueOrNull == null) {
    return;
  }

  await ref.watch(authRepositoryProvider).ensureCurrentUserProfile();
});

class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
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
  const SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

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
        'Profile setup is incomplete. Please sign out and sign up again, '
        'or try again after your profile metadata is fixed.',
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
