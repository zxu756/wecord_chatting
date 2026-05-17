import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wecord/shared/api/supabase_providers.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
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
    final response = await _client.auth.signUp(email: email, password: password);
    final user = response.user ?? _client.auth.currentUser;

    if (user == null) {
      throw const AuthException('Account created, but no user session returned.');
    }

    await _client.from('profiles').upsert({
      'id': user.id,
      'username': username.trim().toLowerCase(),
      'display_name': displayName.trim(),
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
