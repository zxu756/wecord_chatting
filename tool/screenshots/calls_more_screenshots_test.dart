// Renders the call extras (call links, the mini player, reactions, screen
// share zoom and focus, background blur) with real fonts and writes PNGs,
// phone and desktop. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/calls_more_screenshots_test.dart \
//     --dart-define=CALLS_MORE_DIR=build/calls-more
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (files get a
// -dark suffix) and --dart-define=PHONE_SCREENS_ZH=true for Chinese.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/voice/background/video_background.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/voice/call_links_fakes.dart';
import '../../test/features/voice/voice_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'CALLS_MORE_DIR',
  defaultValue: 'build/calls-more',
);
const _dark = bool.fromEnvironment('PHONE_SCREENS_DARK');
const _zh = bool.fromEnvironment('PHONE_SCREENS_ZH');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(loadScreenshotFonts);

  final suffix = '${_dark ? '-dark' : '-light'}${_zh ? '-zh' : ''}';

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    bool settleFirst = true,
  }) async {
    if (settleFirst) {
      await settle(tester);
    } else {
      await tester.pump();
    }
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name$suffix.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      Future<void> Function([bool settleFirst]) take,
    )
    body, {
    bool desktop = false,
  }) {
    testWidgets('$name${desktop ? '-desktop' : '-phone'}', (tester) async {
      usePhoneViewport(tester, desktop ? _desktop : notchedPhone);
      final world = PhoneWorld();
      await body(
        tester,
        world,
        ([settleFirst = true]) => shoot(
          tester,
          '$name-${desktop ? 'desktop' : 'phone'}',
          settleFirst: settleFirst,
        ),
      );
      await world.close(tester);
    });
  }

  final links = FakeCallLinksRepository();

  void withLinks(PhoneWorld world) {
    world.extraOverrides = [
      callLinksRepositoryProvider.overrideWithValue(links),
    ];
  }

  void withVoice(PhoneWorld world, {bool screens = true, bool video = true}) {
    world.circles.detail = circleDetailWithVoice();
    world.voice.states['circle-1'] = [
      voiceMember(userId: bart.id, name: bart.displayName),
      voiceMember(userId: grace.id, name: grace.displayName),
      voiceMember(userId: linus.id, name: 'Linus', selfMute: true),
    ];
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: bart.displayName,
          isSpeaking: true,
          microphoneEnabled: true,
        ),
        VoiceCallParticipant(
          userId: grace.id,
          name: grace.displayName,
          microphoneEnabled: true,
          cameraEnabled: video,
          cameraView: video
              ? (context) => const ColoredBox(
                  color: Color(0xFF35506B),
                  child: Center(
                    child: Icon(Icons.person, size: 72, color: Colors.white54),
                  ),
                )
              : null,
          screenShareEnabled: screens,
          screenView: screens ? (context) => const _FakeSlides() : null,
        ),
        VoiceCallParticipant(userId: linus.id, name: 'Linus'),
      ];
    };
  }

  Future<void> joinLounge(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
  }

  Future<void> openLounge(WidgetTester tester, PhoneWorld world) async {
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-lounge',
      extra: const ChatThreadRouteExtra(
        title: 'Lounge',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await tester.tap(find.byKey(const ValueKey('voice-join-button')));
    await settle(tester);
  }

  for (final desktop in [false, true]) {
    screen('01-call-link-sheet', (tester, world, take) async {
      withLinks(world);
      withVoice(world);
      await links.create(
        const CallLinkTarget.channel('ch-lounge'),
        CallLinkExpiry.week,
      );
      await links.create(
        const CallLinkTarget.channel('ch-lounge'),
        CallLinkExpiry.never,
      );
      await openLounge(tester, world);
      await tester.tap(find.byKey(const ValueKey('voice-call-link-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('call-link-create')));
      await take();
    }, desktop: desktop);

    screen('02-call-link-no-access', (tester, world, take) async {
      withLinks(world);
      links.resolutions['abcd2345efgh'] = const CallLinkResolution.problem(
        CallLinkProblem.noAccess,
      );
      await world.open(tester, '/call/abcd2345efgh');
      await take();
    }, desktop: desktop);

    screen('03-call-link-expired', (tester, world, take) async {
      withLinks(world);
      links.resolutions['abcd2345efgh'] = const CallLinkResolution.problem(
        CallLinkProblem.expired,
      );
      await world.open(tester, '/call/abcd2345efgh');
      await take();
    }, desktop: desktop);

    screen('04-mini-player', (tester, world, take) async {
      withVoice(world);
      await world.open(tester, '/circles/circle-1');
      await joinLounge(tester);
      world.router.go(ChatsScreen.path);
      await settle(tester);
      await take();
    }, desktop: desktop);

    screen('05-reactions', (tester, world, take) async {
      withVoice(world, screens: false);
      await openLounge(tester, world);
      await tester.tap(find.byKey(const ValueKey('voice-control-reactions')));
      await tester.pump();
      final call = world.voiceCalls.last;
      call
        ..receiveReaction(bart.id, '🎉')
        ..receiveReaction(bart.id, '👏')
        ..receiveReaction(grace.id, '❤️')
        ..receiveReaction(me.id, '😂');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await take(false);
      await tester.pump(const Duration(seconds: 3));
    }, desktop: desktop);

    screen('06-screen-zoom', (tester, world, take) async {
      withVoice(world, video: false);
      await openLounge(tester, world);
      final slides = find.byType(_FakeSlides);
      await tester.ensureVisible(slides);
      await settle(tester);
      // Zoom in with the wheel over the slide, then a button more.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(slides)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -160)));
      await settle(tester);
      await take();
    }, desktop: desktop);

    screen('07-spotlight', (tester, world, take) async {
      withVoice(world);
      await openLounge(tester, world);
      await tester.ensureVisible(
        find.byKey(const ValueKey('screen-focus-button')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('screen-focus-button')));
      await take();
    }, desktop: desktop);

    screen('08-background-blur', (tester, world, take) async {
      withVoice(world, screens: false);
      world.voiceCalls.backgroundSupport = VideoBackgroundSupport.inApp;
      await openLounge(tester, world);
      await tester.tap(find.byKey(const ValueKey('voice-control-camera')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('voice-control-blur')));
      await take();
    }, desktop: desktop);
  }
}

class _FakeSlides extends StatelessWidget {
  const _FakeSlides();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1F22),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip plan',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          SizedBox(height: 8),
          Text(
            'Day 1: trailhead at 7:00\nDay 2: ridge walk, camp at the lake\n'
            'Day 3: back by noon',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              'small print: bring snacks',
              style: TextStyle(color: Colors.white38, fontSize: 6),
            ),
          ),
        ],
      ),
    );
  }
}
