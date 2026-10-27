import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/watch/watch_controller.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';

import 'watch_fakes.dart';

/// Moves the test clock and the timers together.
Future<void> elapse(
  WatchWorld world,
  WidgetTester tester,
  Duration time,
) async {
  var left = time;
  while (left > Duration.zero) {
    final step = left < const Duration(seconds: 1)
        ? left
        : const Duration(seconds: 1);
    world.now = world.now.add(step);
    await tester.pump(step);
    left -= step;
  }
}

/// Like [elapse], with the player moving on as a real one would.
Future<void> playAlong(
  WatchWorld world,
  WidgetTester tester,
  Duration time,
) async {
  for (var i = 0; i < time.inSeconds; i++) {
    if (world.player.playing) {
      world.player.at += const Duration(seconds: 1);
    }
    await elapse(world, tester, const Duration(seconds: 1));
  }
}

void main() {
  watchTest('the host starts something and the call is told', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    // Joining asks the call what is on.
    expect(watchSent(world.call).single['k'], 'req');
    expect(world.state.active, isFalse);
    expect(world.watch.canStart, isTrue);

    expect(await world.watch.start(sampleFile(), title: 'Film night'), isTrue);
    await tester.pump();

    expect(world.state.active, isTrue);
    expect(world.state.hostId, 'user-1');
    expect(world.watch.isHost, isTrue);
    expect(world.state.title, 'Film night');
    expect(world.opened.single, sampleFile());
    expect(world.state.load, WatchLoad.ready);
    final start = watchSent(world.call).last;
    expect(start['k'], 'start');
    expect(start['sid'], 'session0001');
    expect(start['ti'], 'Film night');
    expect(start['pl'], false);
    expect((start['src'] as Map)['p'], chatFilePath);
    // Nothing but names and places travels: no media, no address of media.
    expect(jsonEncode(start), isNot(contains('http')));

    // A person who joins is told again.
    final before = watchSent(world.call).length;
    world.call.remotes = [
      ...world.call.remotes,
      const VoiceCallParticipant(userId: 'user-4', name: 'Dan'),
    ];
    world.call.update();
    await tester.pump();
    expect(watchSent(world.call).length, before + 1);
    expect(watchSent(world.call).last['k'], 'start');
  });

  watchTest('a stage audience can not start', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    world.repository
      ..tokenStage = true
      ..tokenStageSpeaker = false;
    await world.join(tester);
    expect(world.watch.canStart, isFalse);
    expect(await world.watch.start(sampleFile()), isFalse);
    expect(world.state.active, isFalse);
  });

  watchTest('the host plays, pauses and moves for everyone', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();

    await world.watch.togglePlay();
    expect(world.player.plays, 1);
    expect(world.state.playing, isTrue);
    var last = watchSent(world.call).last;
    expect(last['k'], 'st');
    expect(last['pl'], true);
    expect(last['p'], 0);
    expect(last['o'], false, reason: 'the host always says its control switch');

    await world.watch.seekTo(const Duration(minutes: 2));
    expect(world.player.seeks.last, const Duration(minutes: 2));
    last = watchSent(world.call).last;
    expect(last['p'], 120000);
    expect(last['pl'], true);

    world.player.at = const Duration(minutes: 2, seconds: 5);
    await world.watch.togglePlay();
    expect(world.player.pauses, 1);
    last = watchSent(world.call).last;
    expect(last['pl'], false);
    expect(last['p'], 125000);

    // Seeking past the end stops at the end.
    await world.watch.seekTo(const Duration(hours: 5));
    expect(world.player.seeks.last, world.player.length);
  });

  watchTest('while it plays the host repeats where it is', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();
    await world.watch.togglePlay();
    world.player.playing = true;
    final base = watchSent(world.call).length;

    world.player.at = const Duration(seconds: 3);
    await elapse(world, tester, const Duration(seconds: 3));
    final beats = watchSent(world.call).sublist(base);
    expect(beats, isNotEmpty);
    expect(beats.last['k'], 'st');
    expect(beats.last['pl'], true);
    expect(beats.last['p'], inInclusiveRange(2000, 4000));
  });

  watchTest('when the host’s own player stops, the room follows', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();
    await world.watch.togglePlay();
    world.player.playing = true;
    await elapse(world, tester, const Duration(seconds: 3));

    // A phone call takes the sound.
    world.player
      ..playing = false
      ..at = const Duration(seconds: 7);
    await elapse(world, tester, const Duration(seconds: 2));
    expect(world.state.playing, isFalse);
    expect(watchSent(world.call).last['pl'], false);
    expect(watchSent(world.call).last['p'], 7000);
  });

  watchTest('a video that ends pauses at its end for everyone', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();
    await world.watch.togglePlay();
    world.player.playing = true;
    await elapse(world, tester, const Duration(seconds: 3));

    world.player
      ..playing = false
      ..ended = true
      ..at = world.player.length;
    await elapse(world, tester, const Duration(seconds: 2));
    expect(world.state.playing, isFalse);
    final last = watchSent(world.call).last;
    expect(last['pl'], false);
    expect(last['p'], world.player.length.inMilliseconds);
  });

  watchTest('someone else’s start is followed and loaded', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);

    await world.receiveStart(
      'user-2',
      position: const Duration(seconds: 30),
      playing: true,
    );

    expect(world.state.active, isTrue);
    expect(world.state.hostId, 'user-2');
    expect(world.watch.isHost, isFalse);
    expect(world.watch.canControl, isFalse);
    expect(world.state.title, 'Film night');
    expect(world.state.load, WatchLoad.ready);
    // Caught up to where the host is, and playing.
    expect(world.player.seeks.single, const Duration(seconds: 30));
    expect(world.player.plays, 1);
    // A follower sends nothing.
    expect(watchSent(world.call).where((p) => p['k'] != 'req'), isEmpty);
    // Followers can not move it.
    await world.watch.togglePlay();
    await world.watch.seekTo(const Duration(minutes: 1));
    expect(world.player.pauses, 0);
    expect(world.player.seeks.length, 1);
  });

  watchTest('a follower drifting more than a second is moved back', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart(
      'user-2',
      position: const Duration(seconds: 30),
      playing: true,
    );
    world.player
      ..playing = true
      ..at = const Duration(seconds: 30);
    world.player.seeks.clear();

    // Half a second off is forgiven.
    await world.receiveState(
      'user-2',
      position: const Duration(milliseconds: 30500),
      playing: true,
    );
    expect(world.player.seeks, isEmpty);

    // Three seconds off is not, once the player has settled.
    await playAlong(world, tester, const Duration(seconds: 4));
    await world.receiveState(
      'user-2',
      position: const Duration(seconds: 38),
      playing: true,
    );
    expect(world.player.seeks.single, const Duration(seconds: 38));

    // The host pauses: the follower pauses where the host stopped.
    await playAlong(world, tester, const Duration(seconds: 4));
    await world.receiveState(
      'user-2',
      position: const Duration(seconds: 40),
      playing: false,
    );
    expect(world.player.pauses, 1);
    expect(world.player.seeks.last, const Duration(seconds: 40));
    expect(world.state.playing, isFalse);
  });

  watchTest('a follower that is still settling is not moved again', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart(
      'user-2',
      position: const Duration(seconds: 30),
      playing: true,
    );
    world.player
      ..playing = true
      ..at = const Duration(seconds: 10);
    world.player.seeks.clear();

    // Just after the first catch-up the player is still behind.
    await world.receiveState(
      'user-2',
      position: const Duration(seconds: 31),
      playing: true,
    );
    expect(world.player.seeks, isEmpty);

    await elapse(world, tester, const Duration(seconds: 4));
    expect(world.player.seeks, isNotEmpty);
  });

  watchTest('only the host’s state counts, until control is opened', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2');

    await world.receiveState(
      'user-3',
      position: const Duration(minutes: 5),
      playing: true,
    );
    expect(world.state.playing, isFalse);
    expect(world.player.plays, 0);

    // The host opens control.
    await world.receiveState('user-2', open: true);
    expect(world.state.controlOpen, isTrue);
    expect(world.watch.canControl, isTrue);

    await world.receiveState(
      'user-3',
      position: const Duration(minutes: 5),
      playing: true,
    );
    expect(world.state.playing, isTrue);
    expect(world.player.seeks.last, const Duration(minutes: 5));
    expect(world.state.authorityId, 'user-3');

    // Now this person can too, and the packet says so.
    await world.watch.togglePlay();
    expect(watchSent(world.call).last['pl'], false);
    expect(
      watchSent(world.call).last.containsKey('o'),
      isFalse,
      reason: 'only the host says the control switch',
    );

    // A controller can not close it, only the host.
    await world.receiveState('user-3', open: false);
    expect(world.state.controlOpen, isTrue);
    await world.receiveState('user-2', open: false);
    expect(world.state.controlOpen, isFalse);
  });

  watchTest('the host opens control for everyone', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();

    await world.watch.setControlOpen(true);
    expect(world.state.controlOpen, isTrue);
    expect(watchSent(world.call).last['o'], true);

    // Someone else’s state is then taken.
    await world.receiveState(
      'user-2',
      sid: 'session0001',
      position: const Duration(seconds: 50),
      playing: true,
    );
    expect(world.state.playing, isTrue);
    expect(world.state.authorityId, 'user-2');
  });

  watchTest('a link to a file asks before loading', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    final link = WatchLinkSource.tryParse(
      'https://cdn.example.com/a/song.mp3',
    )!;

    await world.receiveStart('user-2', source: link, title: 'song.mp3');
    expect(world.state.load, WatchLoad.needsConsent);
    expect(world.state.consent, WatchConsent.link);
    expect(world.opened, isEmpty, reason: 'nothing is loaded before yes');

    world.watch.acceptConsent();
    await tester.pump();
    expect(world.opened.single, link);
    expect(world.state.load, WatchLoad.ready);
  });

  watchTest('audio only does not load a video until asked', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.container
        .read(voiceSessionProvider.notifier)
        .setAudioOnly(true);
    await tester.pump();

    await world.receiveStart('user-2');
    expect(world.state.load, WatchLoad.needsConsent);
    expect(world.state.consent, WatchConsent.dataSaving);
    expect(world.opened, isEmpty);

    // A song is fine.
    await world.receiveStart(
      'user-2',
      sid: 'remote000002',
      source: sampleFile(audio: true),
    );
    expect(world.state.load, WatchLoad.ready);
    expect(world.opened.single, sampleFile(audio: true));
  });

  watchTest('the host leaving ends it for the others', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2');
    expect(world.state.active, isTrue);

    world.call.remotes = [world.call.remotes.last];
    world.call.update();
    await tester.pump();
    expect(world.state.active, isFalse);
    expect(world.player.closed, isTrue);
  });

  watchTest('only the host or a moderator can stop it for everyone', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld(host: false);
    await world.join(tester);
    await world.receiveStart('user-2');

    await world.receive('user-3', encodeWatchStop('remote000001'));
    expect(world.state.active, isTrue);

    // This person is not a moderator, so no button either.
    expect(world.watch.canStop, isFalse);
    await world.watch.stop();
    expect(world.state.active, isTrue);

    world.makeModerator('user-3');
    await tester.pump();
    await world.receive('user-3', encodeWatchStop('remote000001'));
    expect(world.state.active, isFalse);
    expect(world.player.closed, isTrue);
  });

  watchTest('the host stops it for everyone', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();

    await world.watch.stop();
    expect(world.state.active, isFalse);
    expect(watchSent(world.call).last['k'], 'stop');
    expect(world.player.closed, isTrue);
  });

  watchTest('a moderator can stop what someone else started', (tester) async {
    final world = currentWatchWorld = WatchWorld(host: true);
    await world.join(tester);
    await world.receiveStart('user-2');
    expect(world.watch.isHost, isFalse);
    expect(world.watch.canStop, isTrue);

    await world.watch.stop();
    expect(world.state.active, isFalse);
    expect(watchSent(world.call).last['k'], 'stop');
  });

  watchTest('a stranger can not take over a session in progress', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2');

    await world.receiveStart(
      'user-3',
      sid: 'intruder0001',
      title: 'Something else',
    );
    expect(world.state.sessionId, 'remote000001');
    expect(world.state.hostId, 'user-2');

    // The host may change what is watched.
    await world.receiveStart(
      'user-2',
      sid: 'remote000002',
      title: 'Next one',
      source: sampleFile(audio: true),
    );
    expect(world.state.sessionId, 'remote000002');
    expect(world.state.title, 'Next one');
  });

  watchTest('two people starting at once settle on the lower session id', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();
    expect(world.state.sessionId, 'session0001');

    // A higher id loses to ours.
    await world.receiveStart('user-2', sid: 'tzzzzzzzzzzz');
    expect(world.state.sessionId, 'session0001');
    expect(world.watch.isHost, isTrue);

    // A lower one wins, and we follow it.
    await world.receiveStart('user-2', sid: 'aaaaaaaaaaaa');
    expect(world.state.sessionId, 'aaaaaaaaaaaa');
    expect(world.state.hostId, 'user-2');
    expect(world.watch.isHost, isFalse);

    // Later on nobody takes a running session by racing.
    await elapse(world, tester, const Duration(seconds: 30));
    await world.receiveStart('user-3', sid: 'aaaaaaaaaaab');
    expect(world.state.sessionId, 'aaaaaaaaaaaa');
  });

  watchTest('a session that the host left can be replaced', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2');
    world.call.remotes = [world.call.remotes.last];
    world.call.update();
    await tester.pump();
    expect(world.state.active, isFalse);

    await world.receiveStart('user-3', sid: 'other0000001');
    expect(world.state.hostId, 'user-3');
  });

  watchTest('people you blocked can not start anything for you', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld(
      blocked: [blockedProfile('user-2')],
    );
    await world.join(tester);
    await tester.pump();
    await world.receiveStart('user-2');
    expect(world.state.active, isFalse);
    expect(world.opened, isEmpty);

    await world.receiveStart('user-3', sid: 'remote000002');
    expect(world.state.active, isTrue);
  });

  watchTest('a file from another chat is ignored', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart(
      'user-2',
      source: const WatchFileSource(
        path: 'conv-other/9-secret.mp4',
        name: 'secret.mp4',
        mimeType: 'video/mp4',
        size: 1,
        isAudio: false,
      ),
    );
    expect(world.state.active, isFalse);
    expect(world.opened, isEmpty);
  });

  watchTest('garbage and a flood on the topic change nothing', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receive('user-2', utf8.encode('{"v":1,"k":"start"}'));
    await world.receive('user-2', utf8.encode('nope'));
    expect(world.state.active, isFalse);

    // Another topic is not ours.
    world.call.receiveData('user-2', 'wecord.caption', utf8.encode('{}'));
    await tester.pump();
    expect(world.state.active, isFalse);

    for (var i = 0; i < 40; i++) {
      world.call.receiveData('user-3', watchTopic, encodeWatchRequest());
    }
    await tester.pump();
    await world.receiveStart('user-3');
    expect(world.state.active, isFalse, reason: 'the sender was limited');
  });

  watchTest('a media that will not load says so and can be retried', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    world.openError = Exception('403');
    await world.join(tester);
    await world.receiveStart('user-2');
    expect(world.state.load, WatchLoad.failed);

    world.openError = null;
    world.watch.retry();
    await tester.pump();
    expect(world.state.load, WatchLoad.ready);
  });

  watchTest('a source this device can not play inside the app is external', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    world.noPlayer = true;
    await world.join(tester);
    final youtube = WatchEmbedSource.tryCreate(
      WatchEmbedProvider.youtube,
      'dQw4w9WgXcQ',
    )!;
    await world.receiveStart('user-2', source: youtube, title: 'YouTube');
    expect(world.state.load, WatchLoad.external);
    expect(world.watch.player, isNull);

    // Followers get the host's hints.
    await world.receive(
      'user-2',
      encodeWatchCue('remote000001', WatchCueAction.play),
    );
    expect(world.state.cue!.fromId, 'user-2');
    expect(world.state.cue!.action, WatchCueAction.play);

    // The hint goes away by itself.
    await elapse(world, tester, const Duration(seconds: 13));
    expect(world.state.cue, isNull);

    // Another participant’s hint is ignored while control is closed.
    await world.receive(
      'user-3',
      encodeWatchCue('remote000001', WatchCueAction.pause),
    );
    expect(world.state.cue, isNull);
  });

  watchTest('the host sends hints for a player nobody can drive', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    world.noPlayer = true;
    await world.join(tester);
    final bilibili = WatchEmbedSource.tryCreate(
      WatchEmbedProvider.bilibili,
      'BV1GJ411x7h7',
    )!;
    await world.watch.start(bilibili);
    await tester.pump();
    expect(world.state.load, WatchLoad.external);

    await world.watch.sendCue(WatchCueAction.play);
    final last = watchSent(world.call).last;
    expect(last['k'], 'cue');
    expect(last['a'], 'play');
    expect(world.state.cue!.fromId, 'user-1');
  });

  watchTest('stopping on my screen leaves the others watching', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2', playing: true);
    final first = world.player;

    world.watch.leaveForMe();
    expect(world.state.dismissed, isTrue);
    expect(world.state.active, isTrue);
    expect(first.closed, isTrue);
    expect(world.watch.player, isNull);

    // Messages keep arriving but nothing loads.
    await world.receiveState('user-2', playing: true);
    expect(world.players.length, 1);

    world.watch.rejoin();
    await tester.pump();
    expect(world.state.dismissed, isFalse);
    expect(world.players.length, 2);
    expect(world.state.load, WatchLoad.ready);
  });

  watchTest('muting is for this device only', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2');
    world.watch.setMuted(true);
    expect(world.player.muted, isTrue);
    expect(watchSent(world.call).where((p) => p['k'] != 'req'), isEmpty);
  });

  watchTest('the host answers a newcomer’s question, but not in a burst', (
    tester,
  ) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.watch.start(sampleFile());
    await tester.pump();
    final base = watchSent(world.call).length;

    await world.receive('user-2', encodeWatchRequest());
    await world.receive('user-3', encodeWatchRequest());
    expect(watchSent(world.call).length, base + 1);
    expect(watchSent(world.call).last['k'], 'start');

    await elapse(world, tester, const Duration(seconds: 3));
    await world.receive('user-3', encodeWatchRequest());
    expect(
      watchSent(world.call).where((p) => p['k'] == 'start').length,
      greaterThanOrEqualTo(3),
    );
  });

  watchTest('leaving the call forgets everything', (tester) async {
    final world = currentWatchWorld = WatchWorld();
    await world.join(tester);
    await world.receiveStart('user-2');
    expect(world.state.active, isTrue);

    await world.container.read(voiceSessionProvider.notifier).leave();
    await tester.pump();
    expect(world.state.active, isFalse);
    expect(world.state.callKey, isNull);
    expect(world.player.closed, isTrue);
  });
}
