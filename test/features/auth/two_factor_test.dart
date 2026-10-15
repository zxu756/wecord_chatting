import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/auth/two_factor_challenge_screen.dart';
import 'package:wecord/features/settings/two_factor_settings_screen.dart';

import '../../shared/navigation/app_router_test.dart' as router_fakes;

class FakeTwoFactorRepository implements TwoFactorRepository {
  FakeTwoFactorRepository({this.needsCode = false, this.factorId});

  bool needsCode;
  String? factorId;
  final changes = StreamController<void>.broadcast();
  final calls = <String>[];

  /// The code the fake authenticator shows.
  static const goodCode = '123456';

  void _check(String code) {
    if (code != goodCode) {
      throw const AuthException(
        'Invalid TOTP code entered',
        statusCode: '422',
        code: 'mfa_verification_failed',
      );
    }
  }

  @override
  bool needsSecondFactor() => needsCode;

  @override
  Stream<void> sessionChanges() => changes.stream;

  @override
  Future<String?> verifiedFactorId() async => factorId;

  @override
  Future<TwoFactorSetup> enroll() async {
    calls.add('enroll');
    return const TwoFactorSetup(
      factorId: 'factor-new',
      secret: 'JBSWY3DPEHPK3PXP',
      uri: 'otpauth://totp/WeCord:ada@example.com?secret=JBSWY3DPEHPK3PXP',
    );
  }

  @override
  Future<void> confirmEnrollment({
    required String factorId,
    required String code,
  }) async {
    calls.add('confirm $factorId $code');
    _check(code);
    this.factorId = factorId;
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {
    calls.add('cancel $factorId');
  }

  @override
  Future<void> disable({required String factorId, required String code}) async {
    calls.add('disable $factorId $code');
    _check(code);
    this.factorId = null;
  }

  @override
  Future<void> verifySignIn(String code) async {
    calls.add('verify $code');
    _check(code);
    needsCode = false;
  }
}

void main() {
  test('codes are six digits', () {
    expect(isTwoFactorCode('123456'), isTrue);
    expect(isTwoFactorCode(' 123456 '), isTrue);
    expect(isTwoFactorCode('12345'), isFalse);
    expect(isTwoFactorCode('12345a'), isFalse);
    expect(
      twoFactorErrorMessage(
        const AuthException('Invalid TOTP code entered', statusCode: '422'),
      ),
      "That code didn't work. Enter the current code from your "
      'authenticator app.',
    );
  });

  test('the pending check follows the session', () async {
    final repository = FakeTwoFactorRepository(needsCode: true);
    final container = ProviderContainer(
      overrides: [twoFactorRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    expect(container.read(twoFactorPendingProvider), isTrue);
    repository.needsCode = false;
    repository.changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(twoFactorPendingProvider), isFalse);
  });

  test('TOTP is enabled in the local Supabase config', () {
    final config = File('supabase/config.toml').readAsStringSync();
    final totp = RegExp(
      r'\[auth\.mfa\.totp\]\n([\s\S]*?)\n\n',
    ).firstMatch(config)!.group(1)!;
    expect(totp, contains('enroll_enabled = true'));
    expect(totp, contains('verify_enabled = true'));
  });

  testWidgets('accounts with an authenticator enter a code after signing in', (
    tester,
  ) async {
    final repository = FakeTwoFactorRepository(needsCode: true);
    final authState = StreamController<AuthUser?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            router_fakes.FakeAuthRepository(),
          ),
          authStateProvider.overrideWith((ref) => authState.stream),
          twoFactorRepositoryProvider.overrideWithValue(repository),
        ],
        child: const WeCordApp(),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'ada@example.com'));
    await tester.pumpAndSettle();

    expect(find.byType(TwoFactorChallengeScreen), findsOneWidget);
    expect(
      find.text('ada@example.com asks for a code when signing in.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('two-factor-code')),
      '000000',
    );
    await tester.tap(find.byKey(const ValueKey('two-factor-verify')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "That code didn't work. Enter the current code from your "
        'authenticator app.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TwoFactorChallengeScreen), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('two-factor-code')),
      FakeTwoFactorRepository.goodCode,
    );
    await tester.tap(find.byKey(const ValueKey('two-factor-verify')));
    await tester.pumpAndSettle();

    expect(repository.calls, ['verify 000000', 'verify 123456']);
    expect(find.byType(TwoFactorChallengeScreen), findsNothing);
    expect(find.text('Find or start a conversation'), findsOneWidget);
  });

  testWidgets('turning two-step verification on and off', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = FakeTwoFactorRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [twoFactorRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TwoFactorSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('two-factor-set-up')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('two-factor-qr')), findsOneWidget);
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('two-factor-setup-code')),
      '999999',
    );
    await tester.tap(find.byKey(const ValueKey('two-factor-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('two-factor-error')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('two-factor-setup-code')),
      FakeTwoFactorRepository.goodCode,
    );
    await tester.tap(find.byKey(const ValueKey('two-factor-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Two-step verification is on'), findsOneWidget);
    expect(repository.factorId, 'factor-new');

    await tester.tap(find.byKey(const ValueKey('two-factor-turn-off')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('two-factor-disable-code')),
      FakeTwoFactorRepository.goodCode,
    );
    await tester.tap(find.byKey(const ValueKey('two-factor-disable-confirm')));
    await tester.pumpAndSettle();

    expect(repository.calls, [
      'enroll',
      'confirm factor-new 999999',
      'confirm factor-new 123456',
      'disable factor-new 123456',
    ]);
    expect(find.text('Protect your account with a code'), findsOneWidget);
  });

  testWidgets('leaving setup halfway drops the new authenticator', (
    tester,
  ) async {
    final repository = FakeTwoFactorRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [twoFactorRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: TwoFactorSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('two-factor-set-up')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(repository.calls, ['enroll', 'cancel factor-new']);
  });
}
