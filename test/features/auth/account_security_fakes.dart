import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/auth/passkeys.dart';
import 'package:wecord/features/auth/recovery_codes.dart';
import 'package:wecord/features/privacy/account_security_events.dart';

/// Ten codes as the server shows them.
List<String> sampleRecoveryCodes() => const [
  'ABCDE-FGHJK',
  'LMNPQ-RSTUV',
  'WXYZ2-34567',
  '89ABC-DEFGH',
  'JKLMN-PQRST',
  'UVWXY-Z2345',
  '6789A-BCDEF',
  'GHJKL-MNPQR',
  'STUVW-XYZ23',
  '45678-9ABCD',
];

/// Recovery codes as the server keeps them: a set, how many are used, a
/// lock after five wrong tries.
class FakeRecoveryCodesRepository implements RecoveryCodesRepository {
  FakeRecoveryCodesRepository({
    this.remaining = 0,
    this.total = 0,
    this.goodCode = 'ABCDE-FGHJK',
  });

  int remaining;
  int total;
  final String goodCode;
  var failures = 0;
  Object? generateError;
  Object? statusError;
  final calls = <String>[];

  /// What [recover] throws after [failures] reach five.
  static const maxFailures = 5;

  @override
  Future<RecoveryStatus> status() async {
    calls.add('status');
    if (statusError != null) {
      throw statusError!;
    }
    return RecoveryStatus(remaining: remaining, total: total);
  }

  @override
  Future<List<String>> generate() async {
    calls.add('generate');
    if (generateError != null) {
      throw generateError!;
    }
    remaining = 10;
    total = 10;
    return sampleRecoveryCodes();
  }

  @override
  Future<void> recover(String code) async {
    calls.add('recover $code');
    if (failures >= maxFailures) {
      throw const RecoveryException(
        RecoveryFailure.locked,
        retryAfter: Duration(minutes: 30),
      );
    }
    if (normalizeRecoveryCode(code) != normalizeRecoveryCode(goodCode)) {
      failures++;
      throw RecoveryException(
        RecoveryFailure.invalidCode,
        attemptsLeft: maxFailures - failures,
      );
    }
    remaining = 0;
    total = 0;
  }

  @override
  Future<void> refreshSession() async {
    calls.add('refresh');
  }
}

/// Passkeys on the account; [register] adds one unless told to fail.
class FakePasskeyRepository implements PasskeyRepository {
  FakePasskeyRepository({List<PasskeyInfo>? passkeys})
    : passkeys = passkeys ?? [];

  List<PasskeyInfo> passkeys;
  final calls = <String>[];

  /// The next calls throw this, once each, in order.
  final failures = <PasskeyFailure>[];
  var signedIn = false;
  Object? listError;

  void _maybeFail() {
    if (failures.isNotEmpty) {
      throw PasskeyException(failures.removeAt(0));
    }
  }

  @override
  Future<List<PasskeyInfo>> list() async {
    calls.add('list');
    if (listError != null) {
      throw listError!;
    }
    return List.of(passkeys);
  }

  @override
  Future<PasskeyInfo> register({String? accountName}) async {
    calls.add('register');
    _maybeFail();
    final added = PasskeyInfo(
      id: 'pk-${passkeys.length + 1}',
      name: 'iCloud Keychain',
      createdAt: DateTime.utc(2026, 10, 28, 9),
    );
    passkeys = [...passkeys, added];
    return added;
  }

  @override
  Future<void> rename(String id, String name) async {
    calls.add('rename $id $name');
    _maybeFail();
    passkeys = [
      for (final passkey in passkeys)
        if (passkey.id == id)
          PasskeyInfo(
            id: id,
            name: name,
            createdAt: passkey.createdAt,
            lastUsedAt: passkey.lastUsedAt,
          )
        else
          passkey,
    ];
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete $id');
    _maybeFail();
    passkeys = [
      for (final passkey in passkeys)
        if (passkey.id != id) passkey,
    ];
  }

  @override
  Future<void> signIn() async {
    calls.add('signIn');
    _maybeFail();
    signedIn = true;
  }
}

List<PasskeyInfo> samplePasskeys() => [
  PasskeyInfo(
    id: 'pk-1',
    name: 'iCloud Keychain',
    createdAt: DateTime.utc(2026, 10, 20, 9),
    lastUsedAt: DateTime.utc(2026, 10, 27, 18),
  ),
  PasskeyInfo(id: 'pk-2', name: '', createdAt: DateTime.utc(2026, 10, 25, 9)),
];

/// The security record; answering closes an event.
class FakeAccountSecurityRepository implements AccountSecurityRepository {
  FakeAccountSecurityRepository([List<AccountSecurityEvent>? events])
    : events = events ?? sampleSecurityEvents();

  List<AccountSecurityEvent> events;
  var failResolve = false;
  final resolved = <(String, AccountSecurityAnswer)>[];

  @override
  Future<List<AccountSecurityEvent>> list() async => events;

  @override
  Future<void> resolve(String eventId, AccountSecurityAnswer answer) async {
    if (failResolve) {
      throw StateError('offline');
    }
    resolved.add((eventId, answer));
    events = [
      for (final event in events)
        if (event.id == eventId)
          AccountSecurityEvent(
            id: event.id,
            kind: event.kind,
            createdAt: event.createdAt,
            passkeyName: event.passkeyName,
            answer: answer,
          )
        else
          event,
    ];
  }
}

List<AccountSecurityEvent> sampleSecurityEvents() {
  final now = DateTime.now().toUtc();
  return [
    AccountSecurityEvent(
      id: 'ev-1',
      kind: AccountSecurityKind.recoveryCodeUsed,
      createdAt: now.subtract(const Duration(minutes: 9)),
    ),
    AccountSecurityEvent(
      id: 'ev-2',
      kind: AccountSecurityKind.passkeyAdded,
      createdAt: now.subtract(const Duration(hours: 5)),
      passkeyName: 'iCloud Keychain',
    ),
    AccountSecurityEvent(
      id: 'ev-3',
      kind: AccountSecurityKind.recoveryCodesGenerated,
      createdAt: now.subtract(const Duration(days: 3)),
      answer: AccountSecurityAnswer.confirmed,
    ),
  ];
}

/// The three fakes as provider overrides.
List<Override> accountSecurityOverrides({
  RecoveryCodesRepository? recovery,
  PasskeyRepository? passkeys,
  AccountSecurityRepository? events,
  bool passkeysAvailable = true,
}) => [
  recoveryCodesRepositoryProvider.overrideWithValue(
    recovery ?? FakeRecoveryCodesRepository(remaining: 8, total: 10),
  ),
  passkeyRepositoryProvider.overrideWithValue(
    passkeys ?? FakePasskeyRepository(passkeys: samplePasskeys()),
  ),
  accountSecurityRepositoryProvider.overrideWithValue(
    events ?? FakeAccountSecurityRepository(),
  ),
  passkeysAvailableProvider.overrideWithValue(passkeysAvailable),
];
