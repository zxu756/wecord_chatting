// Advanced chat privacy (G6) and screenshot alerts (G7), for the accessibility
// guard (guidelines_test.dart) and the screenshot tools: the banner under a
// restricted chat's header, the sheet with its switch and its plain "what it
// cannot do", the Settings page (on a phone that can notice screenshots and on
// one that cannot), the chat lines, and the view-once viewer after a
// screenshot and while the screen is recorded, at large text, narrow and with
// Care mode on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_notice.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_ui.dart';
import 'package:wecord/features/chats/view_once.dart';
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/features/screen_capture/view_once_screenshots.dart';

import '../features/chat_privacy/chat_privacy_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

const _theirs = ChatPrivacy(restricted: true, requestedBy: {'user-2'});

void _fakes(
  PhoneWorld world, {
  ChatPrivacy privacy = ChatPrivacy.open,
  String conversation = 'dm-1',
  bool detects = false,
  FakeScreenCapture? capture,
}) {
  world.extraOverrides = [
    ...world.extraOverrides,
    chatPrivacyRepositoryProvider.overrideWithValue(
      FakeChatPrivacyRepository(chats: {conversation: privacy}),
    ),
    screenCaptureServiceProvider.overrideWithValue(
      capture ?? (detects ? FakeScreenCapture() : _NoSignal()),
    ),
    viewOnceScreenshotRepositoryProvider.overrideWithValue(
      FakeViewOnceScreenshots(),
    ),
  ];
}

class _NoSignal extends FakeScreenCapture {
  _NoSignal() : super(detects: false);
}

Future<void> _sheet(
  WidgetTester tester,
  PhoneWorld world, {
  required ChatPrivacy privacy,
  bool isGroup = false,
  bool canChange = true,
  bool detects = false,
}) async {
  _fakes(
    world,
    privacy: privacy,
    conversation: isGroup ? 'group-1' : 'dm-1',
    detects: detects,
  );
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    showChatPrivacySheet(
      context,
      conversationId: isGroup ? 'group-1' : 'dm-1',
      isGroup: isGroup,
      canChange: canChange,
    ),
  );
  await settle(tester);
}

Future<void> _banner(WidgetTester tester, PhoneWorld world) async {
  _fakes(world, privacy: _theirs);
  await pumpStandalone(
    tester,
    world,
    const Scaffold(
      body: Column(
        children: [
          ChatPrivacyBanner(
            conversationId: 'dm-1',
            isGroup: false,
            canChange: true,
          ),
        ],
      ),
    ),
  );
}

Future<void> _settings(
  WidgetTester tester,
  PhoneWorld world, {
  required bool detects,
}) async {
  _fakes(world, detects: detects);
  await pumpStandalone(tester, world, const ChatPrivacyScreen());
}

Future<void> _lines(WidgetTester tester, PhoneWorld world) async {
  _fakes(world);
  await pumpStandalone(
    tester,
    world,
    const Scaffold(
      body: SingleChildScrollView(
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
  );
}

const _file = ViewOnceFile(
  url: 'https://example.invalid/x.jpg',
  isVideo: false,
);

Future<void> _viewer(
  WidgetTester tester,
  PhoneWorld world, {
  required ScreenCaptureEvent? event,
  bool detects = true,
}) async {
  final capture = FakeScreenCapture(detects: detects);
  _fakes(world, capture: capture);
  await pumpStandalone(
    tester,
    world,
    const ViewOnceViewer(file: _file, messageId: 'once-1'),
  );
  if (event != null) {
    capture.emit(event);
    await settle(tester);
  }
}

final chatPrivacyA11yScreens = <A11yScreen>[
  A11yScreen(
    'chat-privacy-sheet-off',
    (tester, world) => _sheet(tester, world, privacy: ChatPrivacy.open),
  ),
  A11yScreen(
    'chat-privacy-sheet-off-large-text',
    (tester, world) => _sheet(tester, world, privacy: ChatPrivacy.open),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'chat-privacy-sheet-off-narrow',
    (tester, world) => _sheet(tester, world, privacy: ChatPrivacy.open),
    viewport: smallPhone,
  ),
  A11yScreen('chat-privacy-sheet-off-care-mode', (tester, world) async {
    _care(world);
    await _sheet(tester, world, privacy: ChatPrivacy.open);
  }),
  A11yScreen(
    'chat-privacy-sheet-partner',
    (tester, world) => _sheet(tester, world, privacy: _theirs, detects: true),
  ),
  A11yScreen(
    'chat-privacy-sheet-partner-large-text',
    (tester, world) => _sheet(tester, world, privacy: _theirs, detects: true),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'chat-privacy-sheet-group-member',
    (tester, world) => _sheet(
      tester,
      world,
      privacy: const ChatPrivacy(restricted: true, requestedBy: {'user-2'}),
      isGroup: true,
      canChange: false,
    ),
  ),
  A11yScreen(
    'chat-privacy-sheet-group-admin-narrow',
    (tester, world) => _sheet(
      tester,
      world,
      privacy: ChatPrivacy.open,
      isGroup: true,
      canChange: true,
    ),
    viewport: smallPhone,
  ),
  A11yScreen('chat-privacy-banner', _banner),
  A11yScreen(
    'chat-privacy-banner-large-text',
    _banner,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('chat-privacy-banner-narrow', _banner, viewport: smallPhone),
  A11yScreen('chat-privacy-banner-care-mode', (tester, world) async {
    _care(world);
    await _banner(tester, world);
  }),
  A11yScreen(
    'chat-privacy-settings',
    (tester, world) => _settings(tester, world, detects: false),
  ),
  A11yScreen(
    'chat-privacy-settings-phone',
    (tester, world) => _settings(tester, world, detects: true),
  ),
  A11yScreen(
    'chat-privacy-settings-large-text',
    (tester, world) => _settings(tester, world, detects: true),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'chat-privacy-settings-narrow',
    (tester, world) => _settings(tester, world, detects: false),
    viewport: smallPhone,
  ),
  A11yScreen('chat-notice-lines', _lines),
  A11yScreen(
    'chat-notice-lines-large-text',
    _lines,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('chat-notice-lines-narrow', _lines, viewport: smallPhone),
  A11yScreen(
    'view-once-viewer-screenshot',
    (tester, world) =>
        _viewer(tester, world, event: ScreenCaptureEvent.screenshot),
  ),
  A11yScreen(
    'view-once-viewer-recording',
    (tester, world) =>
        _viewer(tester, world, event: ScreenCaptureEvent.recordingStarted),
  ),
  A11yScreen(
    'view-once-viewer-recording-large-text',
    (tester, world) =>
        _viewer(tester, world, event: ScreenCaptureEvent.recordingStarted),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'view-once-viewer-no-signal-narrow',
    (tester, world) => _viewer(tester, world, event: null, detects: false),
    viewport: smallPhone,
  ),
];
