import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Characters in a recovery code, without the dash.
const recoveryCodeLength = 10;

/// What an empty recovery code field shows (not a word: no translation).
const recoveryCodeHint = 'XXXXX-XXXXX';

/// How many codes a set holds.
const recoveryCodeCount = 10;

/// Upper case, letters and digits only: what the server compares.
String normalizeRecoveryCode(String raw) =>
    raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// Whether [raw] has the length of a recovery code once typed out.
bool isRecoveryCode(String raw) =>
    normalizeRecoveryCode(raw).length == recoveryCodeLength;

/// `ABCDE-FGHJK` from ten characters, with or without the dash.
String formatRecoveryCode(String raw) {
  final code = normalizeRecoveryCode(raw);
  if (code.length <= 5) {
    return code;
  }
  final end = code.length > recoveryCodeLength
      ? recoveryCodeLength
      : code.length;
  return '${code.substring(0, 5)}-${code.substring(5, end)}';
}

/// Types a code the way it is shown: upper case, a dash after five
/// characters, nothing else.
class RecoveryCodeFormatter extends TextInputFormatter {
  const RecoveryCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = formatRecoveryCode(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// How many recovery codes are left.
class RecoveryStatus {
  const RecoveryStatus({
    required this.remaining,
    required this.total,
    this.generatedAt,
    this.lockedUntil,
  });

  factory RecoveryStatus.fromJson(Map<String, dynamic> json) {
    return RecoveryStatus(
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      generatedAt: _date(json['generated_at']),
      lockedUntil: _date(json['locked_until']),
    );
  }

  static const none = RecoveryStatus(remaining: 0, total: 0);

  final int remaining;
  final int total;
  final DateTime? generatedAt;
  final DateTime? lockedUntil;

  /// Whether a set was ever made (and not replaced by a recovery).
  bool get hasCodes => total > 0;

  /// Few enough left that the person should make a new set.
  bool get runningLow => hasCodes && remaining <= 3;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;
}

/// Why a recovery step did not work.
enum RecoveryFailure {
  /// The code is wrong.
  invalidCode,

  /// Too many wrong codes: recovery waits.
  locked,

  /// The account has no codes left to try.
  noCodes,

  /// Two-step verification is not on for the account.
  notEnabled,

  /// Making codes needs a code from the authenticator app first.
  needsAuthenticator,

  /// Too many sets were made in the last hour.
  rateLimited,

  /// Anything else (network, server).
  failed,
}

class RecoveryException implements Exception {
  const RecoveryException(this.failure, {this.attemptsLeft, this.retryAfter});

  final RecoveryFailure failure;

  /// For [RecoveryFailure.invalidCode]: wrong codes the server still allows.
  final int? attemptsLeft;

  /// For [RecoveryFailure.locked]: how long until the next try.
  final Duration? retryAfter;

  @override
  String toString() => 'RecoveryException($failure)';
}

/// Recovery codes for two-step verification (G4).
abstract interface class RecoveryCodesRepository {
  /// How many codes are left (never the codes).
  Future<RecoveryStatus> status();

  /// Makes a new set of codes, replacing the old one, and returns them in
  /// the form to show (`ABCDE-FGHJK`). They are never available again. The
  /// session must have passed a code from the authenticator app a moment
  /// ago, else [RecoveryFailure.needsAuthenticator].
  Future<List<String>> generate();

  /// Signs in past a lost authenticator with [code]: the server turns
  /// two-step verification off for the account. Call [refreshSession]
  /// afterwards so this session stops asking for a code.
  Future<void> recover(String code);

  /// Loads a new access token, which no longer lists the authenticator.
  Future<void> refreshSession();
}

class SupabaseRecoveryCodesRepository implements RecoveryCodesRepository {
  const SupabaseRecoveryCodesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<RecoveryStatus> status() async {
    final rows = await _client.rpc<List<dynamic>>('my_mfa_recovery_status');
    if (rows.isEmpty) {
      return RecoveryStatus.none;
    }
    return RecoveryStatus.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<List<String>> generate() async {
    try {
      final codes = await _client.rpc<List<dynamic>>(
        'generate_mfa_recovery_codes',
      );
      return [for (final code in codes) code as String];
    } on PostgrestException catch (error) {
      throw RecoveryException(switch (error.message) {
        'aal2_required' ||
        'fresh_verification_required' => RecoveryFailure.needsAuthenticator,
        'rate_limited' => RecoveryFailure.rateLimited,
        _ => RecoveryFailure.failed,
      });
    }
  }

  @override
  Future<void> recover(String code) async {
    try {
      await _client.functions.invoke(
        'mfa-recovery',
        body: {'code': formatRecoveryCode(code)},
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final body = details is Map ? details : const <String, dynamic>{};
      final failure = switch (body['error']) {
        'invalid_code' => RecoveryFailure.invalidCode,
        'locked' => RecoveryFailure.locked,
        'no_codes' => RecoveryFailure.noCodes,
        'not_enabled' => RecoveryFailure.notEnabled,
        _ => RecoveryFailure.failed,
      };
      if (failure == RecoveryFailure.notEnabled) {
        // Already off (for instance after an earlier try whose answer got
        // lost): bring this session up to date so it stops asking.
        await _refresh();
      }
      throw RecoveryException(
        failure,
        attemptsLeft: (body['attempts_left'] as num?)?.toInt(),
        retryAfter: body['retry_after_seconds'] is num
            ? Duration(seconds: (body['retry_after_seconds'] as num).toInt())
            : null,
      );
    }
  }

  @override
  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }

  Future<void> _refresh() async {
    try {
      await refreshSession();
    } on Object {
      // The next start-up reads the session fresh.
    }
  }
}

class UninitializedRecoveryCodesRepository implements RecoveryCodesRepository {
  const UninitializedRecoveryCodesRepository();

  @override
  Future<RecoveryStatus> status() async => RecoveryStatus.none;

  @override
  Future<List<String>> generate() async =>
      throw StateError('Supabase must be initialized before recovery codes.');

  @override
  Future<void> recover(String code) async =>
      throw StateError('Supabase must be initialized before recovery codes.');

  @override
  Future<void> refreshSession() async {}
}

final recoveryCodesRepositoryProvider = Provider<RecoveryCodesRepository>((
  ref,
) {
  try {
    return SupabaseRecoveryCodesRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedRecoveryCodesRepository();
  }
});

/// How many recovery codes the signed-in person has left.
final recoveryStatusProvider = FutureProvider.autoDispose<RecoveryStatus>((
  ref,
) {
  return ref.watch(recoveryCodesRepositoryProvider).status();
});

/// A readable message for a failed recovery step.
String recoveryErrorMessage(Object error) {
  if (error is RecoveryException) {
    switch (error.failure) {
      case RecoveryFailure.invalidCode:
        final left = error.attemptsLeft;
        if (left != null && left > 0) {
          return left == 1
              ? tr("That recovery code didn't work. 1 try left.")
              : tr("That recovery code didn't work. {count} tries left.", {
                  'count': left,
                });
        }
        return tr("That recovery code didn't work.");
      case RecoveryFailure.locked:
        final wait = error.retryAfter ?? const Duration(minutes: 30);
        final minutes = wait.inMinutes < 1 ? 1 : wait.inMinutes;
        return tr(
          'Too many wrong codes. Try again in {count} minutes, or sign in '
          'with your authenticator app.',
          {'count': minutes},
        );
      case RecoveryFailure.noCodes:
        return tr('This account has no recovery codes left.');
      case RecoveryFailure.notEnabled:
        return tr('Two-step verification is already off for this account.');
      case RecoveryFailure.needsAuthenticator:
        return tr('Enter a code from your authenticator app first.');
      case RecoveryFailure.rateLimited:
        return tr('You made several sets just now. Try again in an hour.');
      case RecoveryFailure.failed:
        break;
    }
  }
  return tr('Something went wrong. Try again.');
}
