// The chat polish screens (A9 quoting part of a message and silent sending,
// A10 voice message speed and trimming, E6 voice channel status, connection
// hint and audio only), for the accessibility guard (guidelines_test.dart)
// and the accessibility screenshot tool.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_polish/voice_playback.dart';
import 'package:wecord/features/chats/chat_polish/voice_trim.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_polish.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../features/transcribe/transcribe_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _body =
    'The meeting moved to Friday at noon. Bring the slides, and the new '
    'budget if you have it.';

Future<void> _openThread(WidgetTester tester, PhoneWorld world) async {
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

Future<void> _quotePicker(WidgetTester tester, PhoneWorld world) async {
  world.chats.messages = [
    phoneMessage('m0', bart, 'Morning!', minutesAgo: 60),
    phoneMessage('m1', bart, _body, minutesAgo: 30),
  ];
  await _openThread(tester, world);
  await tester.longPress(find.textContaining('The meeting moved').first);
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('message-action-quote-reply')));
  await settle(tester);
}

Future<void> _quotedThread(WidgetTester tester, PhoneWorld world) async {
  world.chats.messages = [
    phoneMessage('m1', bart, _body, minutesAgo: 30),
    phoneMessage(
      'm2',
      me,
      'Friday is bad for me, can we move it?',
      minutesAgo: 25,
      replyPreview: const ReplyPreview(
        messageId: 'm1',
        senderName: 'Message',
        body: _body,
        type: MessageType.text,
        quote: ReplyQuote(text: 'moved to Friday at noon', start: 12, end: 34),
      ),
    ),
    phoneMessage(
      'm3',
      me,
      'Sleep well, talk tomorrow',
      minutesAgo: 5,
      silent: true,
    ),
  ];
  await _openThread(tester, world);
}

Uint8List _wav(int ms) {
  final frames = ms * 8;
  final data = Uint8List(frames * 2);
  final view = ByteData.sublistView(data);
  for (var i = 0; i < frames; i++) {
    final swell = 1 - ((i / frames) - 0.5).abs() * 1.4;
    view.setInt16(
      i * 2,
      (swell * 20000 * ((i ~/ 40) % 2 == 0 ? 1 : -1)).round(),
      Endian.little,
    );
  }
  final out = Uint8List(44 + data.length);
  final header = ByteData.sublistView(out);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      out[at + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 8000, Endian.little);
  header.setUint32(28, 16000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  out.setRange(44, out.length, data);
  return out;
}

Future<void> _trimSheet(WidgetTester tester, PhoneWorld world) async {
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    showVoiceTrimSheet(
      context,
      wav: _wav(7200),
      initial: const VoiceTrimRange(startMs: 900, endMs: 5600),
    ),
  );
  await settle(tester);
}

class _FastSpeed extends VoicePlaybackSpeed {
  @override
  double build() => 1.5;
}

Future<void> _speedChip(WidgetTester tester, PhoneWorld world) async {
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Center(
        child: SizedBox(
          width: 340,
          child: VoiceMessagePlayer(attachment: testVoice),
        ),
      ),
    ),
    extraOverrides: [voicePlaybackSpeedProvider.overrideWith(_FastSpeed.new)],
  );
}

VoiceCallParticipant _withVideo() => VoiceCallParticipant(
  userId: bart.id,
  name: 'Bart the Bold',
  microphoneEnabled: true,
  cameraEnabled: true,
  cameraView: (context) => const ColoredBox(color: Color(0xFF2A4D5C)),
);

Future<void> _joinLounge(
  WidgetTester tester,
  PhoneWorld world, {
  VoiceConnectionQuality quality = VoiceConnectionQuality.good,
  bool video = false,
}) async {
  world.circles.detail = circleDetailWithVoice();
  world.voice.channelStatuses['circle-1'] = {'ch-lounge': 'Playing ranked'};
  world.voiceCalls.prepare = (call) {
    call.connectionQuality = quality;
    call.remotes = [
      if (video) _withVideo(),
      VoiceCallParticipant(
        userId: grace.id,
        name: grace.displayName,
        isSpeaking: true,
        microphoneEnabled: true,
      ),
    ];
  };
  await world.open(tester, '/circles/circle-1');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  // Clear of the floating user panel.
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('circle-channel-row-ch-lounge')));
  await settle(tester);
}

/// The hint on its own, on the room's dark backdrop (the room's control bar
/// has its own checks elsewhere).
Future<void> _poorConnection(WidgetTester tester, PhoneWorld world) async {
  world.voiceCalls.prepare = (call) {
    call.connectionQuality = VoiceConnectionQuality.poor;
    call.remotes = [_withVideo()];
  };
  await pumpStandalone(
    tester,
    world,
    VoiceRoomTheme(
      child: Scaffold(
        backgroundColor: WeCordTokens.dark.colors.paper,
        body: const SafeArea(
          child: Column(children: [SizedBox(height: 56), VoiceQualityBanner()]),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  await container
      .read(voiceSessionProvider.notifier)
      .join(
        circleId: 'circle-1',
        channelId: 'ch-lounge',
        conversationId: 'conv-lounge',
        channelName: 'Lounge',
      );
  await tester.pump(poorConnectionHintDelay + const Duration(seconds: 1));
  await settle(tester);
}

Future<void> _statusSheet(WidgetTester tester, PhoneWorld world) async {
  await _joinLounge(tester, world);
  await tester.tap(find.byKey(const ValueKey('voice-status-button')));
  await settle(tester);
}

final chatPolishA11yScreens = <A11yScreen>[
  A11yScreen('quote-reply-picker', _quotePicker),
  A11yScreen('quote-reply-thread', _quotedThread),
  A11yScreen(
    'quote-reply-thread-desktop',
    _quotedThread,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen('voice-trim-sheet', _trimSheet),
  A11yScreen('voice-message-speed', _speedChip),
  A11yScreen('voice-channel-status-sheet', _statusSheet),
  A11yScreen('voice-poor-connection-hint', _poorConnection),
];
