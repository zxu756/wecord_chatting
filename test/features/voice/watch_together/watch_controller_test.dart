import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';
import 'package:wecord/features/voice/watch_together/watch_together_controller.dart';

import 'watch_fakes.dart';

/// The calls to the player that moved it, without `play` and `pause`.
List<String> seeks(FakeWatchPlayer player) => [
  for (final call in player.calls)
    if (call.startsWith('seek:')) call,
];

/// A call where Bart (user-2) is the host of [videoUrl] at 30 s, playing.
Future<WatchWorld> guestWorld(
  WidgetTester tester, {
  FakeWatchPlayer Function()? playerBuilder,
  String url = videoUrl,
  bool playing = true,
}) async {
  final world = WatchWorld(playerBuilder: playerBuilder);
  currentWatchWorld = world;
  await world.join(tester);
  await world.receiveStart(
    'user-2',
    url,
    title: 'Movie night',
    positionMs: 30000,
    playing: playing,
  );
  return world;
}

void main() {
  group('the host', () {
    watchTest('starts a video and presses play for everyone once it loaded', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      expect(w.state.active, isFalse);

      final problem = await w.watch.start(videoUrl, title: 'Movie night');
      await tester.pump();
      await tester.pump();

      expect(problem, isNull);
      expect(w.state.active, isTrue);
      expect(w.state.isHost, isTrue);
      expect(w.state.hostId, 'user-1');
      expect(w.state.sessionId, 'show-1');
      expect(w.state.title, 'Movie night');
      expect(w.state.link!.kind, WatchLinkKind.video);
      expect(w.player.opened!.text, videoUrl);

      // Everyone is told what is on, then that it plays from the start.
      final sent = w.sent;
      expect(sent[0]['k'], 's');
      expect(sent[0]['id'], 'show-1');
      expect(sent[0]['u'], videoUrl);
      expect(sent[0]['t'], 'Movie night');
      expect(sent[0]['r'], 0);
      expect(sent[0]['_reliable'], isTrue);
      expect(sent[1]['k'], 'y');
      expect(sent[1]['c'], 'play');
      expect(sent[1]['r'], 1);
      expect(sent[1]['p'], 0);
      expect(sent[1]['n'], greaterThan(sent[0]['n']! as int));
      expect(w.player.calls, ['seek:0', 'play']);
      expect(w.state.anchor!.playing, isTrue);
    });

    watchTest('names the showing after the file when no title is given', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(songUrl);
      await tester.pump();
      expect(w.state.title, 'song.mp3');
      expect(w.state.link!.isAudio, isTrue);
    });

    watchTest('a web page is announced but never played or kept in step', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      final problem = await w.watch.start(pageUrl);
      await tester.pump();

      expect(problem, isNull);
      expect(w.state.active, isTrue);
      expect(w.state.synced, isFalse);
      expect(w.players, isEmpty);
      expect(w.sent.single['k'], 's');
      expect(w.sent.single['u'], pageUrl);
    });

    watchTest('a link that is not allowed starts nothing', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      expect(
        await w.watch.start('http://media.example.com/a.mp4'),
        WatchLinkProblem.notHttps,
      );
      expect(
        await w.watch.start('https://192.168.0.5/a.mp4'),
        WatchLinkProblem.privateAddress,
      );
      expect(await w.watch.start('  '), WatchLinkProblem.empty);
      expect(w.state.active, isFalse);
      expect(w.sent, isEmpty);
      expect(w.players, isEmpty);
    });

    watchTest('nobody can start while someone else is the host', (
      tester,
    ) async {
      final w = await guestWorld(tester);
      expect(w.watch.canStart, isFalse);
      final problem = await w.watch.start(songUrl);
      expect(problem, isNotNull);
      expect(w.state.hostId, 'user-2');
      expect(w.sent, isEmpty);
    });

    watchTest('pausing, playing and seeking are sent to everyone', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      w.player.advance(const Duration(seconds: 12));

      await w.watch.pause();
      expect(w.sent.last['c'], 'pause');
      expect(w.sent.last['r'], 0);
      expect(w.sent.last['p'], 12000);
      expect(w.state.anchor!.playing, isFalse);
      expect(w.sent.last['_reliable'], isTrue);

      await w.watch.seek(const Duration(minutes: 3));
      expect(w.sent.last['c'], 'seek');
      expect(w.sent.last['p'], 180000);
      expect(w.sent.last['r'], 0, reason: 'a seek keeps pausing');
      expect(w.player.calls.last, 'seek:180000');

      await w.watch.play();
      expect(w.sent.last['c'], 'play');
      expect(w.sent.last['r'], 1);
      expect(w.sent.last['p'], 180000);
      expect(w.state.anchor!.playing, isTrue);
    });

    watchTest('a seek past the end stops at the end', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      await w.watch.seek(const Duration(hours: 5));
      expect(w.sent.last['p'], const Duration(minutes: 10).inMilliseconds);
      await w.watch.seek(const Duration(seconds: -4));
      expect(w.sent.last['p'], 0);
    });

    watchTest('repeats where it is every few seconds', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      w.player.advance(const Duration(seconds: 3));
      final before = w.sent.length;

      await w.elapse(const Duration(seconds: 3));
      expect(w.sent.length, before, reason: 'not yet');

      await w.elapse(const Duration(seconds: 2));
      expect(w.sent.length, before + 1);
      final beat = w.sent.last;
      expect(beat['k'], 'y');
      expect(beat['c'], 'beat');
      expect(beat['p'], 3000);
      expect(beat['r'], 1);
      expect(beat['_reliable'], isFalse);

      await w.elapse(const Duration(seconds: 4));
      expect(w.sent.length, before + 2);
    });

    watchTest('says it all again when somebody joins', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl, title: 'Movie night');
      await tester.pump();
      await tester.pump();
      w.player.advance(const Duration(seconds: 90));
      final before = w.sent.length;

      await w.addPerson('user-4', 'Dan');
      expect(w.sent.length, before + 1);
      final again = w.sent.last;
      expect(again['k'], 's');
      expect(again['id'], 'show-1');
      expect(again['u'], videoUrl);
      expect(again['t'], 'Movie night');
      expect(again['p'], 90000);
      expect(again['r'], 1);

      // Two people joining at once do not flood the room.
      await w.addPerson('user-5', 'Eve');
      expect(w.sent.length, before + 1);
    });

    watchTest('answers somebody who asks what is on', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      final before = w.sent.length;

      await w.receive('user-3', encodeWatchAsk());
      expect(w.sent.length, before + 1);
      expect(w.sent.last['k'], 's');
      // Asking again straight away does not repeat it.
      await w.receive('user-2', encodeWatchAsk());
      expect(w.sent.length, before + 1);
    });

    watchTest('ending tells everyone and stops the player', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      final player = w.player;

      await w.watch.end();
      await tester.pump();

      expect(w.sent.last['k'], 'e');
      expect(w.sent.last['id'], 'show-1');
      expect(w.state.active, isFalse);
      expect(w.state.notice, WatchNotice.none);
      expect(player.disposed, isTrue);
      // Nothing is repeated afterwards.
      final count = w.sent.length;
      await w.elapse(const Duration(seconds: 10));
      expect(w.sent.length, count);
    });

    watchTest('switching to another link starts a new showing', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      final first = w.player;

      await w.watch.start(songUrl, title: 'Road trip');
      await tester.pump();
      await tester.pump();

      expect(first.disposed, isTrue);
      expect(w.players.length, 2);
      expect(w.state.sessionId, 'show-2');
      expect(w.state.link!.isAudio, isTrue);
      expect(w.state.title, 'Road trip');
      final start = w.sent.where((p) => p['k'] == 's').last;
      expect(start['id'], 'show-2');
      expect(start['u'], songUrl);
    });

    watchTest('at the end of the video everyone is paused there', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      w.player.drift(const Duration(minutes: 10));
      await w.player.pause();

      await w.elapse(const Duration(seconds: 1));

      expect(w.sent.last['c'], 'pause');
      expect(w.sent.last['p'], const Duration(minutes: 10).inMilliseconds);
      expect(w.sent.last['r'], 0);
      expect(w.state.anchor!.playing, isFalse);
    });

    watchTest('guests can not play, pause or seek for the room', (
      tester,
    ) async {
      final w = await guestWorld(tester);
      final before = w.player.calls.length;
      await w.watch.play();
      await w.watch.pause();
      await w.watch.seek(const Duration(minutes: 2));
      await w.watch.end();
      expect(w.sent, isEmpty);
      expect(w.player.calls.length, before);
      expect(w.state.active, isTrue);
    });

    watchTest('two people who start at once: the lower user id hosts', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      w.remotes = const [
        VoiceCallParticipant(userId: 'user-0', name: 'Zed'),
        VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
      ];
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      final mine = w.player;

      // user-2 is above user-1: ignored, this device stays the host.
      await w.receiveStart('user-2', songUrl, id: 'theirs');
      expect(w.state.isHost, isTrue);
      expect(w.state.sessionId, 'show-1');

      // user-0 is below user-1: this device gives way.
      await w.receiveStart('user-0', songUrl, id: 'zed-1', title: 'Zed mix');
      expect(w.state.isHost, isFalse);
      expect(w.state.hostId, 'user-0');
      expect(w.state.sessionId, 'zed-1');
      expect(mine.disposed, isTrue);
      expect(w.players.length, 2);
      expect(w.player.opened!.text, songUrl);
    });
  });

  group('a guest', () {
    watchTest('loads the link and moves to where the host is', (tester) async {
      final w = await guestWorld(tester);

      expect(w.state.active, isTrue);
      expect(w.state.isHost, isFalse);
      expect(w.state.hostId, 'user-2');
      expect(w.state.hostName, 'Bart');
      expect(w.state.title, 'Movie night');
      expect(w.player.opened!.text, videoUrl);
      expect(w.player.calls, ['seek:30000', 'play']);
      // A guest says nothing.
      expect(w.sent, isEmpty);
    });

    watchTest('joining late with a paused host waits at their place', (
      tester,
    ) async {
      final w = await guestWorld(tester, playing: false);
      expect(w.player.calls, ['seek:30000']);
      expect(w.player.value.playing, isFalse);
    });

    watchTest('waits for the player to load before moving', (tester) async {
      final w = await guestWorld(
        tester,
        playerBuilder: () => FakeWatchPlayer(autoReady: false),
      );
      expect(w.player.calls, isEmpty);
      await w.elapse(const Duration(seconds: 3));
      expect(w.player.calls, isEmpty);

      w.player.becomeReady();
      await tester.pump();
      // The host went on by three seconds meanwhile.
      expect(w.player.calls, ['seek:33000', 'play']);
    });

    watchTest('follows pause, play and seek', (tester) async {
      final w = await guestWorld(tester);
      w.player.calls.clear();

      await w.receiveSync(
        'user-2',
        cause: WatchCause.pause,
        positionMs: 45000,
        playing: false,
        seq: 3,
      );
      expect(w.player.calls, ['seek:45000', 'pause']);
      expect(w.player.value.playing, isFalse);
      expect(w.state.anchor!.playing, isFalse);

      w.player.calls.clear();
      await w.receiveSync(
        'user-2',
        cause: WatchCause.play,
        positionMs: 45000,
        playing: true,
        seq: 4,
      );
      expect(w.player.calls, ['play'], reason: 'already at the right place');

      w.player.calls.clear();
      await w.receiveSync(
        'user-2',
        cause: WatchCause.seek,
        positionMs: 300000,
        playing: true,
        seq: 5,
      );
      expect(w.player.calls, ['seek:300000']);
    });

    watchTest('adds the time a message was on its way', (tester) async {
      final w = await guestWorld(tester);
      w.player.calls.clear();
      await w.receiveSync(
        'user-2',
        positionMs: 80000,
        seq: 2,
        sentAt: w.now.subtract(const Duration(milliseconds: 600)),
      );
      expect(w.player.calls, ['seek:80600']);
    });

    watchTest('leaves a gap of up to a second alone', (tester) async {
      final w = await guestWorld(tester);
      w.player.calls.clear();

      // 0.9 s behind the host: no seek.
      w.player.drift(const Duration(milliseconds: 30000 + 600));
      await w.receiveSync('user-2', positionMs: 31500, seq: 2);
      expect(seeks(w.player), isEmpty);

      // More than a second behind: corrected.
      w.player.drift(const Duration(milliseconds: 40000));
      await w.receiveSync('user-2', positionMs: 41500, seq: 3);
      expect(seeks(w.player), ['seek:41500']);
    });

    watchTest('corrects drift between messages too', (tester) async {
      final w = await guestWorld(tester);
      w.player.calls.clear();

      // The player keeps up for a second: nothing to do.
      w.player.advance(const Duration(seconds: 1));
      await w.elapse(const Duration(seconds: 1));
      expect(seeks(w.player), isEmpty);

      // It then stalls for two seconds (the player stands still).
      await w.elapse(const Duration(seconds: 2));
      expect(seeks(w.player), isNotEmpty);
      expect(seeks(w.player).last, 'seek:33000');
    });

    watchTest('ignores a message older than one it already took', (
      tester,
    ) async {
      final w = await guestWorld(tester);
      await w.receiveSync(
        'user-2',
        cause: WatchCause.pause,
        positionMs: 45000,
        playing: false,
        seq: 5,
      );
      expect(w.state.anchor!.playing, isFalse);

      // A late heartbeat from before the pause.
      await w.receiveSync('user-2', positionMs: 44000, playing: true, seq: 4);
      expect(w.state.anchor!.playing, isFalse);
      expect(w.state.anchor!.positionMs, 45000);
      expect(w.player.value.playing, isFalse);

      // The same number again is not new either.
      await w.receiveSync('user-2', positionMs: 1000, playing: true, seq: 5);
      expect(w.state.anchor!.positionMs, 45000);
    });

    watchTest('only believes the host', (tester) async {
      final w = await guestWorld(tester);
      w.player.calls.clear();

      await w.receiveSync('user-3', positionMs: 5000, playing: false, seq: 2);
      await w.receive('user-3', encodeWatchEnd(id: 'remote-1', seq: 9));
      await w.receiveStart('user-3', songUrl, id: 'other');
      await w.receive('user-3', encodeWatchAsk());

      expect(w.state.active, isTrue);
      expect(w.state.hostId, 'user-2');
      expect(w.state.sessionId, 'remote-1');
      expect(w.state.link!.text, videoUrl);
      expect(w.player.calls, isEmpty);
      expect(w.sent, isEmpty);
    });

    watchTest('ignores packets of a showing it is not in', (tester) async {
      final w = await guestWorld(tester);
      w.player.calls.clear();
      await w.receiveSync(
        'user-2',
        id: 'old-one',
        positionMs: 5000,
        playing: false,
        seq: 7,
      );
      await w.receive('user-2', encodeWatchEnd(id: 'old-one', seq: 8));
      expect(w.state.active, isTrue);
      expect(w.state.anchor!.positionMs, 30000);
      expect(w.player.calls, isEmpty);
    });

    watchTest('ignores people who are not in the call', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.receiveStart('user-99', videoUrl);
      expect(w.state.active, isFalse);
      expect(w.players, isEmpty);
    });

    watchTest('ignores other topics and bad packets', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);

      await w.receive(
        'user-2',
        encodeWatchStart(
          id: 'x',
          link: parseWatchLink(videoUrl).link!,
          title: '',
          positionMs: 0,
          playing: false,
          seq: 1,
          sentAt: w.now,
        ),
        topic: 'wecord.caption',
      );
      await w.receive('user-2', utf8.encode('{"v":1,"k":"s"}'));
      await w.receive('user-2', utf8.encode('garbage'));
      await w.receive(
        'user-2',
        utf8.encode(
          jsonEncode({
            'v': 1,
            'k': 's',
            'id': 'x',
            'u': 'http://media.example.com/a.mp4',
            't': '',
            'p': 0,
            'r': 0,
            'n': 1,
            'ts': 1,
          }),
        ),
      );
      expect(w.state.active, isFalse);
    });

    watchTest('does not let one person flood it', (tester) async {
      final w = await guestWorld(tester);
      // The start counted as one; the limit is 20 in five seconds.
      for (var seq = 2; seq <= 40; seq++) {
        w.call.receiveData(
          'user-2',
          watchTopic,
          encodeWatchSync(
            id: 'remote-1',
            cause: WatchCause.beat,
            positionMs: seq * 1000,
            playing: false,
            seq: seq,
            sentAt: w.now,
          ),
        );
      }
      await tester.pump();
      await tester.pump();
      expect(w.state.anchor!.positionMs, 20000);

      await w.elapse(const Duration(seconds: 6));
      await w.receiveSync('user-2', positionMs: 99000, playing: false, seq: 41);
      expect(w.state.anchor!.positionMs, 99000);
    });

    watchTest('asks what is on when it hears a host it knows nothing about', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);

      await w.receiveSync('user-2', seq: 5);
      expect(w.sent.length, 1);
      expect(w.sent.single['k'], 'a');

      // Not again straight away.
      await w.receiveSync('user-2', seq: 6);
      expect(w.sent.length, 1);

      await w.elapse(const Duration(seconds: 6));
      await w.receiveSync('user-2', seq: 7);
      expect(w.sent.length, 2);

      // The host answers with the start and it takes over.
      await w.receiveStart('user-2', videoUrl, id: 'remote-1', seq: 8);
      expect(w.state.active, isTrue);
    });

    watchTest('a new link from the host replaces the old one', (tester) async {
      final w = await guestWorld(tester);
      final first = w.player;
      await w.receiveStart(
        'user-2',
        songUrl,
        id: 'remote-2',
        title: 'Road trip',
        seq: 1,
      );
      expect(first.disposed, isTrue);
      expect(w.players.length, 2);
      expect(w.state.sessionId, 'remote-2');
      expect(w.state.link!.isAudio, isTrue);
      expect(w.player.opened!.text, songUrl);
    });

    watchTest('the same start said again does not reload the player', (
      tester,
    ) async {
      final w = await guestWorld(tester);
      await w.receiveStart(
        'user-2',
        videoUrl,
        id: 'remote-1',
        positionMs: 50000,
        playing: true,
        seq: 2,
      );
      expect(w.players.length, 1);
      expect(w.player.disposed, isFalse);
      expect(w.state.anchor!.positionMs, 50000);
      expect(w.player.calls.last, 'seek:50000');
    });

    watchTest('a web page link is shown but not played', (tester) async {
      final w = await guestWorld(tester, url: pageUrl);
      expect(w.state.active, isTrue);
      expect(w.state.synced, isFalse);
      expect(w.players, isEmpty);
    });
  });

  group('when it ends', () {
    watchTest('the host ends it', (tester) async {
      final w = await guestWorld(tester);
      final player = w.player;
      await w.receive('user-2', encodeWatchEnd(id: 'remote-1', seq: 9));
      await tester.pump();

      expect(w.state.active, isFalse);
      expect(w.state.notice, WatchNotice.hostEnded);
      expect(w.state.noticeName, 'Bart');
      expect(player.disposed, isTrue);

      // The notice goes away by itself.
      await w.elapse(const Duration(seconds: 9));
      expect(w.state.notice, WatchNotice.none);
    });

    watchTest('the host leaves the call', (tester) async {
      final w = await guestWorld(tester);
      final player = w.player;
      await w.removePerson('user-2');

      expect(w.state.active, isFalse);
      expect(w.state.notice, WatchNotice.hostLeft);
      expect(w.state.noticeName, 'Bart');
      expect(player.disposed, isTrue);

      // Later messages from the one who left change nothing.
      await w.receiveSync('user-2', positionMs: 1000, seq: 50);
      expect(w.state.active, isFalse);
    });

    watchTest('somebody else leaving changes nothing', (tester) async {
      final w = await guestWorld(tester);
      await w.removePerson('user-3');
      expect(w.state.active, isTrue);
      expect(w.player.disposed, isFalse);
    });

    watchTest('the host is not heard from for a while', (tester) async {
      final w = await guestWorld(tester);
      await w.elapse(const Duration(seconds: 15));
      expect(w.state.active, isTrue);
      await w.elapse(const Duration(seconds: 7));
      expect(w.state.active, isFalse);
      expect(w.state.notice, WatchNotice.hostLeft);
    });

    watchTest('a heartbeat keeps it going', (tester) async {
      final w = await guestWorld(tester);
      var seq = 2;
      for (var i = 0; i < 6; i++) {
        await w.elapse(const Duration(seconds: 4));
        await w.receiveSync('user-2', positionMs: 30000 + i * 4000, seq: seq++);
      }
      expect(w.state.active, isTrue);
    });

    watchTest('this person leaves the call', (tester) async {
      final w = await guestWorld(tester);
      final player = w.player;
      await w.container.read(voiceSessionProvider.notifier).leave();
      await tester.pump();
      expect(w.state.active, isFalse);
      expect(w.state.notice, WatchNotice.none);
      expect(player.disposed, isTrue);
    });

    watchTest('the host leaving the call stops the showing here too', (
      tester,
    ) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      await tester.pump();
      final player = w.player;
      await w.container.read(voiceSessionProvider.notifier).leave();
      await tester.pump();
      expect(w.state.active, isFalse);
      expect(player.disposed, isTrue);
      final count = w.sent.length;
      await w.elapse(const Duration(seconds: 10));
      expect(w.sent.length, count, reason: 'no heartbeat once out of the call');
    });
  });

  group('my own choices', () {
    watchTest('muting only touches my own sound', (tester) async {
      final w = await guestWorld(tester);
      await w.watch.setMuted(true);
      expect(w.state.muted, isTrue);
      expect(w.player.muted, isTrue);
      expect(w.sent, isEmpty);
      await w.watch.setMuted(false);
      expect(w.player.muted, isFalse);
    });

    watchTest('a new player starts muted when I muted', (tester) async {
      final w = await guestWorld(tester);
      await w.watch.setMuted(true);
      await w.receiveStart('user-2', songUrl, id: 'remote-2', seq: 1);
      expect(w.players.length, 2);
      expect(w.player.muted, isTrue);
    });

    watchTest('hiding the picture keeps the sound going', (tester) async {
      final w = await guestWorld(tester);
      w.watch.setHidden(true);
      expect(w.state.hidden, isTrue);
      expect(w.player.disposed, isFalse);
      w.watch.setHidden(false);
      expect(w.state.hidden, isFalse);
    });

    watchTest('stopping on my side leaves everyone else alone', (tester) async {
      final w = await guestWorld(tester);
      final player = w.player;
      w.watch.leaveMine();

      expect(w.state.dismissed, isTrue);
      expect(w.state.active, isTrue);
      expect(player.disposed, isTrue);
      expect(w.sent, isEmpty);

      // The host's messages are still followed, without a player.
      await w.receiveSync('user-2', positionMs: 70000, seq: 2);
      expect(w.state.anchor!.positionMs, 70000);
      expect(w.players.length, 1);

      // A new link does not bring the picture back by itself.
      await w.receiveStart('user-2', songUrl, id: 'remote-2', seq: 1);
      expect(w.state.dismissed, isTrue);
      expect(w.players.length, 1);
    });

    watchTest('watching again joins where the host is', (tester) async {
      final w = await guestWorld(tester);
      w.watch.leaveMine();
      await w.receiveSync('user-2', positionMs: 70000, seq: 2);

      w.watch.rejoin();
      await tester.pump();

      expect(w.state.dismissed, isFalse);
      expect(w.players.length, 2);
      expect(w.player.calls, ['seek:70000', 'play']);
    });

    watchTest('the host can not stop on their own side', (tester) async {
      final w = WatchWorld();
      currentWatchWorld = w;
      await w.join(tester);
      await w.watch.start(videoUrl);
      await tester.pump();
      w.watch.leaveMine();
      expect(w.state.dismissed, isFalse);
      expect(w.players.single.disposed, isFalse);
    });

    watchTest('a browser that wants a tap shows a tap to start', (
      tester,
    ) async {
      final w = await guestWorld(
        tester,
        playerBuilder: () => FakeWatchPlayer(refusePlay: true),
      );
      expect(w.state.needsTap, isFalse);
      await w.elapse(const Duration(seconds: 2));
      expect(w.state.needsTap, isTrue);
      expect(w.player.value.playing, isFalse);

      w.player.refusePlay = false;
      await w.watch.tapToPlay();
      await tester.pump();
      expect(w.player.value.playing, isTrue);
      expect(w.state.needsTap, isFalse);
      await w.elapse(const Duration(seconds: 3));
      expect(w.state.needsTap, isFalse);
    });

    watchTest('a link that fails to load is reported by the player', (
      tester,
    ) async {
      final w = await guestWorld(
        tester,
        playerBuilder: () =>
            FakeWatchPlayer(failWith: WatchMediaFailure.cannotPlay),
      );
      expect(w.player.value.failed, isTrue);
      expect(w.player.calls, isEmpty);
      // The showing goes on for everybody else.
      expect(w.state.active, isTrue);
    });
  });
}
