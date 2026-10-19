import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

import '../../voice_input/fake_voice_recognizer.dart';
import '../voice_fakes.dart';

/// The data a fake call was asked to publish on the caption topic.
List<Map<String, Object?>> sent(FakeVoiceCall call) => [
  for (final message in call.published)
    if (message.topic == captionTopic)
      {
        ...jsonDecode(utf8.decode(message.data)) as Map<String, Object?>,
        '_reliable': message.reliable,
      },
];

class CaptionsWorld {
  /// With [ownContainer] false the test pumps a widget tree with
  /// [overrides] instead and hands the tree's container to [adopt].
  CaptionsWorld({
    this.host = true,
    FakeVoiceRecognizer? recognizer,
    this.extraOverrides = const [],
    bool ownContainer = true,
  }) : recognizer = recognizer ?? FakeVoiceRecognizer() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    connector.prepare = (call) {
      call.localCaptionsHost = host;
      call.remotes = remotes;
    };
    currentCaptionsWorld = this;
    ownsContainer = ownContainer;
    if (ownContainer) {
      adopt(ProviderContainer(overrides: overrides));
    }
  }

  final List<Override> extraOverrides;
  late final bool ownsContainer;

  List<Override> get overrides => [
    voiceRepositoryProvider.overrideWithValue(repository),
    voiceCallConnectorProvider.overrideWithValue(connector),
    authStateProvider.overrideWith(
      (ref) => Stream.value(const AuthUser(id: 'user-1')),
    ),
    voiceRecognizerProvider.overrideWithValue(recognizer),
    voiceInputStoreProvider.overrideWithValue(InMemoryVoiceInputStore()),
    captionClockProvider.overrideWithValue(() => now),
    ...extraOverrides,
  ];

  void adopt(ProviderContainer container) {
    this.container = container;
    container.listen(captionsProvider, (previous, next) {});
    container.listen(voiceSessionProvider, (previous, next) {});
  }

  final bool host;
  final remotes = const [
    VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
    VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
  ];
  final FakeVoiceRecognizer recognizer;
  late final FakeVoiceRepository repository;
  late final FakeVoiceCallConnector connector;
  late ProviderContainer container;
  var now = DateTime(2026, 10, 19, 12);

  CaptionsController get captions => container.read(captionsProvider.notifier);
  CaptionsState get state => container.read(captionsProvider);
  FakeVoiceCall get call => connector.last;

  late WidgetTester tester;

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

  /// Someone else sends a caption message.
  Future<void> receive(
    String userId,
    List<int> data, {
    String topic = captionTopic,
  }) async {
    call.receiveData(userId, topic, data);
    // The message crosses two streams before the controller sees it.
    await tester.pump();
    await tester.pump();
  }

  /// [userId] starts listening as someone who may turn captions on.
  void makeHost(String userId) {
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

  /// Leaves the call (which stops its timers) and drops the providers.
  Future<void> shutdown(WidgetTester tester) async {
    await container.read(voiceSessionProvider.notifier).leave();
    await tester.pump();
    if (ownsContainer) {
      container.dispose();
    }
    await tester.pump();
  }
}

CaptionsWorld? currentCaptionsWorld;

void captionsTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    currentCaptionsWorld = null;
    await body(tester);
    await currentCaptionsWorld?.shutdown(tester);
  });
}
