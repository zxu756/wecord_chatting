// Two-step recovery codes and passkeys (G4), for the accessibility guard
// (guidelines_test.dart) and the accessibility screenshot tool: signing in
// with a recovery code (and a wrong one), the two-step page with its codes
// card, the new codes and the "leave without saving" question, the passkeys
// page (with passkeys, empty of devices that cannot add), renaming, the
// security log, the Security cards in Notifications and "Not me", and the
// sign-in page with its passkey button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/auth/two_factor_challenge_screen.dart';
import 'package:wecord/features/settings/recovery_codes_screen.dart';

import '../features/auth/account_security_fakes.dart';
import '../features/auth/two_factor_test.dart' show FakeTwoFactorRepository;
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// Scrolls to the widget with [key] (text can be large) and taps it.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await scrollIntoView(tester, finder);
  await tester.tap(finder);
}

void _world(
  PhoneWorld world, {
  FakeRecoveryCodesRepository? recovery,
  FakePasskeyRepository? passkeys,
  bool passkeysAvailable = true,
  bool twoFactorOn = true,
}) {
  world.extraOverrides = [
    ...world.extraOverrides,
    ...accountSecurityOverrides(
      recovery: recovery,
      passkeys: passkeys,
      passkeysAvailable: passkeysAvailable,
    ),
    twoFactorRepositoryProvider.overrideWithValue(
      FakeTwoFactorRepository(factorId: twoFactorOn ? 'factor-1' : null),
    ),
  ];
}

Future<void> _openTile(WidgetTester tester, String key) async {
  final tile = find.byKey(ValueKey(key));
  await scrollIntoView(tester, tile);
  await tester.tap(tile);
  await settle(tester);
}

Future<void> _openTwoFactor(WidgetTester tester, PhoneWorld world) async {
  _world(world);
  await world.open(tester, '/me');
  await _openTile(tester, 'two-factor-settings-tile');
}

Future<void> _openNewCodes(WidgetTester tester, PhoneWorld world) async {
  await _openTwoFactor(tester, world);
  await _tapKey(tester, 'recovery-codes-make');
  await settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey('authenticator-code')),
    FakeTwoFactorRepository.goodCode,
  );
  await _tapKey(tester, 'authenticator-code-confirm');
  await settle(tester);
}

Future<void> _openRecoveryChallenge(
  WidgetTester tester,
  PhoneWorld world,
) async {
  _world(world);
  await pumpStandalone(tester, world, const TwoFactorChallengeScreen());
  await _switchToRecovery(tester);
}

Future<void> _switchToRecovery(WidgetTester tester) async {
  final link = find.byKey(const ValueKey('two-factor-switch-mode'));
  await tester.ensureVisible(link);
  await settle(tester);
  await tester.tap(link);
  await settle(tester);
}

Future<void> _openSecurityFilter(WidgetTester tester, PhoneWorld world) async {
  _world(world);
  await world.open(tester, '/notifications');
  final chip = find.byKey(const ValueKey('inbox-filter-security'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

/// The screens, in the order of the flows.
final accountSecurityA11yScreens = <A11yScreen>[
  A11yScreen('sign-in-passkey', (tester, world) async {
    _world(world);
    world.auth.user = null;
    await pumpStandalone(tester, world, const AuthScreen());
    final button = find.byKey(const ValueKey('auth-passkey'));
    await tester.ensureVisible(button);
    await settle(tester);
  }),
  A11yScreen('two-factor-recovery-code', _openRecoveryChallenge),
  A11yScreen('two-factor-recovery-code-wrong', (tester, world) async {
    await _openRecoveryChallenge(tester, world);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-code-field')),
      'AAAAABBBBB',
    );
    await _tapKey(tester, 'recovery-code-submit');
    await settle(tester);
  }),
  A11yScreen('two-factor-recovered', (tester, world) async {
    _world(world, recovery: FakeRecoveryCodesRepository());
    await pumpStandalone(tester, world, const TwoFactorChallengeScreen());
    await _switchToRecovery(tester);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-code-field')),
      'ABCDEFGHJK',
    );
    await _tapKey(tester, 'recovery-code-submit');
    await settle(tester);
  }),
  A11yScreen('two-factor-with-recovery-codes', _openTwoFactor),
  A11yScreen('two-factor-recovery-codes-low', (tester, world) async {
    _world(
      world,
      recovery: FakeRecoveryCodesRepository(remaining: 2, total: 10),
    );
    await world.open(tester, '/me');
    await _openTile(tester, 'two-factor-settings-tile');
  }),
  A11yScreen('two-factor-recovery-codes-none', (tester, world) async {
    _world(world, recovery: FakeRecoveryCodesRepository());
    await world.open(tester, '/me');
    await _openTile(tester, 'two-factor-settings-tile');
  }),
  A11yScreen('recovery-codes-code-dialog', (tester, world) async {
    await _openTwoFactor(tester, world);
    await _tapKey(tester, 'recovery-codes-make');
    await settle(tester);
  }),
  A11yScreen('recovery-codes-new', _openNewCodes),
  A11yScreen('recovery-codes-leave', (tester, world) async {
    await _openNewCodes(tester, world);
    await popTopRoute(tester);
    await settle(tester);
  }),
  A11yScreen('recovery-codes-saved', (tester, world) async {
    _world(world);
    await pumpStandalone(
      tester,
      world,
      RecoveryCodesScreen(codes: sampleRecoveryCodes()),
    );
    final box = find.byKey(const ValueKey('recovery-codes-saved'));
    await tester.ensureVisible(box);
    await settle(tester);
    await tester.tap(box);
    await settle(tester);
  }),
  A11yScreen('passkeys', (tester, world) async {
    _world(world);
    await world.open(tester, '/me');
    await _openTile(tester, 'passkeys-tile');
  }),
  A11yScreen('passkeys-empty', (tester, world) async {
    _world(world, passkeys: FakePasskeyRepository());
    await world.open(tester, '/me');
    await _openTile(tester, 'passkeys-tile');
  }),
  A11yScreen('passkeys-web-only', (tester, world) async {
    _world(world, passkeysAvailable: false);
    await world.open(tester, '/me');
    await _openTile(tester, 'passkeys-tile');
  }),
  A11yScreen('passkeys-rename', (tester, world) async {
    _world(world);
    await world.open(tester, '/me');
    await _openTile(tester, 'passkeys-tile');
    await _tapKey(tester, 'passkey-rename-pk-1');
    await settle(tester);
  }),
  A11yScreen('passkeys-remove', (tester, world) async {
    _world(world);
    await world.open(tester, '/me');
    await _openTile(tester, 'passkeys-tile');
    await _tapKey(tester, 'passkey-remove-pk-1');
    await settle(tester);
  }),
  A11yScreen('recovery-codes-new-care', (tester, world) async {
    world.careStore.initial = const CareModeSettings(enabled: true);
    await _openNewCodes(tester, world);
  }),
  A11yScreen('passkeys-care', (tester, world) async {
    world.careStore.initial = const CareModeSettings(enabled: true);
    _world(world);
    await world.open(tester, '/me');
    await _openTile(tester, 'passkeys-tile');
  }),
  A11yScreen('security-log', (tester, world) async {
    _world(world);
    await world.open(tester, '/me');
    await _openTile(tester, 'security-log-tile');
  }),
  A11yScreen('notifications-account-security', _openSecurityFilter),
  A11yScreen('security-event-not-me', (tester, world) async {
    await _openSecurityFilter(tester, world);
    await tester.tap(find.byKey(const ValueKey('security-event-not-me')).first);
    await settle(tester);
  }),
  A11yScreen(
    'desktop-passkeys',
    (tester, world) async {
      _world(world);
      await world.open(tester, '/me');
      await _tapKey(tester, 'settings-nav-privacy');
      await settle(tester);
      final tile = find.byKey(const ValueKey('passkeys-tile'));
      await tester.ensureVisible(tile);
      await settle(tester);
      await tester.tap(tile);
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-two-factor-recovery-code',
    _openRecoveryChallenge,
    viewport: desktopViewport,
    desktop: true,
  ),
];
