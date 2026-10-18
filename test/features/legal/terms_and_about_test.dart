import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/bootstrap/app_bootstrap.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/legal/about_screen.dart';
import 'package:wecord/features/legal/terms_acceptance.dart';
import 'package:wecord/features/legal/terms_checkbox.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/app_router.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'legal_test_support.dart';

/// Answers get_my_terms_status and accept_terms.
class FakeTermsRpc {
  FakeTermsRpc({this.accepted = false, this.fail = false});

  bool accepted;
  bool fail;
  final calls = <String>[];

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add(name);
    if (fail) {
      throw StateError('offline');
    }
    if (name == 'accept_terms') {
      accepted = true;
    }
    if (name == 'get_my_terms_status' || name == 'accept_terms') {
      return {
        'accepted_terms_at': accepted ? '2026-10-20T10:00:00Z' : null,
        'age_confirmed_at': accepted ? '2026-10-20T10:00:00Z' : null,
      };
    }
    throw StateError('unexpected $name');
  }
}

Future<void> _host(WidgetTester tester, FakeTermsRpc rpc) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'user-1')),
        ),
        circleRpcProvider.overrideWithValue(rpc.call),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const TermsPromptHost(
          child: Scaffold(body: Center(child: Text('the app'))),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the agreement checkbox', () {
    Future<void> pumpBox(
      WidgetTester tester, {
      required ValueNotifier<bool> value,
      bool enabled = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<bool>(
                valueListenable: value,
                builder: (context, checked, _) => TermsAgreementCheckbox(
                  value: checked,
                  onChanged: enabled ? (next) => value.value = next : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('names the age from the one constant and links both texts', (
      tester,
    ) async {
      await pumpBox(tester, value: ValueNotifier(false));
      expect(
        find.text(
          'I am at least 13 and agree to the Terms of Service and the '
          'Community Guidelines.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('ticks and unticks, and tells screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final value = ValueNotifier(false);
      await pumpBox(tester, value: value);

      expect(
        tester.getSemantics(find.byKey(const ValueKey('terms-checkbox'))),
        matchesSemantics(
          label: 'Agree to the terms',
          hasToggledState: true,
          isToggled: false,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      expect(value.value, isTrue);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      expect(value.value, isFalse);
      handle.dispose();
    });

    testWidgets('does nothing while the form is busy', (tester) async {
      final value = ValueNotifier(false);
      await pumpBox(tester, value: value, enabled: false);
      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      expect(value.value, isFalse);
    });

    testWidgets('keeps the links where the language puts them', (tester) async {
      AppStrings.isChinese = true;
      await pumpBox(tester, value: ValueNotifier(false));
      expect(
        find.text('我已年满 13 岁，并同意服务条款和社区准则。', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('the prompt for existing accounts', () {
    testWidgets('asks someone with nothing on record, and blocks nothing', (
      tester,
    ) async {
      final rpc = FakeTermsRpc();
      await _host(tester, rpc);

      expect(find.text('the app'), findsOneWidget);
      expect(find.byKey(const ValueKey('terms-banner')), findsOneWidget);
      expect(find.text('Please review our terms'), findsOneWidget);
      // Agree needs the box.
      final agree = find.byKey(const ValueKey('terms-banner-agree'));
      expect(tester.widget<WeCordButton>(agree).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      expect(tester.widget<WeCordButton>(agree).onPressed, isNotNull);
    });

    testWidgets('records the agreement once and goes away', (tester) async {
      final rpc = FakeTermsRpc();
      await _host(tester, rpc);

      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('terms-banner-agree')));
      await tester.pumpAndSettle();

      expect(rpc.calls, contains('accept_terms'));
      expect(rpc.accepted, isTrue);
      expect(find.byKey(const ValueKey('terms-banner')), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('"Not now" hides it without recording anything', (
      tester,
    ) async {
      final rpc = FakeTermsRpc();
      await _host(tester, rpc);

      await tester.tap(find.byKey(const ValueKey('terms-banner-later')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('terms-banner')), findsNothing);
      expect(rpc.calls, isNot(contains('accept_terms')));
    });

    testWidgets('does not ask someone who already agreed', (tester) async {
      await _host(tester, FakeTermsRpc(accepted: true));
      expect(find.byKey(const ValueKey('terms-banner')), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('does not ask when the record cannot be read', (tester) async {
      await _host(tester, FakeTermsRpc(fail: true));
      expect(find.byKey(const ValueKey('terms-banner')), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('says so when saving fails, and can be tried again', (
      tester,
    ) async {
      final rpc = FakeTermsRpc();
      await _host(tester, rpc);

      await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
      await tester.pump();
      rpc.fail = true;
      await tester.tap(find.byKey(const ValueKey('terms-banner-agree')));
      await tester.pumpAndSettle();

      expect(find.text('Could not save that. Try again.'), findsOneWidget);
      expect(find.byKey(const ValueKey('terms-banner')), findsOneWidget);
      rpc.fail = false;
      await tester.tap(find.byKey(const ValueKey('terms-banner-agree')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terms-banner')), findsNothing);
    });
  });

  group('About', () {
    testWidgets('lists the version, the three pages and the licences', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: const AboutScreen(version: '1.2.3'),
        ),
      );

      expect(find.text('About WeCord'), findsOneWidget);
      expect(find.text('1.2.3'), findsOneWidget);
      expect(find.text('Community Guidelines'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Open-source licences'), findsOneWidget);
    });

    testWidgets('opens a page', (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: DefaultAssetBundle(
            bundle: DiskAssetBundle(),
            child: const AboutScreen(version: '1.2.3'),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('about-privacy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('legal-privacy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-screen')), findsOneWidget);
    });

    testWidgets('opens the licences page', (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: const AboutScreen(version: '1.2.3'),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('about-licenses')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LicensePage), findsOneWidget);
      // The page gathers the licences outside the test clock; let it finish
      // before the next test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
    });

    testWidgets('has an entry in Settings that opens it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: AboutSettingsEntry()),
        ),
      );
      expect(find.text('About WeCord'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-about')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-screen')), findsOneWidget);
    });
  });

  group('the routes', () {
    Future<_Router> open(WidgetTester tester, {required AuthUser? user}) async {
      final auth = StreamController<AuthUser?>();
      addTearDown(auth.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_FakeAuth()),
            authStateProvider.overrideWith((ref) => auth.stream),
            circleRpcProvider.overrideWithValue(FakeTermsRpc().call),
          ],
          child: DefaultAssetBundle(
            bundle: DiskAssetBundle(),
            child: const WeCordApp(),
          ),
        ),
      );
      auth.add(user);
      await tester.pumpAndSettle();
      return _Router(
        ProviderScope.containerOf(
          tester.element(find.byType(WeCordApp)),
        ).read(appRouterProvider),
      );
    }

    testWidgets('open for somebody who is signed out', (tester) async {
      final router = await open(tester, user: null);
      expect(find.text('Create account'), findsOneWidget);

      router.go('/legal/privacy');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('legal-privacy')), findsOneWidget);
      expect(router.location, '/legal/privacy');
      expect(find.text('Sign in'), findsNothing);
      await _close(tester);
    });

    testWidgets('open for somebody who is signed in', (tester) async {
      final router = await open(
        tester,
        user: const AuthUser(id: 'user-1', email: 'me@example.com'),
      );
      for (final slug in ['guidelines', 'privacy', 'terms']) {
        router.go('/legal/$slug');
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('legal-$slug')),
          findsOneWidget,
          reason: slug,
        );
        expect(router.location, '/legal/$slug');
      }
      await _close(tester);
    });

    testWidgets('an unknown page goes Home', (tester) async {
      final router = await open(
        tester,
        user: const AuthUser(id: 'user-1', email: 'me@example.com'),
      );
      router.go('/legal/cookies');
      await tester.pumpAndSettle();
      expect(router.location, HomeScreen.path);
      await _close(tester);
    });
  });
}

/// Takes the app down so its timers end with the test.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 4));
}

class _Router {
  _Router(this.router);

  final GoRouter router;

  void go(String location) => router.go(location);

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

class _FakeAuth implements AuthRepository {
  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> ensureCurrentUserProfile() async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}
