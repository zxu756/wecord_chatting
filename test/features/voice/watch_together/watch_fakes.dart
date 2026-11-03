import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';
import 'package:wecord/features/voice/watch_together/watch_together_controller.dart';
import 'package:wecord/features/voice/watch_together/watch_together_panel.dart';

import '../voice_fakes.dart';

/// A player that plays nothing; the test moves its clock.
class FakeWatchPlayer extends ChangeNotifier implements WatchMediaPlayer {
  FakeWatchPlayer({
    this.autoReady = true,
    this.failWith,
    this.duration = const Duration(minutes: 10),
    this.refusePlay = false,
    this.picture,
  });

  /// What the picture shows; a plain box by default.
  final Widget Function()? picture;

  /// The player is ready as soon as it is opened; otherwise the test calls
  /// [becomeReady].
  final bool autoReady;

  /// What [open] fails with, when set.
  final WatchMediaFailure? failWith;
  final Duration duration;

  /// [play] throws, as a browser does that wants a tap first.
  bool refusePlay;

  WatchMediaValue _value = const WatchMediaValue();
  WatchLink? opened;
  var disposed = false;
  var muted = false;

  /// What was asked of the player, in order: `play`, `pause`, `seek:<ms>`.
  final calls = <String>[];

  @override
  WatchMediaValue get value => _value;

  void _set(WatchMediaValue value) {
    if (disposed) {
      return;
    }
    _value = value;
    notifyListeners();
  }

  @override
  Future<void> open(WatchLink link) async {
    opened = link;
    _set(const WatchMediaValue(phase: WatchMediaPhase.loading));
    final failure = failWith;
    if (failure != null) {
      _set(_value.copyWith(phase: WatchMediaPhase.failed, failure: failure));
      return;
    }
    if (autoReady) {
      becomeReady();
    }
  }

  void becomeReady() {
    _set(
      _value.copyWith(
        phase: WatchMediaPhase.ready,
        duration: duration,
        aspectRatio: 16 / 9,
      ),
    );
  }

  /// Plays on by [by], as time passes.
  void advance(Duration by) {
    if (_value.playing) {
      _set(_value.copyWith(position: _value.position + by));
    }
  }

  /// The position moves without the player being asked (a stall, a drift).
  void drift(Duration to) {
    _set(_value.copyWith(position: to));
  }

  @override
  Future<void> play() async {
    calls.add('play');
    if (refusePlay) {
      throw StateError('NotAllowedError');
    }
    _set(_value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _set(_value.copyWith(playing: false));
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    _set(_value.copyWith(position: position));
  }

  @override
  Future<void> setMuted(bool muted) async {
    this.muted = muted;
    calls.add('mute:$muted');
  }

  @override
  Widget buildView(BuildContext context) =>
      picture?.call() ??
      const ColoredBox(key: ValueKey('fake-watch-picture'), color: Colors.teal);

  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }
}

/// A call with the watching controller around it.
class WatchWorld {
  WatchWorld({
    this.localId = 'user-1',
    this.extraOverrides = const [],
    this.playerBuilder,
    bool ownContainer = true,
  }) {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector(localUserId: localId);
    connector.prepare = (call) => call.remotes = remotes;
    if (ownContainer) {
      adopt(ProviderContainer(overrides: overrides));
    }
    ownsContainer = ownContainer;
  }

  final String localId;
  final List<Override> extraOverrides;

  /// Makes the next player; a fake that is ready at once by default.
  final FakeWatchPlayer Function()? playerBuilder;
  late final bool ownsContainer;

  var remotes = const [
    VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
    VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
  ];

  late final FakeVoiceRepository repository;
  late final FakeVoiceCallConnector connector;
  late ProviderContainer container;
  late WidgetTester tester;
  var now = DateTime(2026, 11, 4, 20);
  var _ids = 0;

  /// Every player the controller made, oldest first.
  final players = <FakeWatchPlayer>[];

  List<Override> get overrides => [
    voiceRepositoryProvider.overrideWithValue(repository),
    voiceCallConnectorProvider.overrideWithValue(connector),
    authStateProvider.overrideWith(
      (ref) => Stream.value(AuthUser(id: localId)),
    ),
    watchClockProvider.overrideWithValue(() => now),
    watchIdProvider.overrideWithValue(() => 'show-${++_ids}'),
    watchPlayerFactoryProvider.overrideWithValue(() {
      final player = playerBuilder?.call() ?? FakeWatchPlayer();
      players.add(player);
      return player;
    }),
    watchLinkOpenerProvider.overrideWithValue((context, uri) async {
      openedLinks.add(uri);
    }),
    ...extraOverrides,
  ];

  /// Links the panel asked to open outside the player.
  final openedLinks = <Uri>[];

  void adopt(ProviderContainer container) {
    this.container = container;
    container.listen(watchTogetherProvider, (previous, next) {});
    container.listen(voiceSessionProvider, (previous, next) {});
  }

  WatchTogetherController get watch =>
      container.read(watchTogetherProvider.notifier);
  WatchTogetherState get state => container.read(watchTogetherProvider);
  FakeVoiceCall get call => connector.last;
  FakeWatchPlayer get player => players.last;

  Future<void> join(WidgetTester tester) async {
    this.tester = tester;
    await container
        .read(voiceSessionProvider.notifier)
        .join(
          circleId: 'circle-1',
          channelId: 'ch-lounge',
          conversationId: 'conv-lounge',
          channelName: 'Lounge',
        );
    await tester.pump();
  }

  /// Everything the current user published on the watch topic, decoded.
  List<Map<String, Object?>> get sent => [
    for (final message in call.published)
      if (message.topic == watchTopic)
        {
          ...jsonDecode(utf8.decode(message.data)) as Map<String, Object?>,
          '_reliable': message.reliable,
        },
  ];

  /// Someone else sends a data message on the watch topic.
  Future<void> receive(
    String userId,
    List<int> data, {
    String topic = watchTopic,
  }) async {
    call.receiveData(userId, topic, data);
    // The message crosses two streams before the controller sees it.
    await tester.pump();
    await tester.pump();
  }

  /// [userId] starts watching [url].
  Future<void> receiveStart(
    String userId,
    String url, {
    String id = 'remote-1',
    String title = '',
    int positionMs = 0,
    bool playing = false,
    int seq = 1,
    DateTime? sentAt,
  }) {
    return receive(
      userId,
      encodeWatchStart(
        id: id,
        link: parseWatchLink(url).link!,
        title: title,
        positionMs: positionMs,
        playing: playing,
        seq: seq,
        sentAt: sentAt ?? now,
      ),
    );
  }

  Future<void> receiveSync(
    String userId, {
    String id = 'remote-1',
    WatchCause cause = WatchCause.beat,
    int positionMs = 0,
    bool playing = true,
    required int seq,
    DateTime? sentAt,
  }) {
    return receive(
      userId,
      encodeWatchSync(
        id: id,
        cause: cause,
        positionMs: positionMs,
        playing: playing,
        seq: seq,
        sentAt: sentAt ?? now,
      ),
    );
  }

  /// Someone joins the call.
  Future<void> addPerson(String userId, String name) async {
    call.remotes = [
      ...call.remotes,
      VoiceCallParticipant(userId: userId, name: name),
    ];
    call.update();
    await tester.pump();
    await tester.pump();
  }

  /// Someone leaves the call.
  Future<void> removePerson(String userId) async {
    call.remotes = [
      for (final remote in call.remotes)
        if (remote.userId != userId) remote,
    ];
    call.update();
    await tester.pump();
    await tester.pump();
  }

  /// Moves the clock and lets the timers run for that long.
  Future<void> elapse(Duration by) async {
    var left = by;
    while (left > Duration.zero) {
      final step = left < const Duration(seconds: 1)
          ? left
          : const Duration(seconds: 1);
      now = now.add(step);
      await tester.pump(step);
      left -= step;
    }
  }

  Future<void> shutdown(WidgetTester tester) async {
    await container.read(voiceSessionProvider.notifier).leave();
    await tester.pump();
    if (ownsContainer) {
      container.dispose();
    }
    await tester.pump();
  }
}

WatchWorld? currentWatchWorld;

void watchTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    currentWatchWorld = null;
    await body(tester);
    await currentWatchWorld?.shutdown(tester);
  });
}

const videoUrl = 'https://media.example.com/movies/night.mp4';
const songUrl = 'https://media.example.com/music/song.mp3';
const hlsUrl = 'https://media.example.com/live/stream.m3u8';
const pageUrl = 'https://www.youtube.com/watch?v=abc123';
