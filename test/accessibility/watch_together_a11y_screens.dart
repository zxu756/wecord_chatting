// Watch Together (E4: the button, the bar with the player and its controls,
// the sheet that starts it and the one that manages it), for the
// accessibility guard (guidelines_test.dart) and the screenshot tools: the
// host's video and song, a guest following, a link that asks first, YouTube
// in the browser and in this app, Bilibili with hints, a failure, a bar
// hidden on this screen, the start sheet (chat files, none, a link with a
// problem) and the manage sheet for a host and a guest.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/watch/watch_controller.dart';
import 'package:wecord/features/voice/watch/watch_player.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/features/voice/watch/watch_strip.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

import '../features/voice/watch/watch_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// The players this screen's call opened, and what opening one does.
class WatchStage {
  final players = <FakeWatchPlayer>[];
  Object? openError;
  bool noPlayer = false;

  FakeWatchPlayer get player => players.last;

  List<Override> overrides({List<ConversationMediaItem>? media}) => [
    watchPlayerFactoryProvider.overrideWithValue((
      source, {
      String? conversationId,
    }) async {
      if (openError != null) {
        throw openError!;
      }
      if (noPlayer) {
        return null;
      }
      final player = FakeWatchPlayer(
        length: const Duration(minutes: 92),
        hasSurface: !source.isAudio,
        remoteControl: source is! WatchEmbedSource || source.remoteControl,
        surfaceInteractive: source is WatchEmbedSource && !source.remoteControl,
      );
      players.add(player);
      return player;
    }),
    if (media != null)
      chatMediaProvider.overrideWith((ref, conversationId) async => media),
  ];
}

ConversationMediaItem _mediaItem(
  String name,
  String mime,
  int size,
  String sender,
) {
  return ConversationMediaItem(
    messageId: 'msg-$name',
    conversationId: 'conv-lounge',
    senderId: 'user-2',
    senderName: sender,
    type: MessageType.file,
    body: '',
    attachment: {
      'kind': mime.startsWith('video/') ? 'video' : 'file',
      'bucket': 'chat-files',
      'path': 'conv-lounge/17-$name',
      'name': name,
      'mime_type': mime,
      'size': size,
    },
    createdAt: DateTime.utc(2026, 10, 27, 20),
  );
}

List<ConversationMediaItem> watchChatMedia() => [
  _mediaItem('Movie night trailer.mp4', 'video/mp4', 18 * 1024 * 1024, 'Bart'),
  _mediaItem('Road trip playlist.mp3', 'audio/mpeg', 7 * 1024 * 1024, 'Grace'),
  _mediaItem('Hike clip.mov', 'video/quicktime', 42 * 1024 * 1024, 'Ada'),
];

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

/// A call with Bart and Grace in it.
void watchWorld(PhoneWorld world, {bool moderator = false}) {
  world.voiceCalls.prepare = (call) {
    call.localCaptionsHost = moderator;
    call.remotes = [
      const VoiceCallParticipant(
        userId: 'user-2',
        name: 'Bart',
        isSpeaking: true,
        microphoneEnabled: true,
      ),
      const VoiceCallParticipant(
        userId: 'user-3',
        name: 'Grace',
        microphoneEnabled: true,
      ),
    ];
  };
}

/// The button and bar on the voice room's dark backdrop, with the user
/// joined to the lounge. Returns the app's container.
Future<ProviderContainer> pumpWatchRoom(
  WidgetTester tester,
  PhoneWorld world,
  WatchStage stage, {
  List<ConversationMediaItem>? media,
  bool moderator = false,
}) async {
  watchWorld(world, moderator: moderator);
  await pumpStandalone(
    tester,
    world,
    VoiceRoomTheme(
      child: Scaffold(
        backgroundColor: WeCordTokens.dark.colors.paper,
        body: const SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: WatchTogetherButton(),
                ),
              ),
              WatchTogetherStrip(),
            ],
          ),
        ),
      ),
    ),
    extraOverrides: stage.overrides(media: media),
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
  await settle(tester);
  return container;
}

WatchFileSource _film() => const WatchFileSource(
  path: 'conv-lounge/17-Movie night trailer.mp4',
  name: 'Movie night trailer.mp4',
  mimeType: 'video/mp4',
  size: 18 * 1024 * 1024,
  isAudio: false,
);

WatchFileSource _song() => const WatchFileSource(
  path: 'conv-lounge/18-Road trip playlist.mp3',
  name: 'Road trip playlist.mp3',
  mimeType: 'audio/mpeg',
  size: 7 * 1024 * 1024,
  isAudio: true,
);

WatchEmbedSource _youtube() =>
    WatchEmbedSource.tryCreate(WatchEmbedProvider.youtube, 'dQw4w9WgXcQ')!;

WatchEmbedSource _bilibili() =>
    WatchEmbedSource.tryCreate(WatchEmbedProvider.bilibili, 'BV1GJ411x7h7')!;

/// This user starts [source], plays it and is [at] into it.
Future<ProviderContainer> _hostWatching(
  WidgetTester tester,
  PhoneWorld world,
  WatchStage stage,
  WatchSource source, {
  Duration at = const Duration(minutes: 12, seconds: 34),
  bool playing = true,
}) async {
  final container = await pumpWatchRoom(tester, world, stage);
  final watch = container.read(watchTogetherProvider.notifier);
  await watch.start(source, title: source.label);
  await settle(tester);
  if (stage.players.isNotEmpty) {
    stage.player.at = at;
  }
  if (playing && stage.players.isNotEmpty && stage.player.remoteControl) {
    await watch.togglePlay();
    stage.player
      ..playing = true
      ..at = at;
  }
  await settle(tester);
  return container;
}

/// Bart started [source] and the user follows.
Future<ProviderContainer> _guestWatching(
  WidgetTester tester,
  PhoneWorld world,
  WatchStage stage,
  WatchSource source, {
  Duration at = const Duration(minutes: 12, seconds: 34),
  bool playing = true,
  bool open = false,
}) async {
  final container = await pumpWatchRoom(tester, world, stage);
  world.voiceCalls.last.receiveData(
    bart.id,
    watchTopic,
    encodeWatchStart(
      WatchStartPacket(
        sessionId: 'remote000001',
        source: source,
        title: source.label,
        controlOpen: open,
        position: at,
        playing: playing,
      ),
    ),
  );
  await settle(tester);
  if (stage.players.isNotEmpty) {
    stage.player
      ..at = at
      ..playing = playing;
  }
  await settle(tester);
  return container;
}

Future<void> _hostVideo(WidgetTester tester, PhoneWorld world) async {
  await _hostWatching(tester, world, WatchStage(), _film());
}

Future<void> _hostVideoCare(WidgetTester tester, PhoneWorld world) async {
  _care(world);
  await _hostWatching(tester, world, WatchStage(), _film());
}

Future<void> _hostSong(WidgetTester tester, PhoneWorld world) async {
  await _hostWatching(
    tester,
    world,
    WatchStage(),
    _song(),
    at: const Duration(minutes: 3, seconds: 5),
  );
}

Future<void> _hostPaused(WidgetTester tester, PhoneWorld world) async {
  await _hostWatching(tester, world, WatchStage(), _film(), playing: false);
}

Future<void> _hostOpenControl(WidgetTester tester, PhoneWorld world) async {
  final container = await _hostWatching(tester, world, WatchStage(), _film());
  await container.read(watchTogetherProvider.notifier).setControlOpen(true);
  await settle(tester);
}

Future<void> _guestVideo(WidgetTester tester, PhoneWorld world) async {
  await _guestWatching(tester, world, WatchStage(), _film());
}

Future<void> _guestBehind(WidgetTester tester, PhoneWorld world) async {
  final stage = WatchStage();
  await _guestWatching(tester, world, stage, _film());
  // The browser held back the sound: the player is not playing yet.
  stage.player
    ..failToPlay = true
    ..playing = false;
  await tester.pump(const Duration(seconds: 1));
  await settle(tester);
}

Future<void> _guestControls(WidgetTester tester, PhoneWorld world) async {
  await _guestWatching(tester, world, WatchStage(), _song(), open: true);
}

Future<void> _guestLink(WidgetTester tester, PhoneWorld world) async {
  await _guestWatching(
    tester,
    world,
    WatchStage(),
    WatchLinkSource.tryParse(
      'https://files.example.com/shows/pilot-episode.mp4',
    )!,
  );
}

Future<void> _guestDataSaving(WidgetTester tester, PhoneWorld world) async {
  final stage = WatchStage();
  final container = await pumpWatchRoom(tester, world, stage);
  await container.read(voiceSessionProvider.notifier).setAudioOnly(true);
  world.voiceCalls.last.receiveData(
    bart.id,
    watchTopic,
    encodeWatchStart(
      WatchStartPacket(
        sessionId: 'remote000001',
        source: _film(),
        title: _film().label,
        controlOpen: false,
        position: Duration.zero,
        playing: false,
      ),
    ),
  );
  await settle(tester);
}

Future<void> _youtubeWeb(WidgetTester tester, PhoneWorld world) async {
  await _hostWatching(tester, world, WatchStage(), _youtube());
}

Future<void> _youtubeApp(WidgetTester tester, PhoneWorld world) async {
  final stage = WatchStage()..noPlayer = true;
  await _hostWatching(tester, world, stage, _youtube());
}

Future<void> _youtubeAppGuest(WidgetTester tester, PhoneWorld world) async {
  final stage = WatchStage()..noPlayer = true;
  final container = await _guestWatching(tester, world, stage, _youtube());
  world.voiceCalls.last.receiveData(
    bart.id,
    watchTopic,
    encodeWatchCue('remote000001', WatchCueAction.play),
  );
  await settle(tester);
  expect(container.read(watchTogetherProvider).cue, isNotNull);
}

Future<void> _bilibiliWeb(WidgetTester tester, PhoneWorld world) async {
  await _hostWatching(tester, world, WatchStage(), _bilibili());
}

Future<void> _bilibiliGuest(WidgetTester tester, PhoneWorld world) async {
  final container = await _guestWatching(
    tester,
    world,
    WatchStage(),
    _bilibili(),
  );
  world.voiceCalls.last.receiveData(
    bart.id,
    watchTopic,
    encodeWatchCue('remote000001', WatchCueAction.pause),
  );
  await settle(tester);
  expect(container.read(watchTogetherProvider).cue, isNotNull);
}

Future<void> _failed(WidgetTester tester, PhoneWorld world) async {
  final stage = WatchStage()..openError = Exception('403');
  await _guestWatching(tester, world, stage, _film());
}

Future<void> _dismissed(WidgetTester tester, PhoneWorld world) async {
  final container = await _guestWatching(tester, world, WatchStage(), _film());
  container.read(watchTogetherProvider.notifier).leaveForMe();
  await settle(tester);
}

Future<void> _startSheet(WidgetTester tester, PhoneWorld world) async {
  await pumpWatchRoom(tester, world, WatchStage(), media: watchChatMedia());
  await tester.tap(find.byKey(const ValueKey('voice-watch-button')));
  await settle(tester);
}

Future<void> _startSheetEmpty(WidgetTester tester, PhoneWorld world) async {
  await pumpWatchRoom(tester, world, WatchStage(), media: const []);
  await tester.tap(find.byKey(const ValueKey('voice-watch-button')));
  await settle(tester);
}

Future<void> _startSheetLink(WidgetTester tester, PhoneWorld world) async {
  await _startSheet(tester, world);
  await tester.ensureVisible(find.byKey(const ValueKey('watch-tab-link')));
  await tester.tap(find.byKey(const ValueKey('watch-tab-link')));
  await settle(tester);
}

Future<void> _startSheetLinkError(WidgetTester tester, PhoneWorld world) async {
  await _startSheetLink(tester, world);
  await tester.ensureVisible(find.byKey(const ValueKey('watch-link-field')));
  await tester.enterText(
    find.byKey(const ValueKey('watch-link-field')),
    'https://b23.tv/abc123',
  );
  await tester.ensureVisible(find.byKey(const ValueKey('watch-start-link')));
  await tester.tap(find.byKey(const ValueKey('watch-start-link')));
  await settle(tester);
}

Future<void> _manageSheetHost(WidgetTester tester, PhoneWorld world) async {
  await _hostWatching(tester, world, WatchStage(), _film());
  await tester.tap(find.byKey(const ValueKey('voice-watch-button')));
  await settle(tester);
}

Future<void> _manageSheetGuest(WidgetTester tester, PhoneWorld world) async {
  await _guestWatching(tester, world, WatchStage(), _film());
  await tester.tap(find.byKey(const ValueKey('voice-watch-button')));
  await settle(tester);
}

final watchTogetherA11yScreens = <A11yScreen>[
  A11yScreen('watch-bar-host-video', _hostVideo),
  A11yScreen('watch-bar-host-video-care', _hostVideoCare),
  A11yScreen('watch-bar-host-song', _hostSong),
  A11yScreen('watch-bar-host-paused', _hostPaused),
  A11yScreen('watch-bar-host-open-control', _hostOpenControl),
  A11yScreen('watch-bar-guest-video', _guestVideo),
  A11yScreen('watch-bar-guest-behind', _guestBehind),
  A11yScreen('watch-bar-guest-can-control', _guestControls),
  A11yScreen('watch-bar-link-asks-first', _guestLink),
  A11yScreen('watch-bar-data-saving', _guestDataSaving),
  A11yScreen('watch-bar-youtube-web', _youtubeWeb),
  A11yScreen('watch-bar-youtube-app', _youtubeApp),
  A11yScreen('watch-bar-youtube-app-guest', _youtubeAppGuest),
  A11yScreen('watch-bar-bilibili-host', _bilibiliWeb),
  A11yScreen('watch-bar-bilibili-guest', _bilibiliGuest),
  A11yScreen('watch-bar-failed', _failed),
  A11yScreen('watch-bar-dismissed', _dismissed),
  A11yScreen('watch-start-sheet', _startSheet),
  A11yScreen('watch-start-sheet-empty', _startSheetEmpty),
  A11yScreen('watch-start-sheet-link', _startSheetLink),
  A11yScreen('watch-start-sheet-link-error', _startSheetLinkError),
  A11yScreen('watch-manage-sheet-host', _manageSheetHost),
  A11yScreen('watch-manage-sheet-guest', _manageSheetGuest),
  A11yScreen(
    'watch-bar-host-video-desktop',
    _hostVideo,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'watch-start-sheet-desktop',
    _startSheet,
    viewport: desktopViewport,
    desktop: true,
  ),
];
