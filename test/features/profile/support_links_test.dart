import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_insights_blocks.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/features/profile/support_links_editor.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

void main() {
  tearDown(() {
    AppStrings.isChinese = false;
    debugDefaultTargetPlatformOverride = null;
  });

  group('the allow list', () {
    test('known platforms and their subdomains pass, hosts lower-cased', () {
      expect(
        normalizeSupportUrl('https://ko-fi.com/ada'),
        'https://ko-fi.com/ada',
      );
      expect(
        normalizeSupportUrl('  https://www.patreon.com/ada  '),
        'https://www.patreon.com/ada',
      );
      expect(
        normalizeSupportUrl('https://KO-FI.com/Ada'),
        'https://ko-fi.com/Ada',
      );
      for (final url in [
        'https://afdian.net/a/ada',
        'https://afdian.com/a/ada',
        'https://ifdian.net/a/ada',
        'https://buymeacoffee.com/ada',
        'https://liberapay.com/ada',
        'https://opencollective.com/ada',
        'https://paypal.me/ada',
        'https://ada.fanbox.cc/',
        'https://boosty.to/ada',
        'https://github.com/sponsors/ada',
      ]) {
        expect(normalizeSupportUrl(url), isNotNull, reason: url);
      }
    });

    test('look-alikes, other schemes, ports, user names and spaces fail', () {
      for (final url in [
        'http://ko-fi.com/ada',
        'https://patreon.com.evil.example/ada',
        'https://notpatreon.com/ada',
        'https://evil.example/?u=https://ko-fi.com/ada',
        'https://ko-fi.com@evil.example/',
        'https://evil.example@ko-fi.com/',
        'https://ko-fi.com:8443/ada',
        'javascript:alert(1)',
        'https://127.0.0.1/ada',
        'https://ko-fi.com/a b',
        'https://ko-fi.com/"x',
        'https://github.com/ada',
        'https://github.com/sponsors',
        'ko-fi.com/ada',
        '',
        '   ',
        'https://ko-fi.com/${'a' * 300}',
      ]) {
        expect(normalizeSupportUrl(url), isNull, reason: url);
      }
      expect(normalizeSupportUrl(null), isNull);
    });

    test('a link is titled by its label, else its platform, else its host', () {
      expect(
        const SupportLink(
          url: 'https://ko-fi.com/ada',
          label: 'Buy me tea',
        ).title,
        'Buy me tea',
      );
      expect(const SupportLink(url: 'https://ko-fi.com/ada').title, 'Ko-fi');
      expect(
        const SupportLink(url: 'https://github.com/sponsors/ada').title,
        'GitHub Sponsors',
      );
      expect(
        SupportLink.listFromJson([
          {'url': 'https://ko-fi.com/ada', 'label': '  '},
          {'url': 'http://ko-fi.com/ada'},
          'not a link',
        ]).map((link) => link.label),
        [null],
      );
    });
  });

  group('hidden on iPhone, shown on the web and the Mac', () {
    test('by platform', () {
      expect(
        supportLinksAvailable(platform: TargetPlatform.iOS, isWeb: false),
        isFalse,
      );
      expect(
        supportLinksAvailable(platform: TargetPlatform.iOS, isWeb: true),
        isTrue,
        reason: 'the web app in iPhone Safari is the web',
      );
      expect(
        supportLinksAvailable(platform: TargetPlatform.macOS, isWeb: false),
        isTrue,
      );
      expect(
        supportLinksAvailable(platform: TargetPlatform.android, isWeb: false),
        isTrue,
      );
      expect(
        supportLinksAvailable(platform: TargetPlatform.windows, isWeb: false),
        isTrue,
      );
    });

    testWidgets('the profile card hides them on iOS and shows them on macOS', (
      tester,
    ) async {
      Future<void> pump() => tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileInsightsProvider('u2').overrideWith(
              (ref) async => const ProfileInsights(
                links: [
                  SupportLink(url: 'https://ko-fi.com/ada', label: 'Ko-fi'),
                ],
                birthday: ProfileBirthday(month: 10, day: 18),
              ),
            ),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(body: ProfileInsightsBlocks(userId: 'u2')),
          ),
        ),
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('profile-support-links')), findsNothing);
      // The rest of the card is still there.
      expect(find.byKey(const ValueKey('profile-birthday')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-support-links')),
        findsOneWidget,
      );
      expect(find.text('Ko-fi'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('settings and the circle editor hide on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(
              body: Column(
                children: [
                  SupportLinksSettingsRow(),
                  CircleSupportLinkSection(circleId: 'c1'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-support-links')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('circle-support-url')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('settings and the circle editor show elsewhere', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            circleSupportUrlProvider(
              'c1',
            ).overrideWith((ref) async => 'https://afdian.net/a/club'),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const Scaffold(
              body: Column(
                children: [
                  SupportLinksSettingsRow(),
                  CircleSupportLinkSection(circleId: 'c1'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('settings-support-links')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('circle-support-url')), findsOneWidget);
      expect(find.text('https://afdian.net/a/club'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('opening a link', () {
    Future<void> pumpOpener(
      WidgetTester tester,
      List<Uri> opened, {
      String url = 'https://ko-fi.com/ada',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openSupportLink(
                  context,
                  url,
                  launch: (uri) async {
                    opened.add(uri);
                    return true;
                  },
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('warns about leaving WeCord first, then opens', (tester) async {
      final opened = <Uri>[];
      await pumpOpener(tester, opened);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Leaving WeCord'), findsOneWidget);
      expect(
        find.textContaining('a site outside WeCord'),
        findsOneWidget,
        reason: 'the sheet names where it goes',
      );
      expect(find.textContaining('ko-fi.com'), findsOneWidget);
      expect(opened, isEmpty, reason: 'nothing opens before the answer');

      await tester.tap(find.byKey(const ValueKey('leave-wecord-open')));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://ko-fi.com/ada')]);
    });

    testWidgets('cancel opens nothing', (tester) async {
      final opened = <Uri>[];
      await pumpOpener(tester, opened);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('leave-wecord-cancel')));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('an address that is not allowed is not even offered', (
      tester,
    ) async {
      final opened = <Uri>[];
      await pumpOpener(tester, opened, url: 'https://evil.example/pay');
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('Leaving WeCord'), findsNothing);
      expect(opened, isEmpty);
    });

    testWidgets('the warning reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      final opened = <Uri>[];
      await pumpOpener(tester, opened);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('即将离开 WeCord'), findsOneWidget);
      expect(find.textContaining('WeCord 不处理付款'), findsOneWidget);
    });
  });
}
