// Screenshots of AI guard 2.0 and link safety, to look at for overflow:
// the warning page for a risky link, the hint under a stranger's message with
// a link preview card, the guard's settings (what else it checks) and the
// Review queue (a held picture, a poll, flagged tasks).
//
// Always runs (a layout overflow fails the test) and writes PNGs into
// build/guard2/, phone and desktop, light and dark, English and Chinese. The
// text uses a system font found on this machine (macOS) so that it can be
// read in the pictures; without one the layout is still checked.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_ai_guard_screen.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/features/circles/guard2/review_media.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart'
    show friendsProvider;
import 'package:wecord/features/safety/link_check_repository.dart';
import 'package:wecord/features/safety/link_risk.dart';
import 'package:wecord/features/safety/link_warning_screen.dart';
import 'package:wecord/features/safety/scam_hint.dart';
import 'package:wecord/features/safety/scam_rules.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../features/circles/ai_guard_fakes.dart';
import '../features/circles/guard2_fakes.dart';
import '../features/safety/link_safety_test.dart' show FakeLinkCheck;

const _fontCandidates = [
  '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
  '/Library/Fonts/Arial Unicode.ttf',
];

Future<void> _loadFont() async {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final bytes = file.readAsBytesSync();
    for (final family in const [
      'Plus Jakarta Sans',
      'Noto Sans SC',
      'PingFang SC',
      'Hiragino Sans GB',
      'Microsoft YaHei',
    ]) {
      final loader = FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
      await loader.load();
    }
    return;
  }
}

const _phone = Size(390, 844);
const _desktop = Size(1100, 800);

Future<void> _shoot(
  WidgetTester tester,
  Widget Function(ThemeData theme) build,
  String name, {
  List<({String label, Size size, bool dark})> variants = const [
    (label: 'phone-light', size: _phone, dark: false),
    (label: 'phone-dark', size: _phone, dark: true),
    (label: 'desktop-light', size: _desktop, dark: false),
    (label: 'desktop-dark', size: _desktop, dark: true),
  ],
}) async {
  for (final variant in variants) {
    tester.view.physicalSize = variant.size * 2;
    tester.view.devicePixelRatio = 2;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: build(variant.dark ? WeCordTheme.dark() : WeCordTheme.light()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    final png = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final directory = Directory('build/guard2')..createSync(recursive: true);
    File(
      '${directory.path}/$name-${variant.label}${AppStrings.isChinese ? '-zh' : ''}.png',
    ).writeAsBytesSync(png!);
  }
}

Profile _person(String id, String name) => Profile(
  id: id,
  username: id,
  displayName: name,
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ChatMessage _stranger(String body) => ChatMessage(
  id: 'message-1',
  conversationId: 'conversation-1',
  senderId: 'stranger',
  type: MessageType.text,
  body: body,
  createdAt: DateTime.utc(2026, 10, 20, 4),
  sender: _person('stranger', 'Mika'),
);

Widget _app(ThemeData theme, Widget home, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: home,
    ),
  );
}

List<Override> _linkOverrides(FakeLinkCheck check) => [
  linkCheckRepositoryProvider.overrideWithValue(check),
  aiAvailableProvider.overrideWith((ref, circleId) => true),
];

List<Override> _guardOverrides(FakeGuardRpc rpc, FakeGuard2Rpc guard2) => [
  circleAiGuardRepositoryProvider.overrideWithValue(
    CircleAiGuardRepository(rpc),
  ),
  guard2RepositoryProvider.overrideWithValue(Guard2Repository(guard2.call)),
  reviewImageUrlProvider.overrideWith(
    (ref, file) async => 'https://example.test/${file.path}',
  ),
  pendingJoinRequestsProvider.overrideWith((ref, circleId) async => const []),
  joinRequestCountProvider.overrideWith((ref, circleId) async => 0),
];

void main() {
  setUpAll(() async {
    await _loadFont();
  });

  for (final chinese in [false, true]) {
    final suffix = chinese ? ' in Chinese' : '';

    testWidgets('the link warning page$suffix', (tester) async {
      AppStrings.isChinese = chinese;
      addTearDown(() => AppStrings.isChinese = false);
      addTearDown(tester.view.reset);
      final check = FakeLinkCheck()
        ..result = LinkCheckResult(
          verdict: LinkVerdict.suspicious,
          reason: chinese
              ? '域名在模仿 PayPal，并诱导登录。'
              : 'Imitates PayPal and pushes you to log in.',
        );
      await _shoot(
        tester,
        (theme) => _app(
          theme,
          LinkWarningScreen(
            uri: Uri.parse('https://paypal-login.example/verify?id=1'),
            risk: assessLink('https://paypal-login.example/verify?id=1'),
            redirectHost: 'secure-paypal-check.top',
          ),
          _linkOverrides(check),
        ),
        'link-warning',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the link warning page with the AI answer$suffix', (
      tester,
    ) async {
      AppStrings.isChinese = chinese;
      addTearDown(() => AppStrings.isChinese = false);
      addTearDown(tester.view.reset);
      final check = FakeLinkCheck()
        ..result = LinkCheckResult(
          verdict: LinkVerdict.dangerous,
          reason: chinese
              ? '域名在模仿 PayPal，并诱导登录。'
              : 'Imitates PayPal and pushes you to log in.',
        );
      tester.view.physicalSize = _phone * 2;
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(
        _app(
          WeCordTheme.light(),
          LinkWarningScreen(
            uri: Uri.parse('https://paypal-login.example/verify?id=1'),
            risk: assessLink('https://paypal-login.example/verify?id=1'),
          ),
          _linkOverrides(check),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('link-warning-ask-ai')),
      );
      await tester.tap(find.byKey(const ValueKey('link-warning-ask-ai')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('link-warning-ai-answer')),
        findsOneWidget,
      );
      await _shoot(
        tester,
        (theme) => _app(
          theme,
          LinkWarningScreen(
            uri: Uri.parse('https://paypal-login.example/verify?id=1'),
            risk: assessLink('https://paypal-login.example/verify?id=1'),
          ),
          _linkOverrides(check),
        ),
        'link-warning-ai',
        variants: const [(label: 'phone-dark', size: _phone, dark: true)],
      );
    });

    testWidgets('the scam hint under a stranger\'s message$suffix', (
      tester,
    ) async {
      AppStrings.isChinese = chinese;
      addTearDown(() => AppStrings.isChinese = false);
      addTearDown(tester.view.reset);
      final message = _stranger(
        chinese
            ? '恭喜你中奖了！先转账 200 元手续费，再点 https://paypal-login.example/claim 领取'
            : 'Congrats, you won! Send a 200 fee first, then claim at https://paypal-login.example/claim',
      );
      const previewUrl = 'https://paypal-login.example/claim';
      await _shoot(
        tester,
        (theme) => _app(
          theme,
          Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 440),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(message.body),
                    ),
                    const SizedBox(height: 6),
                    const MessageLinkPreviewCard(url: previewUrl, bottomGap: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: ScamHintStrip(
                        message: message,
                        signal: detectScamSignal(message.body)!,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          [
            scamHintStoreProvider.overrideWithValue(InMemoryScamHintStore()),
            friendsProvider.overrideWith((ref) async => const <Profile>[]),
            chatConversationSummaryProvider.overrideWith(
              (ref, id) async => const ConversationSummary(
                id: 'conversation-1',
                type: ConversationType.group,
                unreadCount: 0,
              ),
            ),
            linkPreviewProvider(previewUrl).overrideWith(
              (ref) async => LinkPreview.fromJson({
                'url': previewUrl,
                'title': 'Sign in to your account',
                'description': 'Verify your details to claim the reward.',
                'site_name': 'paypal-login.example',
                'risk': {
                  'level': 'high',
                  'reasons': ['lookalike_brand', 'login_words'],
                },
              }),
            ),
          ],
        ),
        'scam-hint',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the AI guard settings$suffix', (tester) async {
      AppStrings.isChinese = chinese;
      addTearDown(() => AppStrings.isChinese = false);
      addTearDown(tester.view.reset);
      final rpc = FakeGuardRpc()
        ..results['get_circle_ai_guard'] = guardJson(enabled: true)
        ..results['count_message_reviews'] = 2;
      final guard2 = FakeGuard2Rpc()
        ..results['get_circle_ai_guard_scope'] = scopeJson(
          images: true,
          vision: true,
        )
        ..results['count_guard_item_reviews'] = 1;
      await _shoot(
        tester,
        (theme) => _app(
          theme,
          CircleAiGuardScreen(detail: detail()),
          _guardOverrides(rpc, guard2),
        ),
        'guard-settings',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Review queue$suffix', (tester) async {
      AppStrings.isChinese = chinese;
      addTearDown(() => AppStrings.isChinese = false);
      addTearDown(tester.view.reset);
      final rpc = FakeGuardRpc()
        ..results['list_message_reviews'] = [
          reviewJson(
            id: 'message-1',
            body: '',
            verdict: 'sexual',
            reason: 'Nudity',
            reasonZh: '裸露',
          ),
          reviewJson(
            id: 'message-2',
            body: 'Where should the prizes go?',
            verdict: 'spam',
            state: 'flagged',
            reasonZh: '推销药品',
          ),
        ]
        ..results['list_message_review_media'] = [
          {
            'message_id': 'message-1',
            'type': 'image',
            'media': {
              'bucket': 'chat-images',
              'path': 'c/p.png',
              'mime_type': 'image/png',
            },
          },
          {
            'message_id': 'message-2',
            'type': 'poll',
            'media': {
              'options': ['Cash', 'Pills at pills.example', 'Gift cards'],
            },
          },
        ];
      final guard2 = FakeGuard2Rpc()
        ..results['list_guard_item_reviews'] = [
          itemJson(reasonZh: '虚假奖品'),
          itemJson(
            id: 'item-2',
            type: 'circle_event',
            title: 'Free crypto giveaway night',
            detail: 'Join http://scam.example and send a 0.1 ETH fee to win.',
            verdict: 'scam',
            reason: 'Fake giveaway',
            reasonZh: '虚假赠品活动',
          ),
        ]
        ..results['count_guard_item_reviews'] = 2;
      await _shoot(
        tester,
        (theme) => _app(
          theme,
          CircleReviewScreen(
            circleId: 'circle-1',
            now: () => DateTime.utc(2026, 10, 20, 4, 30),
          ),
          _guardOverrides(rpc, guard2),
        ),
        'review-queue',
        variants: const [
          (label: 'phone-light', size: Size(390, 1900), dark: false),
          (label: 'phone-dark', size: Size(390, 1900), dark: true),
          (label: 'desktop-light', size: Size(1100, 1500), dark: false),
          (label: 'desktop-dark', size: Size(1100, 1500), dark: true),
        ],
      );
      expect(tester.takeException(), isNull);
    });
  }
}
