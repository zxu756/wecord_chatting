import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/recovery_codes.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/auth/two_factor_challenge_screen.dart';
import 'package:wecord/features/settings/recovery_codes_screen.dart';
import 'package:wecord/features/settings/two_factor_settings_screen.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../shared/navigation/app_router_test.dart' as router_fakes;
import 'account_security_fakes.dart';
import 'two_factor_test.dart' show FakeTwoFactorRepository;

/// Lets the session through once a recovery refreshed it, as the real one
/// does: the token no longer lists the authenticator.
class _RecoveringCodes extends FakeRecoveryCodesRepository {
  _RecoveringCodes(this.twoFactor) : super(remaining: 10, total: 10);

  final FakeTwoFactorRepository twoFactor;

  @override
  Future<void> refreshSession() async {
    await super.refreshSession();
    twoFactor.needsCode = false;
  }
}

Future<void> _signInToChallenge(
  WidgetTester tester, {
  required FakeTwoFactorRepository twoFactor,
  required FakeRecoveryCodesRepository codes,
}) async {
  final authState = StreamController<AuthUser?>();
  addTearDown(authState.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          router_fakes.FakeAuthRepository(),
        ),
        authStateProvider.overrideWith((ref) => authState.stream),
        twoFactorRepositoryProvider.overrideWithValue(twoFactor),
        recoveryCodesRepositoryProvider.overrideWithValue(codes),
      ],
      child: const WeCordApp(),
    ),
  );
  authState.add(const AuthUser(id: 'user-1', email: 'ada@example.com'));
  await tester.pumpAndSettle();
}

void main() {
  group('the code as typed', () {
    test('letters and digits, upper case, with or without the dash', () {
      expect(normalizeRecoveryCode('abcde-fghjk'), 'ABCDEFGHJK');
      expect(normalizeRecoveryCode(' abcde fghjk '), 'ABCDEFGHJK');
      expect(isRecoveryCode('abcde-fghjk'), isTrue);
      expect(isRecoveryCode('ABCDEFGHJK'), isTrue);
      expect(isRecoveryCode('ABCDE-FGHJ'), isFalse);
      expect(isRecoveryCode(''), isFalse);
      expect(isRecoveryCode('ABCDE-FGHJK-L'), isFalse);
    });

    test('it is shown as XXXXX-XXXXX', () {
      expect(formatRecoveryCode('abc'), 'ABC');
      expect(formatRecoveryCode('abcde'), 'ABCDE');
      expect(formatRecoveryCode('abcdef'), 'ABCDE-F');
      expect(formatRecoveryCode('abcdefghjk'), 'ABCDE-FGHJK');
      expect(formatRecoveryCode('ABCDE-FGHJK'), 'ABCDE-FGHJK');
      // Anything past ten characters is dropped.
      expect(formatRecoveryCode('abcdefghjkxyz'), 'ABCDE-FGHJK');
    });

    test('the field fixes what is typed', () {
      const formatter = RecoveryCodeFormatter();
      final value = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'abcde fgh!jk'),
      );
      expect(value.text, 'ABCDE-FGHJK');
      expect(value.selection.baseOffset, 11);
    });
  });

  group('status', () {
    test('reads the server row', () {
      final status = RecoveryStatus.fromJson({
        'remaining': 7,
        'total': 10,
        'generated_at': '2026-10-28T09:00:00+00:00',
        'locked_until': null,
      });
      expect(status.remaining, 7);
      expect(status.hasCodes, isTrue);
      expect(status.runningLow, isFalse);
      expect(status.generatedAt, DateTime.utc(2026, 10, 28, 9));
      expect(status.lockedUntil, isNull);
    });

    test('few left, or none at all', () {
      expect(const RecoveryStatus(remaining: 3, total: 10).runningLow, isTrue);
      expect(RecoveryStatus.none.hasCodes, isFalse);
      expect(RecoveryStatus.none.runningLow, isFalse);
    });
  });

  group('messages', () {
    test('a wrong code says how many tries are left', () {
      expect(
        recoveryErrorMessage(
          const RecoveryException(RecoveryFailure.invalidCode, attemptsLeft: 4),
        ),
        "That recovery code didn't work. 4 tries left.",
      );
      expect(
        recoveryErrorMessage(
          const RecoveryException(RecoveryFailure.invalidCode, attemptsLeft: 1),
        ),
        "That recovery code didn't work. 1 try left.",
      );
      expect(
        recoveryErrorMessage(
          const RecoveryException(RecoveryFailure.invalidCode),
        ),
        "That recovery code didn't work.",
      );
    });

    test('a lock says when to come back', () {
      expect(
        recoveryErrorMessage(
          const RecoveryException(
            RecoveryFailure.locked,
            retryAfter: Duration(minutes: 29, seconds: 30),
          ),
        ),
        contains('Try again in 29 minutes'),
      );
      expect(
        recoveryErrorMessage(
          const RecoveryException(
            RecoveryFailure.locked,
            retryAfter: Duration(seconds: 20),
          ),
        ),
        contains('Try again in 1 minutes'),
      );
    });

    test('the other failures have their own words', () {
      expect(
        recoveryErrorMessage(
          const RecoveryException(RecoveryFailure.needsAuthenticator),
        ),
        'Enter a code from your authenticator app first.',
      );
      expect(
        recoveryErrorMessage(StateError('x')),
        'Something went wrong. Try again.',
      );
    });
  });

  group('signing in with a recovery code', () {
    testWidgets('the challenge page offers the way out', (tester) async {
      final twoFactor = FakeTwoFactorRepository(needsCode: true);
      await _signInToChallenge(
        tester,
        twoFactor: twoFactor,
        codes: FakeRecoveryCodesRepository(),
      );

      expect(find.byKey(const ValueKey('two-factor-code')), findsOneWidget);
      expect(
        find.text('Lost your authenticator? Use a recovery code'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('two-factor-switch-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-code-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('two-factor-code')), findsNothing);
      expect(find.text('Enter a recovery code'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('two-factor-switch-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('two-factor-code')), findsOneWidget);
    });

    testWidgets('a short code is not sent', (tester) async {
      final twoFactor = FakeTwoFactorRepository(needsCode: true);
      final codes = FakeRecoveryCodesRepository();
      await _signInToChallenge(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('two-factor-switch-mode')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('recovery-code-field')),
        'abcde',
      );
      await tester.tap(find.byKey(const ValueKey('recovery-code-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter the 10-character recovery code.'),
        findsOneWidget,
      );
      expect(codes.calls, isEmpty);
    });

    testWidgets('wrong codes count down, then lock', (tester) async {
      final twoFactor = FakeTwoFactorRepository(needsCode: true);
      final codes = FakeRecoveryCodesRepository();
      await _signInToChallenge(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('two-factor-switch-mode')));
      await tester.pumpAndSettle();

      Future<void> tryCode(String code) async {
        await tester.enterText(
          find.byKey(const ValueKey('recovery-code-field')),
          code,
        );
        await tester.tap(find.byKey(const ValueKey('recovery-code-submit')));
        await tester.pumpAndSettle();
      }

      await tryCode('aaaaabbbbb');
      expect(
        find.text("That recovery code didn't work. 4 tries left."),
        findsOneWidget,
      );
      // The field is typed as it is shown, and cleared after a miss.
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('recovery-code-field')),
            )
            .controller!
            .text,
        '',
      );
      for (var i = 0; i < 3; i++) {
        await tryCode('aaaaabbbbb');
      }
      expect(
        find.text("That recovery code didn't work. 1 try left."),
        findsOneWidget,
      );
      await tryCode('aaaaabbbbb');
      await tryCode('ABCDE-FGHJK');
      expect(find.textContaining('Too many wrong codes'), findsOneWidget);
      expect(find.byType(TwoFactorChallengeScreen), findsOneWidget);
      expect(twoFactor.needsCode, isTrue);
    });

    testWidgets('a right code turns it off and lets the person in', (
      tester,
    ) async {
      final twoFactor = FakeTwoFactorRepository(needsCode: true);
      final codes = _RecoveringCodes(twoFactor);
      await _signInToChallenge(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('two-factor-switch-mode')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('recovery-code-field')),
        'abcdefghjk',
      );
      await tester.tap(find.byKey(const ValueKey('recovery-code-submit')));
      await tester.pumpAndSettle();

      // Told, before the app opens.
      expect(find.text('Two-step verification is off'), findsOneWidget);
      expect(find.byType(TwoFactorChallengeScreen), findsOneWidget);
      expect(codes.calls, ['recover ABCDE-FGHJK']);

      await tester.tap(find.byKey(const ValueKey('two-factor-recovered-ok')));
      await tester.pumpAndSettle();

      expect(codes.calls, ['recover ABCDE-FGHJK', 'refresh']);
      expect(find.byType(TwoFactorChallengeScreen), findsNothing);
      expect(find.byKey(const ValueKey('phone-home')), findsOneWidget);
    });

    testWidgets('an account that is already off just lets the person in', (
      tester,
    ) async {
      final twoFactor = FakeTwoFactorRepository(needsCode: true);
      final codes = _AlreadyOff(twoFactor);
      await _signInToChallenge(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('two-factor-switch-mode')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recovery-code-field')),
        'abcdefghjk',
      );
      await tester.tap(find.byKey(const ValueKey('recovery-code-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(TwoFactorChallengeScreen), findsNothing);
      expect(find.byKey(const ValueKey('phone-home')), findsOneWidget);
    });
  });

  group('the codes of an account with two-step verification', () {
    Future<void> openSettings(
      WidgetTester tester, {
      required FakeTwoFactorRepository twoFactor,
      required FakeRecoveryCodesRepository codes,
    }) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            twoFactorRepositoryProvider.overrideWithValue(twoFactor),
            recoveryCodesRepositoryProvider.overrideWithValue(codes),
          ],
          child: const MaterialApp(home: TwoFactorSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the card counts what is left', (tester) async {
      await openSettings(
        tester,
        twoFactor: FakeTwoFactorRepository(factorId: 'factor-1'),
        codes: FakeRecoveryCodesRepository(remaining: 7, total: 10),
      );
      expect(
        find.text('7 of 10 codes are left. Each works once.'),
        findsOneWidget,
      );
      expect(find.text('Make new codes'), findsOneWidget);
    });

    testWidgets('few left asks for a new set', (tester) async {
      await openSettings(
        tester,
        twoFactor: FakeTwoFactorRepository(factorId: 'factor-1'),
        codes: FakeRecoveryCodesRepository(remaining: 2, total: 10),
      );
      expect(
        find.text('Only 2 of 10 codes are left. Make a new set.'),
        findsOneWidget,
      );
    });

    testWidgets('none yet says how to make them', (tester) async {
      await openSettings(
        tester,
        twoFactor: FakeTwoFactorRepository(factorId: 'factor-1'),
        codes: FakeRecoveryCodesRepository(),
      );
      expect(
        find.textContaining('You have no recovery codes.'),
        findsOneWidget,
      );
      expect(find.text('Make recovery codes'), findsOneWidget);
    });

    testWidgets('a failed lookup can be tried again', (tester) async {
      final codes = FakeRecoveryCodesRepository()
        ..statusError = StateError('offline');
      await openSettings(
        tester,
        twoFactor: FakeTwoFactorRepository(factorId: 'factor-1'),
        codes: codes,
      );
      expect(find.text('Could not load your recovery codes.'), findsOneWidget);
      codes.statusError = null;
      await tester.tap(find.byKey(const ValueKey('recovery-codes-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-codes-make')), findsOneWidget);
    });

    testWidgets('new codes ask for a code first, then show the set', (
      tester,
    ) async {
      final twoFactor = FakeTwoFactorRepository(factorId: 'factor-1');
      final codes = FakeRecoveryCodesRepository(remaining: 8, total: 10);
      await openSettings(tester, twoFactor: twoFactor, codes: codes);

      await tester.tap(find.byKey(const ValueKey('recovery-codes-make')));
      await tester.pumpAndSettle();
      expect(find.text('Make new recovery codes?'), findsOneWidget);

      // A wrong code from the authenticator: nothing is made.
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        '000000',
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();
      expect(codes.calls.where((call) => call == 'generate'), isEmpty);
      expect(find.textContaining("That code didn't work"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('recovery-codes-make')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        FakeTwoFactorRepository.goodCode,
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('recovery-codes-screen')),
        findsOneWidget,
      );
      expect(find.text('ABCDE-FGHJK'), findsOneWidget);
      expect(find.byKey(const ValueKey('recovery-code-9')), findsOneWidget);
      expect(twoFactor.calls, [
        'verify 000000',
        'verify 123456',
      ], reason: 'the authenticator code is what unlocks making codes');
      expect(codes.calls.where((call) => call == 'generate'), hasLength(1));
    });

    testWidgets('the screen holds the person until the codes are saved', (
      tester,
    ) async {
      final twoFactor = FakeTwoFactorRepository(factorId: 'factor-1');
      final codes = FakeRecoveryCodesRepository(remaining: 8, total: 10);
      await openSettings(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('recovery-codes-make')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        FakeTwoFactorRepository.goodCode,
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();

      // Done waits for the tick.
      final done = find.byKey(const ValueKey('recovery-codes-done'));
      expect(tester.widget<WeCordButton>(done).onPressed, isNull);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recovery-codes-screen')),
        findsOneWidget,
      );

      // Back asks first; staying keeps the codes on screen.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recovery-codes-stay')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('recovery-codes-screen')),
        findsOneWidget,
      );

      // Ticking the box lets Done through.
      await tester.tap(find.byKey(const ValueKey('recovery-codes-saved')));
      await tester.pumpAndSettle();
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-codes-screen')), findsNothing);
      expect(
        find.byKey(const ValueKey('two-factor-settings-screen')),
        findsOneWidget,
      );
    });

    testWidgets('leaving anyway is allowed', (tester) async {
      final twoFactor = FakeTwoFactorRepository(factorId: 'factor-1');
      final codes = FakeRecoveryCodesRepository(remaining: 8, total: 10);
      await openSettings(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('recovery-codes-make')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        FakeTwoFactorRepository.goodCode,
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recovery-codes-leave')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-codes-screen')), findsNothing);
      // The count on the page is read again.
      expect(
        find.text('10 of 10 codes are left. Each works once.'),
        findsOneWidget,
      );
    });

    testWidgets('copy puts every code on the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: RecoveryCodesScreen(codes: sampleRecoveryCodes())),
      );
      await tester.tap(find.byKey(const ValueKey('recovery-codes-copy')));
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
      for (final code in sampleRecoveryCodes()) {
        expect(copied.single, contains(code));
      }
    });

    testWidgets('a refused set says why and shows nothing', (tester) async {
      final twoFactor = FakeTwoFactorRepository(factorId: 'factor-1');
      final codes = FakeRecoveryCodesRepository(remaining: 8, total: 10)
        ..generateError = const RecoveryException(RecoveryFailure.rateLimited);
      await openSettings(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('recovery-codes-make')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        FakeTwoFactorRepository.goodCode,
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recovery-codes-screen')), findsNothing);
      expect(
        find.text('You made several sets just now. Try again in an hour.'),
        findsOneWidget,
      );
    });

    testWidgets('turning two-step verification on shows the first set', (
      tester,
    ) async {
      final twoFactor = FakeTwoFactorRepository();
      final codes = FakeRecoveryCodesRepository();
      await openSettings(tester, twoFactor: twoFactor, codes: codes);
      await tester.tap(find.byKey(const ValueKey('two-factor-set-up')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('two-factor-setup-code')),
        FakeTwoFactorRepository.goodCode,
      );
      await tester.tap(find.byKey(const ValueKey('two-factor-confirm')));
      await tester.pumpAndSettle();

      // No second code is asked for: the session has just passed one.
      expect(find.byKey(const ValueKey('authenticator-code')), findsNothing);
      expect(
        find.byKey(const ValueKey('recovery-codes-screen')),
        findsOneWidget,
      );
      expect(codes.calls, contains('generate'));
      expect(
        twoFactor.calls.where((call) => call.startsWith('verify')),
        isEmpty,
      );
    });
  });
}

/// The server answers "not enabled": the account was already switched off.
class _AlreadyOff extends FakeRecoveryCodesRepository {
  _AlreadyOff(this.twoFactor);

  final FakeTwoFactorRepository twoFactor;

  @override
  Future<void> recover(String code) async {
    twoFactor
      ..needsCode = false
      ..changes.add(null);
    throw const RecoveryException(RecoveryFailure.notEnabled);
  }
}
