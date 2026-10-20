import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/safety/link_check_repository.dart';
import 'package:wecord/features/safety/link_risk.dart';
import 'package:wecord/features/safety/link_safety.dart';
import 'package:wecord/features/safety/link_warning_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

class FakeLinkCheck implements LinkCheckRepository {
  final asked = <({String url, bool chinese, String? conversationId})>[];
  Object? error;
  LinkCheckResult result = const LinkCheckResult(
    verdict: LinkVerdict.suspicious,
    reason: 'Imitates PayPal',
  );

  @override
  Future<LinkCheckResult> check({
    required String url,
    required bool chinese,
    String? conversationId,
  }) async {
    asked.add((url: url, chinese: chinese, conversationId: conversationId));
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

/// A button that asks whether [uri] may open, and shows the answer.
class _Probe extends ConsumerWidget {
  const _Probe({required this.uri, required this.answers});

  final Uri uri;
  final List<bool> answers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: TextButton(
        onPressed: () async {
          final scope = ProviderScope.containerOf(context);
          final open = await scope.read(_probeProvider).call(context, uri);
          answers.add(open);
        },
        child: const Text('tap'),
      ),
    );
  }
}

final _probeProvider = Provider<Future<bool> Function(BuildContext, Uri)>(
  (ref) =>
      (context, uri) => confirmLinkSafety(context, ref, uri),
);

Widget app({
  required Uri uri,
  required List<bool> answers,
  FakeLinkCheck? check,
  bool aiOn = true,
  List<Override> overrides = const [],
  ThemeData? theme,
  String? conversationId,
}) {
  Widget home = Scaffold(
    body: _Probe(uri: uri, answers: answers),
  );
  if (conversationId != null) {
    home = LinkChatScope(
      conversationId: conversationId,
      circleId: null,
      child: home,
    );
  }
  return ProviderScope(
    overrides: [
      if (check != null) linkCheckRepositoryProvider.overrideWithValue(check),
      aiAvailableProvider.overrideWith((ref, circleId) => aiOn),
      ...overrides,
    ],
    child: MaterialApp(theme: theme ?? WeCordTheme.light(), home: home),
  );
}

/// A tall window, so the whole warning page is on screen.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('before a link opens', () {
    testWidgets('an ordinary link opens at once', (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        app(uri: Uri.parse('https://example.com/page'), answers: answers),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(answers, [true]);
      expect(find.byType(LinkWarningScreen), findsNothing);
    });

    testWidgets('a link that is only a little odd opens at once as well', (
      tester,
    ) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        app(uri: Uri.parse('https://bit.ly/abc'), answers: answers),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(answers, [true]);
      expect(find.byType(LinkWarningScreen), findsNothing);
    });

    testWidgets('mail and phone links are left to the system', (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        app(uri: Uri.parse('mailto:a@example.com'), answers: answers),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
    });

    testWidgets('a high-risk link gets the warning page first', (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify'),
          answers: answers,
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(answers, isEmpty);
      expect(find.byKey(const ValueKey('link-warning-title')), findsOneWidget);
      expect(find.text('This link looks unsafe'), findsOneWidget);
      expect(find.text('paypal-login.com'), findsOneWidget);
      expect(
        find.text("The name looks like a well-known site, but it isn't."),
        findsOneWidget,
      );
      expect(
        find.text('The address asks you to log in, verify or claim something.'),
        findsOneWidget,
      );
    });

    testWidgets('Go back means no, and asks again next time', (tester) async {
      tall(tester);
      final answers = <bool>[];
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify'),
          answers: answers,
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('link-warning-back')));
      await tester.pumpAndSettle();
      expect(answers, [false]);

      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      expect(find.byType(LinkWarningScreen), findsOneWidget);
    });

    testWidgets('Open anyway opens it, and that host is not asked again', (
      tester,
    ) async {
      tall(tester);
      final answers = <bool>[];
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify'),
          answers: answers,
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('link-warning-open')));
      await tester.pumpAndSettle();
      expect(answers, [true]);

      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      expect(answers, [true, true]);
      expect(find.byType(LinkWarningScreen), findsNothing);
    });

    testWidgets('a short link that the server found to lead somewhere bad is '
        'warned about, with where it ends', (tester) async {
      final answers = <bool>[];
      const url = 'https://bit.ly/abc';
      await tester.pumpWidget(
        app(
          uri: Uri.parse(url),
          answers: answers,
          overrides: [
            linkPreviewProvider(url).overrideWith(
              (ref) async => LinkPreview.fromJson(const {
                'url': url,
                'title': 'Sign in',
                'risk': {
                  'level': 'high',
                  'reasons': ['short_link', 'redirects_risky'],
                },
                'final_host': 'paypal-login.com',
              }),
            ),
          ],
        ),
      );
      // The preview is already loaded when the link is tapped.
      final container = ProviderScope.containerOf(
        tester.element(find.text('tap')),
      );
      await container.read(linkPreviewProvider(url).future);
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(find.byType(LinkWarningScreen), findsOneWidget);
      expect(
        find.text('It sends you on to a riskier address.'),
        findsOneWidget,
      );
      expect(
        find.text("It is a short link, so you can't see where it goes."),
        findsOneWidget,
      );
      expect(
        find.text('Then it redirects to paypal-login.com'),
        findsOneWidget,
      );
    });
  });

  group('Ask AI on the warning page', () {
    testWidgets('sends the address and the chat, and shows the verdict', (
      tester,
    ) async {
      final check = FakeLinkCheck();
      final answers = <bool>[];
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify?token=abc'),
          answers: answers,
          check: check,
          conversationId: 'conversation-1',
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('link-warning-ask-ai')),
      );
      await tester.tap(find.byKey(const ValueKey('link-warning-ask-ai')));
      await tester.pumpAndSettle();

      expect(
        check.asked.single.url,
        'https://paypal-login.com/verify?token=abc',
      );
      expect(check.asked.single.conversationId, 'conversation-1');
      expect(check.asked.single.chinese, isFalse);
      expect(find.text('AI finds it suspicious'), findsOneWidget);
      expect(find.text('Imitates PayPal'), findsOneWidget);
      expect(
        find.text('AI can be wrong. It has not opened the link.'),
        findsOneWidget,
      );
      // The decision is still the person's.
      expect(find.byKey(const ValueKey('link-warning-open')), findsOneWidget);
    });

    testWidgets('says why when the AI cannot answer', (tester) async {
      final check = FakeLinkCheck()
        ..error = const AiLimitReachedException(limit: 50, used: 50);
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify'),
          answers: [],
          check: check,
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('link-warning-ask-ai')),
      );
      await tester.tap(find.byKey(const ValueKey('link-warning-ask-ai')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('link-warning-ai-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('link-warning-ai-answer')),
        findsNothing,
      );
    });

    testWidgets('is not offered when AI is off', (tester) async {
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify'),
          answers: [],
          check: FakeLinkCheck(),
          aiOn: false,
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-warning-ask-ai')), findsNothing);
    });

    testWidgets('the page reads in Chinese', (tester) async {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      await tester.pumpWidget(
        app(
          uri: Uri.parse('https://paypal-login.com/verify'),
          answers: [],
          check: FakeLinkCheck(),
        ),
      );
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      expect(find.text('这个链接看起来不安全'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
      expect(find.text('仍然打开'), findsOneWidget);
      expect(find.text('让 AI 检查这个链接'), findsOneWidget);
    });
  });

  group('the preview card', () {
    Widget card(Map<String, Object?> json) {
      const url = 'https://example.com/x';
      return ProviderScope(
        overrides: [
          linkPreviewProvider(url).overrideWith(
            (ref) async => LinkPreview.fromJson({'url': url, ...json}),
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: const Scaffold(body: MessageLinkPreviewCard(url: url)),
        ),
      );
    }

    testWidgets('says to be careful when the function found something odd', (
      tester,
    ) async {
      await tester.pumpWidget(
        card({
          'title': 'Hello',
          'risk': {
            'level': 'caution',
            'reasons': ['short_link'],
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-risk-caution')), findsOneWidget);
      expect(find.text('Be careful with this link'), findsOneWidget);
    });

    testWidgets('says it looks unsafe when it does', (tester) async {
      await tester.pumpWidget(
        card({
          'title': 'Hello',
          'risk': {
            'level': 'high',
            'reasons': ['lookalike_brand'],
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-risk-high')), findsOneWidget);
      expect(find.text('This link looks unsafe'), findsOneWidget);
    });

    testWidgets('is quiet for an ordinary link or an older function', (
      tester,
    ) async {
      await tester.pumpWidget(
        card({
          'title': 'Hello',
          'risk': {'level': 'none', 'reasons': <String>[]},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-risk-caution')), findsNothing);
      expect(find.byKey(const ValueKey('link-risk-high')), findsNothing);

      await tester.pumpWidget(card({'title': 'Hello'}));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('link-risk-caution')), findsNothing);
    });
  });

  test('the preview model reads the risk and the final host', () {
    final preview = LinkPreview.fromJson(const {
      'url': 'https://bit.ly/a',
      'title': 'T',
      'risk': {
        'level': 'high',
        'reasons': ['short_link', 7, 'redirects_risky'],
      },
      'final_host': 'evil.example',
    });
    expect(preview.riskLevel, 'high');
    expect(preview.riskReasons, ['short_link', 'redirects_risky']);
    expect(preview.finalHost, 'evil.example');
    final old = LinkPreview.fromJson(const {'url': 'https://a.example/'});
    expect(old.riskLevel, isNull);
    expect(old.riskReasons, isEmpty);
    expect(
      LinkRisk.fromJson({'level': 'caution'}).level,
      LinkRiskLevel.caution,
    );
  });
}
