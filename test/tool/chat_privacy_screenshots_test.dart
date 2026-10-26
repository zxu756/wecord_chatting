// Screenshots of advanced chat privacy (G6) and screenshot alerts (G7), to look
// at for overflow: the banner under a restricted chat's header, the sheet with
// its switch and what it cannot do, the Settings page on a phone that can
// notice screenshots and on one that cannot, the chat lines, and the view-once
// viewer after a screenshot and while the screen is recorded.
//
// Always runs (a layout overflow fails the test) and writes PNGs into
// build/chat_privacy/: phone, narrow phone at 2x text, light and dark,
// English and Chinese. The text uses a system font found on this machine
// (macOS) so that it can be read in the pictures; without one the layout is
// still checked.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_notice.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_ui.dart';
import 'package:wecord/features/chats/view_once.dart';
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/features/screen_capture/view_once_screenshots.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../features/chat_privacy/chat_privacy_fakes.dart';
import '../mobile/phone_test_support.dart';

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

typedef _Variant = ({String label, Size size, bool dark, double text});

const _variants = <_Variant>[
  (label: 'phone-light', size: Size(390, 844), dark: false, text: 1),
  (label: 'phone-dark', size: Size(390, 844), dark: true, text: 1),
  (label: 'narrow-large-text', size: Size(360, 640), dark: false, text: 2),
];

const _theirs = ChatPrivacy(restricted: true, requestedBy: {'user-2'});

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required Widget home,
  ChatPrivacy privacy = ChatPrivacy.open,
  String conversation = 'dm-1',
  FakeScreenCapture? capture,
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  for (final variant in _variants) {
    tester.view.physicalSize = variant.size * 2;
    tester.view.devicePixelRatio = 2;
    final world = PhoneWorld();
    world.extraOverrides = [
      chatPrivacyRepositoryProvider.overrideWithValue(
        FakeChatPrivacyRepository(chats: {conversation: privacy}),
      ),
      screenCaptureServiceProvider.overrideWithValue(
        capture ?? FakeScreenCapture(detects: false),
      ),
      viewOnceScreenshotRepositoryProvider.overrideWithValue(
        FakeViewOnceScreenshots(),
      ),
    ];
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          retry: noProviderRetry,
          overrides: world.overrides,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: variant.dark ? WeCordTheme.dark() : WeCordTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.text)),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (afterPump != null) {
      await afterPump(tester);
    }
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
    final directory = Directory('build/chat_privacy')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name-${variant.label}${AppStrings.isChinese ? '-zh' : ''}.png',
    ).writeAsBytesSync(png!);
    // The next variant starts from nothing.
    await tester.pumpWidget(const SizedBox());
  }
}

Future<void> Function(WidgetTester) _openSheet({
  bool isGroup = false,
  bool canChange = true,
}) {
  return (tester) async {
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showChatPrivacySheet(
        context,
        conversationId: isGroup ? 'group-1' : 'dm-1',
        isGroup: isGroup,
        canChange: canChange,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  };
}

const _file = ViewOnceFile(
  url: 'https://example.invalid/x.jpg',
  isVideo: false,
);

void main() {
  setUpAll(() async {
    await _loadFont();
  });

  for (final chinese in [false, true]) {
    final suffix = chinese ? ' in Chinese' : '';

    void screen(
      String description,
      Future<void> Function(WidgetTester tester) body,
    ) {
      testWidgets('$description$suffix', (tester) async {
        AppStrings.isChinese = chinese;
        addTearDown(() => AppStrings.isChinese = false);
        addTearDown(tester.view.reset);
        await body(tester);
        expect(tester.takeException(), isNull);
      });
    }

    screen('the banner of a restricted chat', (tester) async {
      await _shoot(
        tester,
        'banner',
        privacy: _theirs,
        home: const Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                ChatPrivacyBanner(
                  conversationId: 'dm-1',
                  isGroup: false,
                  canChange: true,
                ),
              ],
            ),
          ),
        ),
      );
    });

    screen('the sheet, switch off', (tester) async {
      await _shoot(
        tester,
        'sheet-off',
        home: const Scaffold(body: SizedBox.expand()),
        afterPump: _openSheet(),
      );
    });

    screen('the sheet, the other person turned it on', (tester) async {
      await _shoot(
        tester,
        'sheet-partner',
        privacy: _theirs,
        capture: FakeScreenCapture(),
        home: const Scaffold(body: SizedBox.expand()),
        afterPump: _openSheet(),
      );
    });

    screen('the sheet in a group, for a member', (tester) async {
      await _shoot(
        tester,
        'sheet-group-member',
        conversation: 'group-1',
        privacy: _theirs,
        home: const Scaffold(body: SizedBox.expand()),
        afterPump: _openSheet(isGroup: true, canChange: false),
      );
    });

    screen('Settings on a device that cannot notice screenshots', (
      tester,
    ) async {
      await _shoot(
        tester,
        'settings-no-signal',
        home: const ChatPrivacyScreen(),
      );
    });

    screen('Settings on an iPhone', (tester) async {
      await _shoot(
        tester,
        'settings-iphone',
        capture: FakeScreenCapture(),
        home: const ChatPrivacyScreen(),
      );
    });

    screen('the chat lines', (tester) async {
      await _shoot(
        tester,
        'lines',
        home: const Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ChatNoticeLine(
                    notice: PrivacyNotice(actorName: 'Ada', enabled: true),
                  ),
                  ChatNoticeLine(
                    notice: PrivacyNotice(actorName: 'Ada', enabled: false),
                  ),
                  ChatNoticeLine(
                    notice: ScreenshotNotice(
                      actorName: 'Bartholomew Montgomery-Featherstonehaugh',
                      recording: false,
                      video: false,
                    ),
                  ),
                  ChatNoticeLine(
                    notice: ScreenshotNotice(
                      actorName: 'Bob',
                      recording: false,
                      video: true,
                    ),
                  ),
                  ChatNoticeLine(
                    notice: ScreenshotNotice(
                      actorName: 'Bob',
                      recording: true,
                      video: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });

    screen('the viewer after a screenshot', (tester) async {
      final capture = FakeScreenCapture();
      await _shoot(
        tester,
        'viewer-screenshot',
        capture: capture,
        home: const ViewOnceViewer(file: _file, messageId: 'once-1'),
        afterPump: (tester) async {
          capture.emit(ScreenCaptureEvent.screenshot);
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });

    screen('the viewer while the screen is recorded', (tester) async {
      final capture = FakeScreenCapture();
      await _shoot(
        tester,
        'viewer-recording',
        capture: capture,
        home: const ViewOnceViewer(file: _file, messageId: 'once-1'),
        afterPump: (tester) async {
          capture.emit(ScreenCaptureEvent.recordingStarted);
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
    });

    screen('the viewer on a device that cannot notice', (tester) async {
      await _shoot(
        tester,
        'viewer-no-signal',
        home: const ViewOnceViewer(file: _file, messageId: 'once-1'),
      );
    });
  }
}
