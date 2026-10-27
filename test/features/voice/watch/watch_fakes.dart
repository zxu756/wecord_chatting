import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/watch/watch_controller.dart';
import 'package:wecord/features/voice/watch/watch_player.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/shared/models/profile.dart';

import '../voice_fakes.dart';

/// A player that plays nothing: the test moves its clock.
class FakeWatchPlayer extends ChangeNotifier implements WatchPlayer {
  FakeWatchPlayer({
    this.length = const Duration(minutes: 10),
    this.hasSurface = true,
    this.remoteControl = true,
    this.surfaceInteractive = false,
  });

  final Duration length;

  @override
  final bool hasSurface;

  @override
  final bool remoteControl;

  @override
  final bool surfaceInteractive;

  Duration at = Duration.zero;
  var playing = false;
  var buffering = false;
  var ended = false;
  var muted = false;
  var closed = false;
  var failToPlay = false;
  final seeks = <Duration>[];
  var plays = 0;
  var pauses = 0;

  @override
  Duration get position => at;

  @override
  Duration? get duration => length;

  @override
  bool get isPlaying => playing;

  @override
  bool get isBuffering => buffering;

  @override
  bool get hasEnded => ended;

  @override
  Future<void> play() async {
    if (failToPlay) {
      throw Exception('blocked');
    }
    plays++;
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    at = position;
    notifyListeners();
  }

  @override
  Future<void> setMuted(bool value) async => muted = value;

  @override
  Widget buildSurface(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF223344),
      child: Center(
        child: Icon(Icons.play_circle_outline, size: 48, color: Colors.white),
      ),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// The data a fake call was asked to publish on the watch topic.
List<Map<String, Object?>> watchSent(FakeVoiceCall call) => [
  for (final message in call.published)
    if (message.topic == watchTopic)
      jsonDecode(utf8.decode(message.data)) as Map<String, Object?>,
];

const chatFilePath = 'conv-lounge/1700-film.mp4';

WatchFileSource sampleFile({bool audio = false}) => WatchFileSource(
  path: audio ? 'conv-lounge/1701-song.mp3' : chatFilePath,
  name: audio ? 'song.mp3' : 'film.mp4',
  mimeType: audio ? 'audio/mpeg' : 'video/mp4',
  size: 4 * 1024 * 1024,
  isAudio: audio,
);

class WatchWorld {
  WatchWorld({
    this.host = true,
    this.extraOverrides = const [],
    this.blocked = const [],
    bool ownContainer = true,
  }) {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    connector.prepare = (call) {
      call.localCaptionsHost = host;
      call.remotes = remotes;
    };
    ownsContainer = ownContainer;
    if (ownContainer) {
      adopt(ProviderContainer(overrides: overrides));
    }
  }

  final bool host;
  final List<Override> extraOverrides;
  final List<Profile> blocked;
  late final bool ownsContainer;

  late final FakeVoiceRepository repository;
  late final FakeVoiceCallConnector connector;
  late ProviderContainer container;
  late WidgetTester tester;
  var remotes = const [
    VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
    VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
  ];

  /// Every player the factory opened, newest last.
  final players = <FakeWatchPlayer>[];
  final opened = <WatchSource>[];
  Object? openError;
  bool noPlayer = false;
  var now = DateTime(2026, 10, 28, 20);
  var sessionCounter = 0;

  List<Override> get overrides => [
    voiceRepositoryProvider.overrideWithValue(repository),
    voiceCallConnectorProvider.overrideWithValue(connector),
    authStateProvider.overrideWith(
      (ref) => Stream.value(const AuthUser(id: 'user-1')),
    ),
    watchClockProvider.overrideWithValue(() => now),
    watchSessionIdProvider.overrideWithValue(
      () => 'session${(++sessionCounter).toString().padLeft(4, '0')}',
    ),
    blockedUsersProvider.overrideWith((ref) async => blocked),
    watchPlayerFactoryProvider.overrideWithValue((
      source, {
      String? conversationId,
    }) async {
      opened.add(source);
      if (openError != null) {
        throw openError!;
      }
      if (noPlayer) {
        return null;
      }
      final player = FakeWatchPlayer(
        hasSurface: !source.isAudio,
        remoteControl: source is! WatchEmbedSource || source.remoteControl,
        surfaceInteractive: source is WatchEmbedSource && !source.remoteControl,
      );
      players.add(player);
      return player;
    }),
    ...extraOverrides,
  ];

  void adopt(ProviderContainer container) {
    this.container = container;
    container.listen(watchTogetherProvider, (previous, next) {});
    container.listen(voiceSessionProvider, (previous, next) {});
  }

  WatchTogetherController get watch =>
      container.read(watchTogetherProvider.notifier);
  WatchState get state => container.read(watchTogetherProvider);
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
    await tester.pump();
  }

  /// Someone else sends a watch packet.
  Future<void> receive(String userId, List<int> data) async {
    call.receiveData(userId, watchTopic, data);
    // The message crosses two streams before the controller sees it.
    await tester.pump();
    await tester.pump();
  }

  Future<void> receiveStart(
    String userId, {
    String sid = 'remote000001',
    WatchSource? source,
    String title = 'Film night',
    bool open = false,
    Duration position = Duration.zero,
    bool playing = false,
  }) {
    return receive(
      userId,
      encodeWatchStart(
        WatchStartPacket(
          sessionId: sid,
          source: source ?? sampleFile(),
          title: title,
          controlOpen: open,
          position: position,
          playing: playing,
        ),
      ),
    );
  }

  Future<void> receiveState(
    String userId, {
    String sid = 'remote000001',
    Duration position = Duration.zero,
    bool playing = false,
    bool? open,
  }) {
    return receive(
      userId,
      encodeWatchState(
        WatchStatePacket(
          sessionId: sid,
          position: position,
          playing: playing,
          controlOpen: open,
        ),
      ),
    );
  }

  /// [userId] is now a moderator in the call.
  void makeModerator(String userId) {
    call.remotes = [
      for (final remote in call.remotes)
        VoiceCallParticipant(
          userId: remote.userId,
          name: remote.name,
          captionsHost: remote.userId == userId,
        ),
    ];
    call.update();
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

Profile blockedProfile(String id) => Profile(
  id: id,
  username: 'blocked',
  displayName: 'Blocked',
  bio: '',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
