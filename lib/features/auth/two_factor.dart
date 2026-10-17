import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Digits in an authenticator app's code.
const twoFactorCodeLength = 6;

/// The name authenticator apps show for the account.
const twoFactorIssuer = 'WeCord';

final twoFactorRepositoryProvider = Provider<TwoFactorRepository>((ref) {
  try {
    return SupabaseTwoFactorRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedTwoFactorRepository();
  }
});

/// Whether the signed-in user still has to enter a code from their
/// authenticator app (their session is at aal1 and they have a verified
/// factor, so it can reach aal2). The router shows TwoFactorChallengeScreen
/// while it is true.
final twoFactorPendingProvider = NotifierProvider<TwoFactorPending, bool>(
  TwoFactorPending.new,
);

class TwoFactorPending extends Notifier<bool> {
  @override
  bool build() {
    final repository = ref.watch(twoFactorRepositoryProvider);
    final subscription = repository.sessionChanges().listen(
      (_) => state = repository.needsSecondFactor(),
      onError: (Object _) {},
    );
    ref.onDispose(subscription.cancel);
    return repository.needsSecondFactor();
  }

  /// Checks the session again, e.g. after entering a code.
  void refresh() {
    state = ref.read(twoFactorRepositoryProvider).needsSecondFactor();
  }
}

/// The current user's verified authenticator, or null when two-step
/// verification is off.
final twoFactorFactorProvider = FutureProvider.autoDispose<String?>((ref) {
  return ref.watch(twoFactorRepositoryProvider).verifiedFactorId();
});

/// A new authenticator to add: shown as a QR code ([uri]) and as text
/// ([secret]), then confirmed with a code.
class TwoFactorSetup {
  const TwoFactorSetup({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  final String factorId;
  final String secret;

  /// The otpauth:// link the QR code holds.
  final String uri;
}

/// Two-step verification with an authenticator app (Supabase Auth MFA,
/// TOTP).
abstract interface class TwoFactorRepository {
  /// Whether this session must still be verified with a code.
  bool needsSecondFactor();

  /// Fires when the session changes (sign in, verification, sign out).
  Stream<void> sessionChanges();

  /// The verified authenticator's id, or null.
  Future<String?> verifiedFactorId();

  /// Starts adding an authenticator (dropping unfinished ones first).
  Future<TwoFactorSetup> enroll();

  /// Finishes adding the authenticator with a [code] from it.
  Future<void> confirmEnrollment({
    required String factorId,
    required String code,
  });

  /// Drops an authenticator that was never confirmed.
  Future<void> cancelEnrollment(String factorId);

  /// Turns two-step verification off; needs a current [code].
  Future<void> disable({required String factorId, required String code});

  /// Verifies this session with a [code] after signing in.
  Future<void> verifySignIn(String code);
}

class SupabaseTwoFactorRepository implements TwoFactorRepository {
  const SupabaseTwoFactorRepository(this._client);

  final SupabaseClient _client;

  GoTrueMFAApi get _mfa => _client.auth.mfa;

  @override
  bool needsSecondFactor() {
    if (_client.auth.currentSession == null) {
      return false;
    }
    final level = _mfa.getAuthenticatorAssuranceLevel();
    return level.currentLevel == AuthenticatorAssuranceLevels.aal1 &&
        level.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  @override
  Stream<void> sessionChanges() => _client.auth.onAuthStateChange.map((_) {});

  @override
  Future<String?> verifiedFactorId() async {
    // Not mfa.listFactors(): it refreshes the session first, so a page that
    // shows this would refresh the token every time it is built, and a
    // burst of refreshes is rate limited, which signs the app out. getUser
    // reads the same factors fresh from the server without a refresh.
    final user = (await _client.auth.getUser()).user;
    return _verifiedTotp(user?.factors);
  }

  @override
  Future<TwoFactorSetup> enroll() async {
    final factors = await _mfa.listFactors();
    for (final factor in factors.all) {
      if (factor.factorType == FactorType.totp &&
          factor.status != FactorStatus.verified) {
        await _mfa.unenroll(factor.id);
      }
    }
    final response = await _mfa.enroll(
      factorType: FactorType.totp,
      issuer: twoFactorIssuer,
      friendlyName: 'Authenticator app',
    );
    final totp = response.totp;
    if (totp == null) {
      throw const AuthException('The server did not return a secret.');
    }
    return TwoFactorSetup(
      factorId: response.id,
      secret: totp.secret,
      uri: totp.uri,
    );
  }

  @override
  Future<void> confirmEnrollment({
    required String factorId,
    required String code,
  }) async {
    await _mfa.challengeAndVerify(factorId: factorId, code: code.trim());
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {
    await _mfa.unenroll(factorId);
  }

  @override
  Future<void> disable({required String factorId, required String code}) async {
    // Removing a verified factor needs an aal2 session, which the code
    // gives.
    await _mfa.challengeAndVerify(factorId: factorId, code: code.trim());
    await _mfa.unenroll(factorId);
  }

  @override
  Future<void> verifySignIn(String code) async {
    var factorId = _verifiedTotp(_client.auth.currentUser?.factors);
    factorId ??= (await _mfa.listFactors()).totp.firstOrNull?.id;
    if (factorId == null) {
      throw const AuthException('No authenticator is set up.');
    }
    await _mfa.challengeAndVerify(factorId: factorId, code: code.trim());
  }

  String? _verifiedTotp(List<Factor>? factors) {
    for (final factor in factors ?? const <Factor>[]) {
      if (factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.verified) {
        return factor.id;
      }
    }
    return null;
  }
}

class UninitializedTwoFactorRepository implements TwoFactorRepository {
  const UninitializedTwoFactorRepository();

  @override
  bool needsSecondFactor() => false;

  @override
  Stream<void> sessionChanges() => const Stream.empty();

  @override
  Future<String?> verifiedFactorId() async => null;

  @override
  Future<TwoFactorSetup> enroll() => _uninitialized();

  @override
  Future<void> confirmEnrollment({
    required String factorId,
    required String code,
  }) => _uninitialized();

  @override
  Future<void> cancelEnrollment(String factorId) => _uninitialized();

  @override
  Future<void> disable({required String factorId, required String code}) =>
      _uninitialized();

  @override
  Future<void> verifySignIn(String code) => _uninitialized();

  Future<Never> _uninitialized() async {
    throw StateError(
      'Supabase must be initialized before two-step verification.',
    );
  }
}

/// Whether [code] looks like an authenticator code.
bool isTwoFactorCode(String code) =>
    RegExp('^\\d{$twoFactorCodeLength}\$').hasMatch(code.trim());

/// A readable message for a failed code or setup step.
String twoFactorErrorMessage(Object error) {
  if (error is AuthException) {
    if (error.code == 'mfa_verification_failed' ||
        error.code == 'mfa_challenge_expired' ||
        error.message.contains('Invalid TOTP code')) {
      return tr(
        "That code didn't work. Enter the current code from your "
        'authenticator app.',
      );
    }
    if (error.code == 'mfa_totp_enroll_not_enabled' ||
        error.code == 'mfa_totp_verify_not_enabled') {
      return tr('Two-step verification is not available on this server.');
    }
  }
  return tr('Something went wrong. Try again.');
}
