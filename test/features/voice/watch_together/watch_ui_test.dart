import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';
import 'package:wecord/features/voice/watch_together/watch_together_panel.dart';
import 'package:wecord/features/voice/watch_together/watch_together_sheets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'watch_fakes.dart';

class _Rig {
  _Rig({FakeWatchPlayer Function()? playerBuilder}) {
    world = WatchWorld(ownContainer: false, playerBuilder: playerBuilder);
    currentWatchWorld = world;
  }

  late final WatchWorld world;

  /// The watch button and panel, in the dark voice room.
  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    bool disableAnimations = false,
    Size size = const Size(420, 900),
    bool join = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: world.overrides,
        child: MaterialApp(
          theme: WeCordTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
          home: VoiceRoomTheme(
            child: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    children: const [
                      Row(children: [WatchTogetherButton()]),
                      WatchTogetherPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    world.adopt(
      ProviderScope.containerOf(tester.element(find.byType(Scaffold))),
    );
    if (join) {
      await world.join(tester);
      await tester.pump();
    }
  }

  /// Bart hosts [url]; this device follows.
  Future<void> bartHosts(
    WidgetTester tester, {
    String url = videoUrl,
    String title = 'Movie night',
  }) async {
    await world.receiveStart(
      'user-2',
      url,
      title: title,
      positionMs: 30000,
      playing: true,
    );
    await tester.pump();
  }
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('voice-watch-button')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the button and the start form', () {
    watchTest('are only there in a connected call', (tester) async {
      final rig = _Rig();
      await rig.pump(tester, join: false);
      expect(find.byKey(const ValueKey('voice-watch-button')), findsNothing);
      await rig.world.join(tester);
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-watch-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-card')), findsNothing);
    });

    watchTest('explain that only the position is shared', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await openSheet(tester);
      expect(find.text('Watch or listen together'), findsWidgets);
      expect(
        find.textContaining('never sent through the call'),
        findsOneWidget,
      );
      expect(find.textContaining('headphones'), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-formats')), findsOneWidget);
    });

    watchTest('tell a video from a web page as the link is typed', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await openSheet(tester);
      final field = find.byKey(const ValueKey('watch-link-field'));

      await tester.enterText(field, videoUrl);
      await tester.pump();
      expect(find.text('Video · everyone stays in step'), findsOneWidget);

      await tester.enterText(field, songUrl);
      await tester.pump();
      expect(
        find.text('Music or audio · everyone stays in step'),
        findsOneWidget,
      );

      await tester.enterText(field, pageUrl);
      await tester.pump();
      expect(
        find.textContaining('each person plays it on their own'),
        findsOneWidget,
      );
    });

    watchTest('refuse a link that is not https', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await openSheet(tester);
      await tester.enterText(
        find.byKey(const ValueKey('watch-link-field')),
        'http://media.example.com/a.mp4',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('watch-start')));
      await tester.pump();
      expect(find.text('Only secure https:// links work.'), findsOneWidget);
      expect(rig.world.state.active, isFalse);
    });

    watchTest('start a video: the sheet closes and the host has controls', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await openSheet(tester);
      await tester.enterText(
        find.byKey(const ValueKey('watch-link-field')),
        videoUrl,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('watch-start')));
      await tester.pumpAndSettle();

      expect(rig.world.state.isHost, isTrue);
      expect(find.byKey(const ValueKey('watch-link-field')), findsNothing);
      expect(find.byKey(const ValueKey('watch-card')), findsOneWidget);
      expect(find.text('night.mp4'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-watch-picture')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-play')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-seek')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-mute')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-hide')), findsOneWidget);
    });
  });

  group('the host', () {
    watchTest('plays, pauses and ends from the panel', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.world.watch.start(videoUrl, title: 'Movie night');
      await tester.pumpAndSettle();
      expect(rig.world.state.anchor!.playing, isTrue);

      await tester.tap(find.byKey(const ValueKey('watch-play')));
      await tester.pumpAndSettle();
      expect(rig.world.sent.last['c'], 'pause');
      expect(find.byTooltip('Play'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watch-play')));
      await tester.pumpAndSettle();
      expect(rig.world.sent.last['c'], 'play');
      expect(find.byTooltip('Pause'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watch-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('watch-change')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('watch-end')));
      await tester.pumpAndSettle();
      expect(rig.world.state.active, isFalse);
      expect(rig.world.sent.last['k'], 'e');
      expect(find.byKey(const ValueKey('watch-card')), findsNothing);
    });

    watchTest('changes the link from the options', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.world.watch.start(videoUrl);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('watch-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('watch-change')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('watch-link-field')),
        songUrl,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('watch-start')));
      await tester.pumpAndSettle();

      expect(rig.world.state.sessionId, 'show-2');
      expect(rig.world.state.link!.isAudio, isTrue);
      // A song has no picture to hide.
      expect(find.byKey(const ValueKey('watch-hide')), findsNothing);
      expect(
        find.text('Listening together · You are the host'),
        findsOneWidget,
      );
    });

    watchTest('shows a web page with the note that it is not in step', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.world.watch.start(pageUrl);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('watch-web-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-play')), findsNothing);
      expect(
        find.text('Sharing a web page · You are the host'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('watch-open-link')));
      await tester.pump();
      expect(rig.world.openedLinks, [Uri.parse(pageUrl)]);
    });
  });

  group('a guest', () {
    watchTest('sees what Bart shares and can not steer it', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester);

      expect(find.byKey(const ValueKey('watch-card')), findsOneWidget);
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('Watching together · Hosted by Bart'), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-play')), findsNothing);
      expect(find.byKey(const ValueKey('watch-seek')), findsNothing);
      expect(find.byKey(const ValueKey('watch-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-watch-picture')), findsOneWidget);
    });

    watchTest('mutes and hides only on their own side', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester);

      await tester.tap(find.byKey(const ValueKey('watch-mute')));
      await tester.pump();
      expect(rig.world.state.muted, isTrue);
      expect(rig.world.player.muted, isTrue);
      expect(find.byTooltip('Unmute on my side'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('watch-hide')));
      await tester.pump();
      expect(find.byKey(const ValueKey('watch-card')), findsNothing);
      expect(find.byKey(const ValueKey('watch-bar-hidden')), findsOneWidget);
      expect(rig.world.player.disposed, isFalse);
      expect(rig.world.sent, isEmpty);

      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.byKey(const ValueKey('watch-card')), findsOneWidget);
    });

    watchTest('stops watching and joins again', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester);

      await tester.tap(find.byKey(const ValueKey('watch-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('watch-end')), findsNothing);
      expect(find.byKey(const ValueKey('watch-change')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('watch-sheet-leave')));
      await tester.pumpAndSettle();

      expect(rig.world.state.dismissed, isTrue);
      expect(find.byKey(const ValueKey('watch-bar-dismissed')), findsOneWidget);
      expect(find.text('Bart is watching together'), findsOneWidget);

      await tester.tap(find.text('Join'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('watch-card')), findsOneWidget);
      expect(rig.world.players.length, 2);
    });

    watchTest('is asked for a tap when the browser blocks playing', (
      tester,
    ) async {
      final rig = _Rig(playerBuilder: () => FakeWatchPlayer(refusePlay: true));
      await rig.pump(tester);
      await rig.bartHosts(tester);
      await rig.world.elapse(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('watch-tap-to-play')), findsOneWidget);

      rig.world.player.refusePlay = false;
      await tester.tap(find.byKey(const ValueKey('watch-tap-to-play')));
      await tester.pump();
      expect(rig.world.player.value.playing, isTrue);
      expect(find.byKey(const ValueKey('watch-tap-to-play')), findsNothing);
    });

    watchTest('sees the picture is loading', (tester) async {
      final rig = _Rig(playerBuilder: () => FakeWatchPlayer(autoReady: false));
      await rig.pump(tester);
      await rig.bartHosts(tester);
      expect(find.byKey(const ValueKey('watch-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-watch-picture')), findsNothing);
    });

    watchTest('sees that a link failed and can open it instead', (
      tester,
    ) async {
      final rig = _Rig(
        playerBuilder: () =>
            FakeWatchPlayer(failWith: WatchMediaFailure.timeout),
      );
      await rig.pump(tester);
      await rig.bartHosts(tester, url: hlsUrl);
      expect(find.byKey(const ValueKey('watch-failed')), findsOneWidget);
      expect(find.text('The link took too long to load.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('watch-open-link')));
      await tester.pump();
      expect(rig.world.openedLinks, [Uri.parse(hlsUrl)]);
    });

    watchTest('is told when Bart ends it, and can dismiss the notice', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester);

      await rig.world.receive('user-2', encodeWatchEnd(id: 'remote-1', seq: 9));
      await tester.pump();
      expect(find.byKey(const ValueKey('watch-card')), findsNothing);
      expect(find.text('Bart ended watching together'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(find.byKey(const ValueKey('watch-notice')), findsNothing);
    });

    watchTest('is told when Bart leaves the call', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester);
      await rig.world.removePerson('user-2');
      await tester.pump();
      expect(
        find.text('Bart left, so watching together ended'),
        findsOneWidget,
      );
    });

    watchTest('sees a web page as a note and a button', (tester) async {
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester, url: pageUrl, title: 'Trailer');
      expect(find.text('Trailer'), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-web-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('watch-progress')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('watch-open-link')));
      await tester.pump();
      expect(rig.world.openedLinks.single.host, 'www.youtube.com');
    });
  });

  group('looks', () {
    watchTest('read in Chinese', (tester) async {
      AppStrings.isChinese = true;
      final rig = _Rig();
      await rig.pump(tester);
      await rig.bartHosts(tester);
      expect(find.text('一起看 · 主持人：Bart'), findsOneWidget);
      expect(find.byTooltip('在我这边静音'), findsOneWidget);
      await openSheet(tester);
      expect(find.text('只在我这边停止观看'), findsOneWidget);
    });

    watchTest('hold together with large text on a small phone', (tester) async {
      final rig = _Rig();
      await rig.pump(tester, textScale: 2, size: const Size(360, 640));
      await rig.bartHosts(
        tester,
        title: 'A very long title for a very long film night with everyone',
      );
      expect(tester.takeException(), isNull);
      await rig.world.removePerson('user-2');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    watchTest('stay still when the system asks for no motion', (tester) async {
      final rig = _Rig();
      await rig.pump(tester, disableAnimations: true);
      await rig.bartHosts(tester);
      expect(find.byKey(const ValueKey('watch-card')), findsOneWidget);
    });
  });
}
