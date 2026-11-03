// Watching and listening together in a call (E4: the start form, the host's
// and a guest's panel for a video, a song and a web page, the loading,
// failed and tap-to-play states, the slim bars, the notice and the
// options), for the accessibility guard (guidelines_test.dart) and the
// accessibility screenshot tool.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';
import 'package:wecord/features/voice/watch_together/watch_together_controller.dart';
import 'package:wecord/features/voice/watch_together/watch_together_panel.dart';
import 'package:wecord/features/voice/watch_together/watch_together_sheets.dart';
import 'package:wecord/shared/theme/wecord_tokens.dart';

import '../features/voice/watch_together/watch_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

const _filmLink = 'https://media.example.com/films/the-long-way-home.mp4';
const _songLink = 'https://media.example.com/music/road-trip-mix.mp3';
const _pageLink = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

/// A picture to look at where the video would be.
Widget _scene() => const DecoratedBox(
  key: ValueKey('fake-watch-picture'),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF283C86), Color(0xFF45A247)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  child: Center(
    child: Icon(Icons.movie_creation_outlined, size: 56, color: Colors.white54),
  ),
);

FakeWatchPlayer _film({bool refusePlay = false, bool autoReady = true}) =>
    FakeWatchPlayer(
      duration: const Duration(hours: 1, minutes: 48, seconds: 30),
      picture: _scene,
      refusePlay: refusePlay,
      autoReady: autoReady,
    );

/// What the watching screens need around the voice room.
List<Override> watchOverrides({FakeWatchPlayer Function()? player}) => [
  watchPlayerFactoryProvider.overrideWithValue(player ?? _film),
  watchLinkOpenerProvider.overrideWithValue((context, uri) async {}),
];

/// A call with Bart and Grace in it.
void watchWorld(PhoneWorld world) {
  world.voiceCalls.prepare = (call) {
    call.remotes = [
      VoiceCallParticipant(
        userId: bart.id,
        name: 'Bart',
        isSpeaking: true,
        microphoneEnabled: true,
      ),
      VoiceCallParticipant(
        userId: grace.id,
        name: 'Grace',
        microphoneEnabled: true,
      ),
    ];
  };
}

/// The watch button and panel on the voice room's dark backdrop, with the
/// user joined to the lounge. Returns the app's container.
Future<ProviderContainer> pumpWatchRoom(
  WidgetTester tester,
  PhoneWorld world, {
  FakeWatchPlayer Function()? player,
}) async {
  watchWorld(world);
  await pumpStandalone(
    tester,
    world,
    VoiceRoomTheme(
      child: Scaffold(
        backgroundColor: WeCordTokens.dark.colors.paper,
        body: const SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: WatchTogetherButton(),
                  ),
                ),
                WatchTogetherPanel(),
              ],
            ),
          ),
        ),
      ),
    ),
    extraOverrides: watchOverrides(player: player),
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

/// Bart shares [url], a little over an hour in.
Future<ProviderContainer> _bartHosts(
  WidgetTester tester,
  PhoneWorld world, {
  String url = _filmLink,
  String title = 'The Long Way Home',
  FakeWatchPlayer Function()? player,
}) async {
  final container = await pumpWatchRoom(tester, world, player: player);
  world.voiceCalls.last.receiveData(
    bart.id,
    watchTopic,
    encodeWatchStart(
      id: 'bart-1',
      link: parseWatchLink(url).link!,
      title: title,
      positionMs: 4325000,
      playing: true,
      seq: 1,
      sentAt: DateTime.now(),
    ),
  );
  await settle(tester);
  return container;
}

Future<ProviderContainer> _iHost(
  WidgetTester tester,
  PhoneWorld world, {
  String url = _filmLink,
  String title = 'The Long Way Home',
}) async {
  final container = await pumpWatchRoom(tester, world);
  await container.read(watchTogetherProvider.notifier).start(url, title: title);
  await settle(tester);
  if (parseWatchLink(url).link!.synced) {
    await container
        .read(watchTogetherProvider.notifier)
        .seek(const Duration(minutes: 23, seconds: 10));
    await settle(tester);
  }
  return container;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('voice-watch-button')));
  await settle(tester);
}

Future<void> _startSheet(WidgetTester tester, PhoneWorld world) async {
  await pumpWatchRoom(tester, world);
  await _openSheet(tester);
}

Future<void> _startSheetFilled(WidgetTester tester, PhoneWorld world) async {
  await _startSheet(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('watch-link-field')),
    _filmLink,
  );
  await settle(tester);
}

Future<void> _startSheetSong(WidgetTester tester, PhoneWorld world) async {
  await _startSheet(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('watch-link-field')),
    _songLink,
  );
  await settle(tester);
}

Future<void> _startSheetPage(WidgetTester tester, PhoneWorld world) async {
  await _startSheet(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('watch-link-field')),
    _pageLink,
  );
  await settle(tester);
}

Future<void> _startSheetError(WidgetTester tester, PhoneWorld world) async {
  await _startSheet(tester, world);
  await tester.enterText(
    find.byKey(const ValueKey('watch-link-field')),
    'http://media.example.com/films/the-long-way-home.mp4',
  );
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('watch-start')));
  await settle(tester);
}

Future<void> _hostVideo(WidgetTester tester, PhoneWorld world) async {
  await _iHost(tester, world);
}

Future<void> _hostSong(WidgetTester tester, PhoneWorld world) async {
  await _iHost(tester, world, url: _songLink, title: 'Road trip mix');
}

Future<void> _hostPage(WidgetTester tester, PhoneWorld world) async {
  await _iHost(tester, world, url: _pageLink, title: 'Trailer');
}

Future<void> _hostOptions(WidgetTester tester, PhoneWorld world) async {
  await _iHost(tester, world);
  await tester.tap(find.byKey(const ValueKey('watch-more')));
  await settle(tester);
}

Future<void> _hostChange(WidgetTester tester, PhoneWorld world) async {
  await _hostOptions(tester, world);
  await tester.tap(find.byKey(const ValueKey('watch-change')));
  await settle(tester);
}

Future<void> _guestVideo(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(tester, world);
}

Future<void> _guestSong(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(
    tester,
    world,
    url: _songLink,
    title: 'Road trip mix',
    player: () => FakeWatchPlayer(duration: const Duration(minutes: 54)),
  );
}

Future<void> _guestPage(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(tester, world, url: _pageLink, title: 'Trailer');
}

Future<void> _guestLoading(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(tester, world, player: () => _film(autoReady: false));
}

Future<void> _guestFailed(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(
    tester,
    world,
    player: () => FakeWatchPlayer(
      failWith: WatchMediaFailure.cannotPlay,
      picture: _scene,
    ),
  );
}

Future<void> _guestTap(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(tester, world, player: () => _film(refusePlay: true));
  await settle(tester);
  await settle(tester);
  await settle(tester);
}

Future<void> _guestOptions(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(tester, world);
  await tester.tap(find.byKey(const ValueKey('watch-more')));
  await settle(tester);
}

Future<void> _guestHidden(WidgetTester tester, PhoneWorld world) async {
  final container = await _bartHosts(tester, world);
  container.read(watchTogetherProvider.notifier).setHidden(true);
  await settle(tester);
}

Future<void> _guestMuted(WidgetTester tester, PhoneWorld world) async {
  final container = await _bartHosts(tester, world);
  await container.read(watchTogetherProvider.notifier).setMuted(true);
  await settle(tester);
}

Future<void> _guestStopped(WidgetTester tester, PhoneWorld world) async {
  final container = await _bartHosts(tester, world);
  container.read(watchTogetherProvider.notifier).leaveMine();
  await settle(tester);
}

Future<void> _notice(WidgetTester tester, PhoneWorld world) async {
  await _bartHosts(tester, world);
  world.voiceCalls.last.receiveData(
    bart.id,
    watchTopic,
    encodeWatchEnd(id: 'bart-1', seq: 9),
  );
  await settle(tester);
}

final watchTogetherA11yScreens = <A11yScreen>[
  A11yScreen('watch-start-sheet', _startSheet),
  A11yScreen('watch-start-sheet-video', _startSheetFilled),
  A11yScreen('watch-start-sheet-song', _startSheetSong),
  A11yScreen('watch-start-sheet-web-page', _startSheetPage),
  A11yScreen('watch-start-sheet-error', _startSheetError),
  A11yScreen('watch-host-video', _hostVideo),
  A11yScreen('watch-host-song', _hostSong),
  A11yScreen('watch-host-web-page', _hostPage),
  A11yScreen('watch-host-options', _hostOptions),
  A11yScreen('watch-host-change-link', _hostChange),
  A11yScreen('watch-guest-video', _guestVideo),
  A11yScreen('watch-guest-song', _guestSong),
  A11yScreen('watch-guest-web-page', _guestPage),
  A11yScreen('watch-guest-loading', _guestLoading),
  A11yScreen('watch-guest-failed', _guestFailed),
  A11yScreen('watch-guest-tap-to-play', _guestTap),
  A11yScreen('watch-guest-options', _guestOptions),
  A11yScreen('watch-guest-picture-hidden', _guestHidden),
  A11yScreen('watch-guest-muted', _guestMuted),
  A11yScreen('watch-guest-stopped', _guestStopped),
  A11yScreen('watch-ended-notice', _notice),
  A11yScreen(
    'watch-host-video-desktop',
    _hostVideo,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'watch-guest-video-desktop',
    _guestVideo,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'watch-start-sheet-desktop',
    _startSheetFilled,
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'watch-host-options-desktop',
    _hostOptions,
    viewport: desktopViewport,
    desktop: true,
  ),
];
