import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRepository repository;
  late FakeVoiceCallConnector connector;
  late VoiceSessionController controller;
  late List<String> changedCircles;

  void setUpController() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    changedCircles = [];
    controller = VoiceSessionController(
      repository: repository,
      connector: connector,
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
