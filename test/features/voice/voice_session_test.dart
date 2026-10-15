import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/models/voice.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRepository repository;
  late FakeVoiceCallConnector connector;
  late VoiceSessionController controller;
  late List<String> changedCircles;

  void setUpController({VoiceSettings settings = const VoiceSettings()}) {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    changedCircles = [];
    controller = VoiceSessionController(
      repository: repository,
      connector: connector,
      settings: settings,
      onMembersChanged: (session) =>
          changedCircles.add(session.circleId ?? 'call'),
    );
  }

  Future<void> joinLounge() {
    return controller.join(
      circleId: 'circle-1',
      channelId: 'ch-lounge',
      conversationId: 'conv-lounge',
      channelName: 'Lounge',
    );
  }

  testWidgets('joining connects, marks the server state and heartbeats', (
    tester,
  ) async {
    setUpController();

    await joinLounge();

    final session = controller.state!;
    expect(session.isConnected, isTrue);
    expect(session.channelName, 'Lounge');
    expect(session.conversationId, 'conv-lounge');
    expect(session.selfMute, isFalse);
    expect(session.participants.single.userId, 'user-1');
    expect(repository.tokenRequests, ['ch-lounge']);
    expect(repository.joined, ['ch-lounge']);
    expect(connector.last.microphone, isTrue);
    expect(changedCircles, ['circle-1']);

    await tester.pump(voiceHeartbeatInterval);
    expect(repository.updates, hasLength(1));
    await tester.pump(voiceHeartbeatInterval);
    expect(repository.updates, hasLength(2));

    await controller.leave();
    expect(controller.state, isNull);
    expect(connector.last.disconnects, 1);
    expect(repository.leaves, 1);
    await tester.pump(voiceHeartbeatInterval * 2);
    expect(repository.updates, hasLength(2));
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('an unconfigured voice service leaves no session', (
    tester,
  ) async {
    setUpController();
    repository.tokenError = const VoiceNotConfiguredException();

    await expectLater(
      joinLounge(),
      throwsA(isA<VoiceNotConfiguredException>()),
    );

    expect(controller.state, isNull);
    expect(connector.calls, isEmpty);
    expect(repository.joined, isEmpty);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('a refused server join disconnects the call', (tester) async {
    setUpController();
    repository.joinError = const VoiceAccessDeniedException();

    await expectLater(joinLounge(), throwsA(isA<VoiceAccessDeniedException>()));

    expect(controller.state, isNull);
    expect(connector.last.disconnects, 1);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('switching channels leaves the previous one', (tester) async {
    setUpController();
    await joinLounge();
    final first = connector.last;

    await controller.join(
      circleId: 'circle-2',
      channelId: 'ch-stage',
      conversationId: 'conv-stage',
      channelName: 'Stage',
    );

    expect(first.disconnects, 1);
    expect(repository.leaves, 1);
    expect(controller.state!.channelId, 'ch-stage');
    expect(connector.calls, hasLength(2));
    // Joining the channel already joined does nothing.
    await controller.join(
      circleId: 'circle-2',
      channelId: 'ch-stage',
      conversationId: 'conv-stage',
      channelName: 'Stage',
    );
    expect(connector.calls, hasLength(2));
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('mute, deafen, camera and screen update call and server', (
    tester,
  ) async {
    setUpController();
    await joinLounge();
    final call = connector.last;

    await controller.toggleMute();
    expect(controller.state!.selfMute, isTrue);
    expect(call.microphone, isFalse);
    expect(repository.updates.last.mute, isTrue);

    // Deafening mutes too; undeafening restores the earlier mute.
    await controller.toggleMute();
    await controller.toggleDeafen();
    expect(controller.state!.selfDeaf, isTrue);
    expect(controller.state!.selfMute, isTrue);
    expect(call.remoteAudio, isFalse);
    expect(call.microphone, isFalse);
    await controller.toggleDeafen();
    expect(controller.state!.selfDeaf, isFalse);
    expect(controller.state!.selfMute, isFalse);
    expect(call.remoteAudio, isTrue);
    expect(call.microphone, isTrue);

    // Unmuting while deafened undeafens.
    await controller.toggleDeafen();
    await controller.toggleMute();
    expect(controller.state!.selfDeaf, isFalse);
    expect(controller.state!.selfMute, isFalse);
    expect(call.remoteAudio, isTrue);

    await controller.toggleCamera();
    expect(controller.state!.video, isTrue);
    expect(call.camera, isTrue);
    await controller.setScreenShare(
      const VoiceScreenSource(sourceId: 'screen-1'),
    );
    expect(controller.state!.screen, isTrue);
    expect(call.screenSource, 'screen-1');
    expect(repository.updates.last, (
      mute: false,
      deaf: false,
      video: true,
      screen: true,
    ));
    await controller.setScreenShare(null);
    expect(call.screen, isFalse);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('push to talk sends only while held', (tester) async {
    setUpController(
      settings: const VoiceSettings(inputMode: VoiceInputMode.pushToTalk),
    );
    await joinLounge();
    final call = connector.last;

    expect(controller.state!.pushToTalk, isTrue);
    // Not muted, just quiet until the key is held.
    expect(controller.state!.selfMute, isFalse);
    expect(call.microphone, isFalse);
    expect(call.audio.keepMicrophoneOpen, isTrue);

    await controller.setTransmitting(true);
    expect(controller.state!.transmitting, isTrue);
    expect(call.microphone, isTrue);
    await controller.setTransmitting(false);
    expect(call.microphone, isFalse);

    // Muted, holding the key sends nothing.
    await controller.toggleMute();
    await controller.setTransmitting(true);
    expect(call.microphone, isFalse);
    await controller.setTransmitting(false);
    // Unmuting doesn't open the microphone either.
    await controller.toggleMute();
    expect(call.microphone, isFalse);

    // Back to voice activity, the microphone opens.
    await controller.updateSettings(const VoiceSettings());
    expect(controller.state!.pushToTalk, isFalse);
    expect(call.microphone, isTrue);
    await controller.setTransmitting(false);
    expect(call.microphone, isTrue);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('processing and volumes reach the call', (tester) async {
    setUpController(
      settings: const VoiceSettings(
        noiseSuppression: false,
        userVolumes: {'user-2': 1.5},
      ),
    );
    await joinLounge();
    final call = connector.last;
    expect(call.audio.noiseSuppression, isFalse);
    expect(call.audio.echoCancellation, isTrue);
    expect(call.userVolumes, {'user-2': 1.5});

    await controller.updateSettings(
      const VoiceSettings(
        autoGainControl: false,
        userVolumes: {'user-2': 0.5, 'user-3': 2},
      ),
    );
    expect(call.audio.noiseSuppression, isTrue);
    expect(call.audio.autoGainControl, isFalse);
    expect(call.userVolumes, {'user-2': 0.5, 'user-3': 2});
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('a server mute silences the microphone until lifted', (
    tester,
  ) async {
    setUpController();
    await joinLounge();
    final call = connector.last;
    expect(call.microphone, isTrue);

    repository.ownState = const OwnVoiceState(
      channelId: 'ch-lounge',
      circleId: 'circle-1',
      serverMute: true,
    );
    repository.emitChange();
    await tester.pump();
    expect(controller.state!.serverMute, isTrue);
    expect(controller.state!.selfMute, isFalse);
    expect(call.microphone, isFalse);

    // Deafened by the server, nothing is heard either.
    repository.ownState = const OwnVoiceState(
      channelId: 'ch-lounge',
      circleId: 'circle-1',
      serverMute: true,
      serverDeaf: true,
    );
    repository.emitChange();
    await tester.pump();
    expect(call.remoteAudio, isFalse);

    repository.ownState = const OwnVoiceState(
      channelId: 'ch-lounge',
      circleId: 'circle-1',
    );
    repository.emitChange();
    await tester.pump();
    expect(controller.state!.serverMute, isFalse);
    expect(call.microphone, isTrue);
    expect(call.remoteAudio, isTrue);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('joining server muted keeps the microphone closed', (
    tester,
  ) async {
    setUpController();
    repository.tokenServerMute = true;
    await joinLounge();
    expect(controller.state!.serverMute, isTrue);
    expect(controller.state!.selfMute, isFalse);
    expect(connector.last.microphone, isFalse);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('a move reconnects to the new channel, keeping mute', (
    tester,
  ) async {
    setUpController();
    await joinLounge();
    final first = connector.last;
    await controller.toggleMute();

    repository.ownState = const OwnVoiceState(
      channelId: 'ch-stage',
      circleId: 'circle-1',
      conversationId: 'conv-stage',
      channelName: 'Stage',
    );
    repository.emitChange();
    await tester.pump();
    await tester.pump();

    expect(first.disconnects, 1);
    expect(repository.leaves, 0);
    expect(repository.tokenRequests, ['ch-lounge', 'ch-stage']);
    final session = controller.state!;
    expect(session.channelId, 'ch-stage');
    expect(session.conversationId, 'conv-stage');
    expect(session.channelName, 'Stage');
    expect(session.isConnected, isTrue);
    expect(session.selfMute, isTrue);
    expect(connector.last.microphone, isFalse);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('a moderator disconnect ends the session', (tester) async {
    setUpController();
    await joinLounge();

    repository.ownState = const OwnVoiceState(disconnected: true);
    repository.emitChange();
    await tester.pump();
    expect(controller.state, isNull);
    expect(connector.last.disconnects, 1);

    // The heartbeat doesn't rejoin after a disconnect either.
    await joinLounge();
    repository.updateResult = false;
    await tester.pump(voiceHeartbeatInterval);
    expect(controller.state, isNull);
    expect(repository.joined, ['ch-lounge', 'ch-lounge']);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('a dropped server state is joined again on the heartbeat', (
    tester,
  ) async {
    setUpController();
    await joinLounge();
    repository.updateResult = false;

    await tester.pump(voiceHeartbeatInterval);

    expect(repository.joined, ['ch-lounge', 'ch-lounge']);
    expect(controller.state, isNotNull);

    // Losing access ends the call.
    repository.joinError = const VoiceAccessDeniedException();
    await tester.pump(voiceHeartbeatInterval);
    expect(controller.state, isNull);
    expect(connector.last.disconnects, 1);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('the room dropping the call ends the session', (tester) async {
    setUpController();
    await joinLounge();

    connector.last.dropConnection();
    await tester.pump();

    expect(controller.state, isNull);
    expect(repository.leaves, 1);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  testWidgets('speaking and quality follow the call', (tester) async {
    setUpController();
    await joinLounge();
    final call = connector.last
      ..localSpeaking = true
      ..connectionQuality = VoiceConnectionQuality.poor;

    call.update();

    expect(controller.state!.participants.single.isSpeaking, isTrue);
    expect(controller.state!.quality, VoiceConnectionQuality.poor);
    // Stops the heartbeat before the test ends.
    await controller.leave();
  });

  group('direct calls', () {
    Future<void> callBob({bool video = false}) {
      return controller.startCall(
        conversationId: 'dm-bob',
        name: 'Bob',
        video: video,
      );
    }

    testWidgets('starting a call joins it, connects and heartbeats', (
      tester,
    ) async {
      setUpController();

      await callBob();

      final session = controller.state!;
      expect(session.isDirectCall, isTrue);
      expect(session.isConnected, isTrue);
      expect(session.callId, 'call-dm-bob');
      expect(session.conversationId, 'dm-bob');
      expect(session.channelName, 'Bob');
      expect(voiceSessionPath(session), '/chats/dm-bob');
      expect(repository.startedCalls, ['dm-bob']);
      expect(repository.callTokenRequests, ['call-dm-bob']);
      expect(repository.tokenRequests, isEmpty);
      expect(repository.joined, isEmpty);
      expect(changedCircles, ['call']);

      await tester.pump(voiceHeartbeatInterval);
      expect(repository.callUpdates, ['call-dm-bob']);

      await controller.leave();
      expect(controller.state, isNull);
      expect(repository.leftCalls, ['call-dm-bob']);
      expect(repository.leaves, 0);
    });

    testWidgets('a joined call is handed on so it rings by push', (
      tester,
    ) async {
      final rung = <String>[];
      repository = FakeVoiceRepository();
      connector = FakeVoiceCallConnector();
      controller = VoiceSessionController(
        repository: repository,
        connector: connector,
        onCallJoined: (callId) async => rung.add(callId),
      );

      await callBob();

      expect(rung, ['call-dm-bob']);
      await controller.leave();
    });

    testWidgets('a video call turns the camera on', (tester) async {
      setUpController();

      await callBob(video: true);

      expect(controller.state!.video, isTrue);
      expect(connector.last.camera, isTrue);
      await controller.leave();
    });

    testWidgets('calling leaves a voice channel, and joining one the call', (
      tester,
    ) async {
      setUpController();
      await joinLounge();

      await callBob();
      expect(repository.leaves, 1);
      expect(controller.state!.isDirectCall, isTrue);

      await joinLounge();
      expect(repository.leftCalls, ['call-dm-bob']);
      expect(controller.state!.channelId, 'ch-lounge');
      await controller.leave();
    });

    testWidgets('a refused call leaves no session', (tester) async {
      setUpController();
      repository.startCallError = const VoiceAccessDeniedException();

      await expectLater(callBob(), throwsA(isA<VoiceAccessDeniedException>()));

      expect(controller.state, isNull);
      expect(connector.calls, isEmpty);
      await controller.leave();
    });

    testWidgets('an ended call ends the session on the next heartbeat', (
      tester,
    ) async {
      setUpController();
      await callBob();

      repository
        ..updateResult = false
        ..rejoinResult = false;
      await tester.pump(voiceHeartbeatInterval);
      await tester.pump();

      expect(repository.rejoinedCalls, ['call-dm-bob']);
      expect(controller.state, isNull);
      expect(connector.last.disconnects, 1);
      await controller.leave();
    });

    testWidgets('a missed heartbeat rejoins a call still going', (
      tester,
    ) async {
      setUpController();
      await callBob();

      repository.updateResult = false;
      await tester.pump(voiceHeartbeatInterval);
      await tester.pump();

      expect(repository.rejoinedCalls, ['call-dm-bob']);
      expect(controller.state, isNotNull);
      repository.updateResult = true;
      await controller.leave();
    });
  });

  test('screen sharing is offered on the web and macOS only', () {
    expect(
      voiceScreenShareSupported(isWeb: true, platform: TargetPlatform.iOS),
      isTrue,
    );
    expect(
      voiceScreenShareSupported(isWeb: false, platform: TargetPlatform.macOS),
      isTrue,
    );
    expect(
      voiceScreenShareSupported(isWeb: false, platform: TargetPlatform.iOS),
      isFalse,
    );
  });
}
