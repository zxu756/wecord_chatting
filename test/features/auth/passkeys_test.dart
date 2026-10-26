import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/auth/passkeys.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/settings/passkeys_screen.dart';

import '../../shared/navigation/app_router_test.dart' as router_fakes;
import 'account_security_fakes.dart';
import 'two_factor_test.dart' show FakeTwoFactorRepository;

Future<void> _openPasskeys(
  WidgetTester tester, {
  required FakePasskeyRepository passkeys,
  FakeTwoFactorRepository? twoFactor,
  bool available = true,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...accountSecurityOverrides(
          passkeys: passkeys,
          passkeysAvailable: available,
        ),
        twoFactorRepositoryProvider.overrideWithValue(
          twoFactor ?? FakeTwoFactorRepository(),
        ),
      ],
      child: const MaterialApp(home: PasskeysScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('what the platform and the server threw', () {
    test('a closed sheet says nothing', () {
      expect(
        passkeyErrorMessage(const PasskeyException(PasskeyFailure.cancelled)),
        isNull,
      );
    });

    test('the others have their own words', () {
      expect(
        passkeyErrorMessage(
          const PasskeyException(PasskeyFailure.notEnabledOnServer),
        ),
        'Passkeys are not available on this server yet.',
      );
      expect(
        passkeyErrorMessage(const PasskeyException(PasskeyFailure.unsupported)),
        "This device or browser can't use passkeys for WeCord.",
      );
      expect(
        passkeyErrorMessage(
          const PasskeyException(PasskeyFailure.alreadyRegistered),
        ),
        'This device already has a passkey for your account.',
      );
      expect(
        passkeyErrorMessage(StateError('x')),
        'Something went wrong. Try again.',
      );
    });

    test('this build offers them on the web and, once allowed, on devices', () {
      // Tests run on the VM, not in a browser, and the native switch is off.
      expect(nativePasskeysEnabled, isFalse);
      expect(passkeysSupportedHere, isFalse);
    });

    test('a passkey from the server keeps its name and dates', () {
      final info = PasskeyInfo(
        id: 'a',
        name: '',
        createdAt: DateTime.utc(2026, 10, 1),
      );
      expect(info.displayName, 'Passkey');
      expect(info.lastUsedAt, isNull);
    });
  });

  group('the sign-in page', () {
    Future<void> openSignIn(
      WidgetTester tester, {
      required FakePasskeyRepository passkeys,
      bool available = true,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...accountSecurityOverrides(
              passkeys: passkeys,
              passkeysAvailable: available,
            ),
            authRepositoryProvider.overrideWithValue(
              router_fakes.FakeAuthRepository(),
            ),
          ],
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers a passkey, and signs in with it', (tester) async {
      final passkeys = FakePasskeyRepository();
      await openSignIn(tester, passkeys: passkeys);
      expect(find.byKey(const ValueKey('auth-passkey')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('auth-passkey')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-passkey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(passkeys.signedIn, isTrue);
      expect(passkeys.calls, ['signIn']);
    });

    testWidgets('a closed sheet leaves the page as it was', (tester) async {
      final passkeys = FakePasskeyRepository()
        ..failures.add(PasskeyFailure.cancelled);
      await openSignIn(tester, passkeys: passkeys);
      await tester.ensureVisible(find.byKey(const ValueKey('auth-passkey')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-passkey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(passkeys.signedIn, isFalse);
      expect(find.textContaining('Something went wrong'), findsNothing);
      expect(find.byKey(const ValueKey('auth-passkey')), findsOneWidget);
    });

    testWidgets('a server without passkeys says so', (tester) async {
      final passkeys = FakePasskeyRepository()
        ..failures.add(PasskeyFailure.notEnabledOnServer);
      await openSignIn(tester, passkeys: passkeys);
      await tester.ensureVisible(find.byKey(const ValueKey('auth-passkey')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-passkey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Passkeys are not available on this server yet.'),
        findsOneWidget,
      );
    });

    testWidgets('is not there where passkeys are not offered', (tester) async {
      await openSignIn(
        tester,
        passkeys: FakePasskeyRepository(),
        available: false,
      );
      expect(find.byKey(const ValueKey('auth-passkey')), findsNothing);
    });

    testWidgets('is not there when creating an account', (tester) async {
      await openSignIn(tester, passkeys: FakePasskeyRepository());
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-toggle-mode')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-toggle-mode')));
      await tester.pump();
      expect(find.byKey(const ValueKey('auth-passkey')), findsNothing);
    });
  });

  group('the Passkeys page', () {
    testWidgets('lists the passkeys with their dates', (tester) async {
      await _openPasskeys(
        tester,
        passkeys: FakePasskeyRepository(passkeys: samplePasskeys()),
      );
      expect(find.text('iCloud Keychain'), findsOneWidget);
      // A passkey with no name is still a row.
      expect(find.text('Passkey'), findsOneWidget);
      expect(find.textContaining('Never used to sign in'), findsOneWidget);
      expect(find.textContaining('Last used'), findsOneWidget);
    });

    testWidgets('an account without any says so', (tester) async {
      await _openPasskeys(tester, passkeys: FakePasskeyRepository());
      expect(find.byKey(const ValueKey('passkeys-empty')), findsOneWidget);
    });

    testWidgets('adds one on this device', (tester) async {
      final passkeys = FakePasskeyRepository();
      await _openPasskeys(tester, passkeys: passkeys);
      await tester.tap(find.byKey(const ValueKey('passkey-add')));
      await tester.pumpAndSettle();
      expect(passkeys.calls, containsAllInOrder(['register', 'list']));
      expect(find.text('Passkey added.'), findsOneWidget);
      expect(find.text('iCloud Keychain'), findsOneWidget);
    });

    testWidgets('a closed sheet adds nothing and says nothing', (tester) async {
      final passkeys = FakePasskeyRepository()
        ..failures.add(PasskeyFailure.cancelled);
      await _openPasskeys(tester, passkeys: passkeys);
      await tester.tap(find.byKey(const ValueKey('passkey-add')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('passkeys-empty')), findsOneWidget);
    });

    testWidgets('where devices cannot add, it points to the web app', (
      tester,
    ) async {
      await _openPasskeys(
        tester,
        passkeys: FakePasskeyRepository(passkeys: samplePasskeys()),
        available: false,
      );
      expect(find.byKey(const ValueKey('passkey-add')), findsNothing);
      expect(find.byKey(const ValueKey('passkey-web-only')), findsOneWidget);
      // Seeing and removing still work.
      expect(find.byKey(const ValueKey('passkey-remove-pk-1')), findsOneWidget);
    });

    testWidgets('renames one', (tester) async {
      final passkeys = FakePasskeyRepository(passkeys: samplePasskeys());
      await _openPasskeys(tester, passkeys: passkeys);
      await tester.tap(find.byKey(const ValueKey('passkey-rename-pk-1')));
      await tester.pumpAndSettle();

      // An empty name is not taken.
      await tester.enterText(
        find.byKey(const ValueKey('passkey-name-field')),
        '  ',
      );
      await tester.tap(find.byKey(const ValueKey('passkey-name-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('passkey-name-field')),
        ' Work laptop ',
      );
      await tester.tap(find.byKey(const ValueKey('passkey-name-save')));
      await tester.pumpAndSettle();
      expect(passkeys.calls, contains('rename pk-1 Work laptop'));
      expect(find.text('Work laptop'), findsOneWidget);
    });

    testWidgets('removes one after asking', (tester) async {
      final passkeys = FakePasskeyRepository(passkeys: samplePasskeys());
      await _openPasskeys(tester, passkeys: passkeys);
      await tester.tap(find.byKey(const ValueKey('passkey-remove-pk-1')));
      await tester.pumpAndSettle();
      expect(find.text('Remove iCloud Keychain?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('passkey-remove-confirm')));
      await tester.pumpAndSettle();
      expect(passkeys.calls, contains('delete pk-1'));
      expect(find.text('iCloud Keychain'), findsNothing);
      expect(find.text('Passkey removed.'), findsOneWidget);
    });

    testWidgets('an account with two-step verification confirms with a code', (
      tester,
    ) async {
      final passkeys = FakePasskeyRepository(passkeys: samplePasskeys())
        ..failures.add(PasskeyFailure.needsAuthenticator);
      final twoFactor = FakeTwoFactorRepository(factorId: 'factor-1');
      await _openPasskeys(tester, passkeys: passkeys, twoFactor: twoFactor);
      await tester.tap(find.byKey(const ValueKey('passkey-remove-pk-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('passkey-remove-confirm')));
      await tester.pumpAndSettle();

      // The server wanted a code: asked for, then tried again.
      expect(find.text('Confirm with your authenticator app'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        FakeTwoFactorRepository.goodCode,
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();

      expect(twoFactor.calls, ['verify 123456']);
      expect(
        passkeys.calls.where((call) => call == 'delete pk-1'),
        hasLength(2),
      );
      expect(find.text('iCloud Keychain'), findsNothing);
    });

    testWidgets('a wrong code leaves the passkey alone', (tester) async {
      final passkeys = FakePasskeyRepository(passkeys: samplePasskeys())
        ..failures.add(PasskeyFailure.needsAuthenticator);
      await _openPasskeys(
        tester,
        passkeys: passkeys,
        twoFactor: FakeTwoFactorRepository(factorId: 'factor-1'),
      );
      await tester.tap(find.byKey(const ValueKey('passkey-remove-pk-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('passkey-remove-confirm')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('authenticator-code')),
        '000000',
      );
      await tester.tap(
        find.byKey(const ValueKey('authenticator-code-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('iCloud Keychain'), findsOneWidget);
      expect(
        passkeys.calls.where((call) => call == 'delete pk-1'),
        hasLength(1),
      );
    });

    testWidgets('a failed load can be tried again', (tester) async {
      final passkeys = FakePasskeyRepository()..listError = StateError('x');
      await _openPasskeys(tester, passkeys: passkeys);
      expect(find.text('Could not load your passkeys.'), findsOneWidget);
    });
  });

  group('the website part', () {
    test('the app-site association names the app for passkeys', () {
      final file = File('web/.well-known/apple-app-site-association');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final apps =
          (json['webcredentials'] as Map<String, dynamic>)['apps'] as List;
      // <team>.<bundle id> of the iOS app.
      expect(
        apps,
        contains(matches(RegExp(r'^[A-Z0-9]{10}\.fyi\.jokebear\.wecord$'))),
      );
    });

    test('it is served as JSON, uncached', () {
      final headers = File('web/_headers').readAsStringSync();
      expect(
        headers,
        contains(
          '/.well-known/apple-app-site-association\n  Content-Type: application/json',
        ),
      );
    });

    test('the page defines the passkey interface before the app starts', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains('window.PasskeyAuthenticator = {'));
      expect(
        html.indexOf('window.PasskeyAuthenticator'),
        lessThan(html.indexOf('<script src="flutter_bootstrap.js"')),
      );
    });

    test('Supabase Auth settings are left alone', () {
      final config = File('supabase/config.toml').readAsStringSync();
      expect(config, contains('[functions.mfa-recovery]'));
      expect(
        RegExp(
          r'\[functions\.mfa-recovery\]\n(?:.*\n)*?verify_jwt = true',
        ).hasMatch(config),
        isTrue,
      );
    });
  });
}
