import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';

final authControllerProvider =
    StateNotifierProvider.autoDispose<AuthController, AuthActionState>((ref) {
      return AuthController(ref.watch(authRepositoryProvider));
    });

class AuthActionState {
  const AuthActionState({this.isLoading = false, this.errorMessage});

  final bool isLoading;
  final String? errorMessage;

  AuthActionState copyWith({bool? isLoading, String? errorMessage}) {
    return AuthActionState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthController extends StateNotifier<AuthActionState> {
  AuthController(this._repository) : super(const AuthActionState());

  final AuthRepository _repository;

  Future<void> signIn(String email, String password) async {
    await _run(() {
      return _repository.signIn(email.trim(), password);
    });
  }

  Future<void> signUp(
    String username,
    String displayName,
    String email,
    String password,
  ) async {
    final validationError = _validateSignUp(
      username: username,
      displayName: displayName,
      email: email,
      password: password,
    );

    if (validationError != null) {
      state = AuthActionState(errorMessage: validationError);
      return;
    }

    await _run(() {
      return _repository.signUp(
        email.trim(),
        password,
        username,
        displayName,
      );
    });
  }

  Future<void> signOut() async {
    await _run(_repository.signOut);
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AuthActionState(isLoading: true);
    try {
      await action();
      state = const AuthActionState();
    } catch (error) {
      state = AuthActionState(errorMessage: _errorMessage(error));
    }
  }
}

String? _validateSignUp({
  required String username,
  required String displayName,
  required String email,
  required String password,
}) {
  if (username.trim().isEmpty) {
    return 'Username is required.';
  }
  if (displayName.trim().isEmpty) {
    return 'Display name is required.';
  }
  if (email.trim().isEmpty) {
    return 'Email is required.';
  }
  if (password.isEmpty) {
    return 'Password is required.';
  }
  return null;
}

String _errorMessage(Object error) {
  if (error is AuthException) {
    return error.message;
  }

  final message = error.toString();
  const exceptionPrefix = 'Exception: ';
  if (message.startsWith(exceptionPrefix)) {
    return message.substring(exceptionPrefix.length);
  }
  return message;
}
