import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/config/site_url.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The shortest password Supabase Auth accepts by default.
const minPasswordLength = 6;

final passwordRecoveryRepositoryProvider = Provider<PasswordRecoveryRepository>(
  (ref) {
    try {
      return SupabasePasswordRecoveryRepository(
        ref.watch(supabaseClientProvider),
      );
    } on AssertionError {
      return const UninitializedPasswordRecoveryRepository();
    }
  },
);

/// Whether the user opened a password reset link and still has to choose
/// a new password. The router shows SetNewPasswordScreen while it is true.
final passwordRecoveryPendingProvider =
    NotifierProvider<PasswordRecoveryPending, bool>(
      PasswordRecoveryPending.new,
    );

class PasswordRecoveryPending extends Notifier<bool> {
  @override
  bool build() {
    final subscription = ref
        .watch(passwordRecoveryRepositoryProvider)
        .recoveries()
        .listen((_) => state = true, onError: (Object _) {});
    ref.onDispose(subscription.cancel);
    return false;
  }

  /// The new password is saved, or the user chose to keep the old one.
  void finish() => state = false;
}

/// Forgotten passwords: the reset email, the arrival from its link, and
/// the new password.
abstract interface class PasswordRecoveryRepository {
  /// Emails [email] a link back to the app (see [authRedirectUrl]) that
  /// signs them in to set a new password. Supabase does not say whether
  /// the address has an account.
  Future<void> sendPasswordReset(String email);

  /// Fires when the app was opened from a reset link; the user is then
  /// signed in.
  Stream<void> recoveries();

  /// Sets the signed-in user's password.
  Future<void> updatePassword(String password);
}

class SupabasePasswordRecoveryRepository implements PasswordRecoveryRepository {
  const SupabasePasswordRecoveryRepository(
    this._client, {
    String Function() redirectUrl = authRedirectUrl,
  }) : _redirectUrl = redirectUrl;

  final SupabaseClient _client;
  final String Function() _redirectUrl;

  @override
  Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: _redirectUrl(),
    );
  }

  @override
  Stream<void> recoveries() {
    // The link is handled while Supabase starts, before anyone listens;
    // the auth stream replays its latest event.
    return _client.auth.onAuthStateChange
        .where((state) => state.event == AuthChangeEvent.passwordRecovery)
        .map((_) {});
  }

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }
}

class UninitializedPasswordRecoveryRepository
    implements PasswordRecoveryRepository {
  const UninitializedPasswordRecoveryRepository();

  @override
  Future<void> sendPasswordReset(String email) {
    throw StateError(
      'Supabase must be initialized before resetting passwords.',
    );
  }

  @override
  Stream<void> recoveries() => const Stream.empty();

  @override
  Future<void> updatePassword(String password) {
    throw StateError('Supabase must be initialized before changing passwords.');
  }
}

/// Why [password] and [confirmation] cannot be the new password, or null.
String? newPasswordProblem(String password, String confirmation) {
  if (password.isEmpty) {
    return tr('Password is required.');
  }
  if (password.length < minPasswordLength) {
    return tr('Passwords must be at least {count} characters.', {
      'count': minPasswordLength,
    });
  }
  if (password != confirmation) {
    return tr('The passwords do not match.');
  }
  return null;
}

/// A readable message for a failed reset or password change.
String passwordRecoveryErrorMessage(Object error) {
  if (error is AuthException) {
    return tr(error.message);
  }
  return tr('Something went wrong. Try again.');
}
