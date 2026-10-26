// Supabase Auth's passkey API is marked experimental (beta) in the SDK; this
// file is the only place that uses it.
// ignore_for_file: experimental_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/exceptions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Whether this build tries passkeys on iPhone, Mac and Android.
///
/// Off for now: a passkey belongs to a web address, and an app proves it
/// speaks for that address with an Associated Domains entitlement
/// (`webcredentials:wecord.jokebear.fyi`) that needs a paid Apple developer
/// account (and, on Android, a digital asset links file with the app's
/// signing key). The website part is in place already (web/.well-known).
/// Build with `--dart-define=WECORD_NATIVE_PASSKEYS=true` once the
/// entitlement is added.
const nativePasskeysEnabled = bool.fromEnvironment('WECORD_NATIVE_PASSKEYS');

/// Whether this build offers passkeys at all: the web app (a passkey in the
/// browser, in the password manager or on the phone) and, later, the apps.
bool get passkeysSupportedHere => kIsWeb || nativePasskeysEnabled;

/// A passkey registered to the signed-in account.
class PasskeyInfo {
  const PasskeyInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory PasskeyInfo.fromPasskey(Passkey passkey) => PasskeyInfo(
    id: passkey.id,
    name: (passkey.friendlyName ?? '').trim(),
    createdAt: passkey.createdAt.toUtc(),
    lastUsedAt: passkey.lastUsedAt?.toUtc(),
  );

  final String id;

  /// What the server called it ("iCloud Keychain", ...) or what the person
  /// renamed it to; may be empty.
  final String name;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  String get displayName => name.isEmpty ? tr('Passkey') : name;
}

/// Why a passkey step did not work.
enum PasskeyFailure {
  /// The person closed the system sheet. Not an error to show.
  cancelled,

  /// This browser or device cannot do passkeys (or the app is not allowed
  /// to for this address yet).
  unsupported,

  /// The server has passkeys switched off (Supabase Auth, beta).
  notEnabledOnServer,

  /// The account needs a code from the authenticator app first.
  needsAuthenticator,

  /// No passkey for this site on the device.
  noPasskey,

  /// This device already holds a passkey for the account.
  alreadyRegistered,

  /// Anything else.
  failed,
}

class PasskeyException implements Exception {
  const PasskeyException(this.failure);

  final PasskeyFailure failure;

  @override
  String toString() => 'PasskeyException($failure)';
}

/// Passkeys (WebAuthn) through Supabase Auth: sign in without a password,
/// and manage the ones on the account.
abstract interface class PasskeyRepository {
  /// The account's passkeys, oldest first.
  Future<List<PasskeyInfo>> list();

  /// Creates a passkey on this device for the signed-in account. Throws a
  /// [PasskeyException] (cancelled when the person closed the sheet).
  Future<PasskeyInfo> register({String? accountName});

  Future<void> rename(String id, String name);

  /// Removes a passkey (the account needs a recent code from the
  /// authenticator app if it has two-step verification).
  Future<void> delete(String id);

  /// Signs in with a passkey on this device (no password).
  Future<void> signIn();
}

class SupabasePasskeyRepository implements PasskeyRepository {
  SupabasePasskeyRepository(this._client, {this._authenticator});

  final SupabaseClient _client;
  PasskeyAuthenticator? _authenticator;

  PasskeyAuthenticator get _platform =>
      _authenticator ??= PasskeyAuthenticator();

  @override
  Future<List<PasskeyInfo>> list() async {
    try {
      final passkeys = await _client.auth.passkey.list();
      return [for (final passkey in passkeys) PasskeyInfo.fromPasskey(passkey)]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<PasskeyInfo> register({String? accountName}) async {
    try {
      final passkey = await _client.auth.registerPasskey(
        _platform,
        friendlyName: accountName,
      );
      return PasskeyInfo.fromPasskey(passkey);
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> rename(String id, String name) async {
    try {
      await _client.auth.passkey.update(passkeyId: id, friendlyName: name);
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _client.auth.passkey.delete(passkeyId: id);
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<void> signIn() async {
    try {
      await _client.auth.signInWithPasskey(_platform);
    } on Object catch (error) {
      throw _translate(error);
    }
  }
}

/// Maps what the plugin or the server threw to a [PasskeyException].
PasskeyException _translate(Object error) {
  if (error is PasskeyException) {
    return error;
  }
  if (error is PasskeyAuthCancelledException) {
    return const PasskeyException(PasskeyFailure.cancelled);
  }
  if (error is ExcludeCredentialsCanNotBeRegisteredException) {
    return const PasskeyException(PasskeyFailure.alreadyRegistered);
  }
  if (error is NoCredentialsAvailableException) {
    return const PasskeyException(PasskeyFailure.noPasskey);
  }
  if (error is PasskeyUnsupportedException ||
      error is DeviceNotSupportedException ||
      error is DomainNotAssociatedException ||
      error is SyncAccountNotAvailableException) {
    return const PasskeyException(PasskeyFailure.unsupported);
  }
  if (error is AuthException) {
    final code = error.code ?? '';
    if (code.contains('passkey') && code.contains('not_enabled') ||
        code == 'feature_disabled' ||
        error.statusCode == '404' ||
        error.statusCode == '501') {
      return const PasskeyException(PasskeyFailure.notEnabledOnServer);
    }
    if (code == 'insufficient_aal' || code == 'mfa_verification_required') {
      return const PasskeyException(PasskeyFailure.needsAuthenticator);
    }
  }
  return const PasskeyException(PasskeyFailure.failed);
}

class UninitializedPasskeyRepository implements PasskeyRepository {
  const UninitializedPasskeyRepository();

  @override
  Future<List<PasskeyInfo>> list() async => const [];

  @override
  Future<PasskeyInfo> register({String? accountName}) async =>
      throw const PasskeyException(PasskeyFailure.unsupported);

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> signIn() async =>
      throw const PasskeyException(PasskeyFailure.unsupported);
}

final passkeyRepositoryProvider = Provider<PasskeyRepository>((ref) {
  try {
    return SupabasePasskeyRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedPasskeyRepository();
  }
});

/// Whether to offer passkeys in this build. Tests and previews override it.
final passkeysAvailableProvider = Provider<bool>((ref) {
  return passkeysSupportedHere;
});

/// The signed-in account's passkeys.
final passkeysProvider = FutureProvider.autoDispose<List<PasskeyInfo>>((ref) {
  return ref.watch(passkeyRepositoryProvider).list();
});

/// A readable message for a failed passkey step (null for cancelled: say
/// nothing).
String? passkeyErrorMessage(Object error) {
  if (error is! PasskeyException) {
    return tr('Something went wrong. Try again.');
  }
  return switch (error.failure) {
    PasskeyFailure.cancelled => null,
    PasskeyFailure.unsupported => tr(
      "This device or browser can't use passkeys for WeCord.",
    ),
    PasskeyFailure.notEnabledOnServer => tr(
      'Passkeys are not available on this server yet.',
    ),
    PasskeyFailure.needsAuthenticator => tr(
      'Enter a code from your authenticator app first.',
    ),
    PasskeyFailure.noPasskey => tr(
      'No passkey for WeCord was found on this device.',
    ),
    PasskeyFailure.alreadyRegistered => tr(
      'This device already has a passkey for your account.',
    ),
    PasskeyFailure.failed => tr('Something went wrong. Try again.'),
  };
}
