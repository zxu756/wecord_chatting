// Screenshots of "Help me reply" (F6), to look at for overflow: the AI menu of
// the message box with its new row, the "+" menu entry on a phone, the sheet
// asking what to say, three suggested replies (one long) and a refusal.
//
// Always runs (a layout overflow fails the test) and writes PNGs into
// build/ai_suggest/: phone, narrow phone at 2x text, Care mode, and desktop,
// light and dark, English and Chinese. The text uses a system font found on
// this machine (macOS) so that it can be read in the pictures; without one the
// layout is still checked.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/draft_reply/draft_reply_repository.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../features/ai/ai_chat_app.dart';
import '../features/chats/chat_thread_screen_test.dart' as chat_fakes;
import '../features/ai/ai_fakes.dart';
import '../features/ai/draft_reply_fakes.dart';

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

typedef _Variant = ({
  String label,
  Size size,
  bool dark,
  double text,
  bool care,
  bool desktop,
});

const _variants = <_Variant>[
  (
    label: 'phone-light',
    size: Size(390, 844),
    dark: false,
    text: 1,
    care: false,
    desktop: false,
  ),
  (
    label: 'phone-dark',
    size: Size(390, 844),
    dark: true,
    text: 1,
    care: false,
    desktop: false,
  ),
  (
    label: 'narrow-large-text',
    size: Size(360, 640),
    dark: false,
    text: 2,
    care: false,
    desktop: false,
  ),
  (
    label: 'care-mode',
    size: Size(390, 844),
    dark: false,
    text: 1.3,
    care: true,
    desktop: false,
  ),
  (
    label: 'desktop-light',
    size: Size(1100, 800),
    dark: false,
    text: 1,
    care: false,
    desktop: true,
  ),
  (
    label: 'desktop-dark',
    size: Size(1100, 800),
    dark: true,
    text: 1,
    care: false,
    desktop: true,
  ),
];

FakeDraftReplyRepository _replies() =>
    FakeDraftReplyRepository()
      ..replies = const [
        'Sounds good, 8:30 works for me.',
        'Yes, 8:30 at the north lot is fine with me. Thanks for organizing the '
            'whole trip, and I can bring the extra headlamps and a thermos of '
            'tea for everyone if that helps.',
        'Could we make it 9 instead? The earlier train is hard for me.',
      ];

const _zhReplies = [
  '好的，8:30 我可以。',
  '可以，8:30 在北停车场集合没问题。谢谢你组织这次行程，我可以多带几个头灯，再带一壶茶给大家，如果需要的话。',
  '能不能改到 9 点？早一班车对我来说有点赶。',
];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String name,
  _Variant variant,
) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  final png = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  final directory = Directory('build/ai_suggest')..createSync(recursive: true);
  File(
    '${directory.path}/$name-${variant.label}${AppStrings.isChinese ? '-zh' : ''}.png',
  ).writeAsBytesSync(png!);
}

Future<void> _open(
  WidgetTester tester,
  GlobalKey key,
  _Variant variant,
  FakeDraftReplyRepository replies,
) async {
  tester.view.physicalSize = variant.size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = variant.text;
  final harness = AiChatHarness(
    FakeAiRepository(),
    extraOverrides: [
      draftReplyRepositoryProvider.overrideWithValue(replies),
      voiceMessageRecorderProvider.overrideWithValue(
        chat_fakes.FakeVoiceMessageRecorder(),
      ),
      if (variant.care)
        careModeStoreProvider.overrideWithValue(
          InMemoryCareModeStore(const CareModeSettings(enabled: true)),
        ),
    ],
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: harness.build(
        theme: variant.dark ? WeCordTheme.dark() : WeCordTheme.light(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _openHelpSheet(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('chat-composer-field')),
    AppStrings.isChinese ? '好的，我可以' : 'yes, I can come',
  );
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('composer-ai-button')));
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await _loadFont();
  });

  for (final chinese in [false, true]) {
    final suffix = chinese ? ' in Chinese' : '';

    void screen(
      String description,
      Future<void> Function(WidgetTester tester, _Variant variant) body, {
      bool desktopOnly = false,
      bool phoneOnly = false,
    }) {
      for (final variant in _variants) {
        if ((desktopOnly && !variant.desktop) ||
            (phoneOnly && variant.desktop)) {
          continue;
        }
        testWidgets('$description ${variant.label}$suffix', (tester) async {
          AppStrings.isChinese = chinese;
          addTearDown(() => AppStrings.isChinese = false);
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          await body(tester, variant);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }

    FakeDraftReplyRepository replies() {
      final fake = _replies();
      if (chinese) {
        fake.replies = _zhReplies;
      }
      return fake;
    }

    screen('the AI menu of the message box', (tester, variant) async {
      final key = GlobalKey();
      await _open(tester, key, variant, replies());
      await _openHelpSheet(tester);
      expect(
        find.byKey(const ValueKey('ai-rewrite-help-reply')),
        findsOneWidget,
      );
      await _capture(tester, key, 'ai-menu', variant);
    });

    screen('the plus menu', (tester, variant) async {
      final key = GlobalKey();
      await _open(tester, key, variant, replies());
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await _settle(tester);
      if (variant.care) {
        // Care mode keeps the everyday entries only.
        expect(
          find.byKey(const ValueKey('composer-draft-reply-entry')),
          findsNothing,
        );
      } else {
        await tester.ensureVisible(
          find.byKey(const ValueKey('composer-draft-reply-entry')),
        );
        await _settle(tester);
      }
      await _capture(tester, key, 'plus-menu', variant);
    }, phoneOnly: true);

    screen('the sheet asking what to say', (tester, variant) async {
      final key = GlobalKey();
      await _open(tester, key, variant, replies());
      await _openHelpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('draft-reply-intent')), findsOneWidget);
      await _capture(tester, key, 'sheet', variant);
    });

    screen('three suggested replies', (tester, variant) async {
      final key = GlobalKey();
      await _open(tester, key, variant, replies());
      await _openHelpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('draft-reply-option-1')),
        findsOneWidget,
      );
      await _capture(tester, key, 'replies', variant);
    });

    screen('a locked chat', (tester, variant) async {
      final key = GlobalKey();
      await _open(
        tester,
        key,
        variant,
        replies()..error = const AiChatLockedException(),
      );
      await _openHelpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('ai-rewrite-help-reply')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('draft-reply-suggest')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('draft-reply-error')), findsOneWidget);
      await _capture(tester, key, 'locked', variant);
    });
  }
}
