import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/watch/watch_controller.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/features/voice/watch/watch_strip.dart';

import '../../../accessibility/watch_together_a11y_screens.dart';
import '../../../mobile/phone_test_support.dart';
import 'watch_fakes.dart';

Finder key(String name) => find.byKey(ValueKey(name));

List<Map<String, Object?>> sentPackets(PhoneWorld world) =>
    watchSent(world.voiceCalls.last);

void main() {
  testWidgets('no button outside a call', (tester) async {
    final world = PhoneWorld();
    await pumpStandalone(
      tester,
      world,
      const Scaffold(body: WatchTogetherButton()),
    );
    expect(key('voice-watch-button'), findsNothing);
    await world.close(tester);
  });

  testWidgets('the host picks a chat video and everyone is told', (
    tester,
  ) async {
    final world = PhoneWorld();
    final stage = WatchStage();
    await pumpWatchRoom(tester, world, stage, media: watchChatMedia());
    await tester.tap(key('voice-watch-button'));
    await settle(tester);

    expect(find.text('Movie night trailer.mp4'), findsOneWidget);
    expect(find.text('Road trip playlist.mp3'), findsOneWidget);
    await tester.tap(find.text('Movie night trailer.mp4'));
    await settle(tester);

    expect(key('watch-strip'), findsOneWidget);
    expect(find.text('You started this'), findsOneWidget);
    expect(stage.players, hasLength(1));
    final start = sentPackets(world).last;
    expect(start['k'], 'start');
    expect((start['src'] as Map)['n'], 'Movie night trailer.mp4');
    await world.close(tester);
  });

  testWidgets('with no videos in the chat the sheet says so', (tester) async {
    final world = PhoneWorld();
    await pumpWatchRoom(tester, world, WatchStage(), media: const []);
    await tester.tap(key('voice-watch-button'));
    await settle(tester);
    expect(key('watch-no-files'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('a pasted link starts, and a bad one explains itself', (
    tester,
  ) async {
    final world = PhoneWorld();
    final stage = WatchStage()..noPlayer = true;
    await pumpWatchRoom(tester, world, stage, media: const []);
    await tester.tap(key('voice-watch-button'));
    await settle(tester);
    await tester.tap(key('watch-tab-link'));
    await settle(tester);

    await tester.enterText(key('watch-link-field'), 'https://b23.tv/abc');
    await tester.ensureVisible(key('watch-start-link'));
    await tester.tap(key('watch-start-link'));
    await settle(tester);
    expect(key('watch-link-problem'), findsOneWidget);
    expect(sentPackets(world).where((p) => p['k'] == 'start'), isEmpty);

    await tester.enterText(
      key('watch-link-field'),
      'https://youtu.be/dQw4w9WgXcQ',
    );
    await tester.ensureVisible(key('watch-start-link'));
    await tester.tap(key('watch-start-link'));
    await settle(tester);
    expect(key('watch-strip'), findsOneWidget);
    final start = sentPackets(world).last;
    expect(start['k'], 'start');
    expect(start['src'], {'t': 'emb', 'pr': 'yt', 'id': 'dQw4w9WgXcQ'});
    // This app has no YouTube player: the bar opens it in the browser.
    expect(key('watch-open-browser'), findsOneWidget);
    expect(key('watch-cue-play'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('the host plays and moves from the bar', (tester) async {
    final world = PhoneWorld();
    final stage = WatchStage();
    final container = await pumpWatchRoom(tester, world, stage);
    await container
        .read(watchTogetherProvider.notifier)
        .start(
          const WatchFileSource(
            path: 'conv-lounge/1-a.mp4',
            name: 'a.mp4',
            mimeType: 'video/mp4',
            size: 1,
            isAudio: false,
          ),
        );
    await settle(tester);

    await tester.tap(key('watch-play'));
    await settle(tester);
    expect(stage.player.plays, 1);
    expect(sentPackets(world).last['pl'], true);

    await tester.drag(key('watch-slider'), const Offset(200, 0));
    await settle(tester);
    expect(stage.player.seeks, isNotEmpty);
    expect(sentPackets(world).last['p'], greaterThan(0));
    await world.close(tester);
  });

  testWidgets('a guest sees the controls but can not use them', (tester) async {
    final world = PhoneWorld();
    final stage = WatchStage();
    await pumpWatchRoom(tester, world, stage);
    world.voiceCalls.last.receiveData(
      'user-2',
      watchTopic,
      encodeWatchStart(
        WatchStartPacket(
          sessionId: 'remote000001',
          source: const WatchFileSource(
            path: 'conv-lounge/1-a.mp4',
            name: 'a.mp4',
            mimeType: 'video/mp4',
            size: 1,
            isAudio: false,
          ),
          title: 'a.mp4',
          controlOpen: false,
          position: const Duration(seconds: 20),
          playing: true,
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Started by Bart'), findsOneWidget);
    expect(find.text('Following Bart'), findsOneWidget);
    final play = tester.widget<Slider>(key('watch-slider'));
    expect(play.onChanged, isNull);
    await tester.tap(key('watch-play'), warnIfMissed: false);
    await settle(tester);
    expect(stage.player.pauses, 0);
    // They can still mute for themselves.
    await tester.tap(key('watch-mute'));
    await settle(tester);
    expect(stage.player.muted, isTrue);
    await world.close(tester);
  });

  testWidgets('a link asks before it loads', (tester) async {
    final world = PhoneWorld();
    final stage = WatchStage();
    await pumpWatchRoom(tester, world, stage);
    world.voiceCalls.last.receiveData(
      'user-2',
      watchTopic,
      encodeWatchStart(
        WatchStartPacket(
          sessionId: 'remote000001',
          source: WatchLinkSource.tryParse(
            'https://files.example.com/pilot.mp4',
          )!,
          title: 'pilot.mp4',
          controlOpen: false,
          position: Duration.zero,
          playing: false,
        ),
      ),
    );
    await settle(tester);
    expect(stage.players, isEmpty);
    expect(
      find.textContaining('files.example.com'),
      findsOneWidget,
      reason: 'it says whose site is asked',
    );
    await tester.tap(key('watch-accept'));
    await settle(tester);
    expect(stage.players, hasLength(1));
    expect(key('watch-play'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('the host manages: opens control, stops for everyone', (
    tester,
  ) async {
    final world = PhoneWorld();
    final stage = WatchStage();
    final container = await pumpWatchRoom(tester, world, stage);
    await container
        .read(watchTogetherProvider.notifier)
        .start(
          const WatchFileSource(
            path: 'conv-lounge/1-a.mp4',
            name: 'a.mp4',
            mimeType: 'video/mp4',
            size: 1,
            isAudio: false,
          ),
        );
    await settle(tester);

    await tester.tap(key('watch-strip-menu'));
    await settle(tester);
    await tester.tap(key('watch-open-control'));
    await settle(tester);
    expect(container.read(watchTogetherProvider).controlOpen, isTrue);
    expect(sentPackets(world).last['o'], true);

    await tester.tap(key('watch-stop'));
    await settle(tester);
    expect(container.read(watchTogetherProvider).active, isFalse);
    expect(sentPackets(world).last['k'], 'stop');
    expect(key('watch-strip'), findsNothing);
    await world.close(tester);
  });

  testWidgets('a guest can stop watching on their own screen and return', (
    tester,
  ) async {
    final world = PhoneWorld();
    final stage = WatchStage();
    final container = await pumpWatchRoom(tester, world, stage);
    world.voiceCalls.last.receiveData(
      'user-2',
      watchTopic,
      encodeWatchStart(
        WatchStartPacket(
          sessionId: 'remote000001',
          source: const WatchFileSource(
            path: 'conv-lounge/1-a.mp4',
            name: 'a.mp4',
            mimeType: 'video/mp4',
            size: 1,
            isAudio: false,
          ),
          title: 'a.mp4',
          controlOpen: false,
          position: Duration.zero,
          playing: false,
        ),
      ),
    );
    await settle(tester);

    await tester.tap(key('watch-strip-menu'));
    await settle(tester);
    // A guest has no "stop for everyone".
    expect(key('watch-stop'), findsNothing);
    await tester.tap(key('watch-leave-for-me'));
    await settle(tester);
    expect(key('watch-strip-dismissed'), findsOneWidget);
    expect(container.read(voiceSessionProvider), isNotNull);

    await tester.tap(key('watch-strip-resume'));
    await settle(tester);
    expect(key('watch-strip'), findsOneWidget);
    await world.close(tester);
  });

  test('times read well', () {
    expect(formatWatchTime(Duration.zero), '0:00');
    expect(formatWatchTime(const Duration(seconds: 65)), '1:05');
    expect(
      formatWatchTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatWatchTime(const Duration(seconds: -4)), '0:00');
  });
}
