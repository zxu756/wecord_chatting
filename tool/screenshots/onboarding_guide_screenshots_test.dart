// Renders the member guide (the questions, the guide page, the editor and
// the new-member card) on a phone and a desktop, light and dark, with real
// fonts, and writes PNGs for eyeballing. Not part of `flutter test`; run it
// with:
//
//   flutter test tool/screenshots/onboarding_guide_screenshots_test.dart \
//     --dart-define=GUIDE_SCREENS_DIR=build/onboarding_guide
//
// Chinese with --dart-define=GUIDE_SCREENS_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/onboarding/guide_editor_screen.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/features/circles/onboarding/guide_page.dart';
import 'package:wecord/features/circles/onboarding/guide_prompts_page.dart';
import 'package:wecord/features/circles/onboarding/newcomer_card.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../test/features/circles/onboarding_guide_fakes.dart';
import '../../test/mobile/phone_test_support.dart' show circleDetail;
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'GUIDE_SCREENS_DIR',
  defaultValue: 'build/onboarding_guide',
);
const _zh = bool.fromEnvironment('GUIDE_SCREENS_ZH');

class _SignedIn implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'me');

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _prompts = [
  guidePromptJson(
    title: 'What do you play?',
    options: [
      guideOptionJson(
        id: 'opt-chess',
        label: 'Chess',
        emoji: '♟',
        selected: true,
        roles: [
          {'id': 'role-photo', 'name': 'Photographers', 'color': 0x2ECC71},
        ],
        channels: [
          {'id': 'ch-games', 'name': 'games'},
        ],
      ),
      guideOptionJson(id: 'opt-go', label: 'Go', emoji: '⚫'),
      guideOptionJson(id: 'opt-cards', label: 'Card games', emoji: '🃏'),
    ],
  ),
  guidePromptJson(
    id: 'prompt-2',
    title: 'Where do you play?',
    required: true,
    singleSelect: true,
    options: [
      guideOptionJson(id: 'opt-pc', label: 'PC', emoji: '💻'),
      guideOptionJson(id: 'opt-mobile', label: 'Mobile', emoji: '📱'),
    ],
  ),
];

Map<String, dynamic> _guide() => guideJson(
  prompts: _prompts,
  tasks: [
    guideTaskJson(done: true),
    guideTaskJson(
      id: 'task-2',
      title: 'Have a look around',
      action: 'visit_channel',
      channelId: 'ch-general',
      channelName: 'general',
      done: true,
    ),
    guideTaskJson(
      id: 'task-3',
      title: 'Introduce yourself',
      action: 'send_message',
      channelId: 'ch-general',
      channelName: 'general',
    ),
    guideTaskJson(
      id: 'task-4',
      title: 'Add a profile picture',
      action: 'set_avatar',
    ),
  ],
);

void main() {
  setUpAll(loadScreenshotFonts);

  final variants = [
    ('phone-light', const Size(390, 1500), WeCordTheme.light()),
    ('phone-dark', const Size(390, 1500), WeCordTheme.dark()),
    ('desktop-light', const Size(1280, 1500), WeCordTheme.light()),
    ('desktop-dark', const Size(1280, 1500), WeCordTheme.dark()),
  ];

  final screens = <String, Widget Function()>{
    'questions': () => GuidePromptsPage(
      circleId: 'circle-1',
      circleName: 'Book Club',
      guide: CircleGuide.fromJson(_guide()),
    ),
    'guide': () =>
        const CircleGuidePage(circleId: 'circle-1', circleName: 'Book Club'),
    'editor': () => GuideEditor(
      detail: circleDetail(),
      initial: CircleGuideConfig.fromJson(
        guideConfigJson(
          greetingChannelId: 'ch-general',
          prompts: [
            {
              'id': 'prompt-1',
              'title': 'What do you play?',
              'required': false,
              'single_select': false,
              'options': [
                {
                  'id': 'opt-chess',
                  'label': 'Chess',
                  'emoji': '♟',
                  'role_ids': ['role-photo', 'role-mods'],
                  'channel_ids': ['ch-general'],
                },
                {
                  'id': 'opt-go',
                  'label': 'Go',
                  'emoji': '⚫',
                  'role_ids': <String>[],
                  'channel_ids': <String>[],
                },
              ],
            },
          ],
          tasks: [
            {
              'id': 'task-1',
              'title': 'Read the rules',
              'action': 'read_rules',
              'channel_id': null,
            },
            {
              'id': 'task-2',
              'title': 'Have a look around',
              'action': 'visit_channel',
              'channel_id': 'ch-general',
            },
          ],
        ),
      ),
    ),
    'card': () => Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          NewcomerCard(
            conversationId: 'conv-welcome',
            notice: NewcomerNotice(userId: 'user-9', userLabel: 'Nia'),
          ),
          NewcomerCard(
            conversationId: 'conv-welcome',
            notice: NewcomerNotice(userId: 'me', userLabel: 'Grace'),
          ),
        ],
      ),
    ),
  };

  for (final MapEntry(key: screenName, value: build) in screens.entries) {
    for (final (variantName, size, theme) in variants) {
      final name = '$screenName-$variantName';
      testWidgets('guide $name', (tester) async {
        AppStrings.isChinese = _zh;
        addTearDown(() => AppStrings.isChinese = false);
        tester.view.physicalSize = screenName == 'card'
            ? Size(size.width, 240)
            : size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final rpc = GuideRpc()..answer('get_circle_guide', _guide());
        await tester.pumpWidget(
          ProviderScope(
            retry: noProviderRetry,
            overrides: [
              circleRpcProvider.overrideWithValue(rpc.call),
              authRepositoryProvider.overrideWithValue(_SignedIn()),
              circleEmojisProvider('circle-1').overrideWith(
                (ref) async => [
                  CircleEmoji(
                    id: 'sticker-wave',
                    circleId: 'circle-1',
                    name: 'wave',
                    kind: CircleEmojiKind.sticker,
                    storagePath: 'x/wave.png',
                    mimeType: 'image/png',
                    createdAt: DateTime.utc(2026, 10, 1),
                  ),
                ],
              ),
            ],
            child: MaterialApp(
              theme: theme,
              debugShowCheckedModeBanner: false,
              home: build(),
            ),
          ),
        );
        for (var round = 0; round < 3; round++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await tester.pumpAndSettle();
        }
        final renderView = tester.binding.renderViews.first;
        final layer = renderView.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final image = await layer.toImage(renderView.paintBounds);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$_outputDir/$name.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
