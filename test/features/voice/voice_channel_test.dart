import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/models/circle_event.dart';

import '../../mobile/phone_test_support.dart';
import 'voice_fakes.dart';

/// Voice channels in the full app, with a fake voice server and call.
void main() {
  void useWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  PhoneWorld voiceWorld() {
    final world = PhoneWorld();
    world.circles.detail = circleDetailWithVoice();
    return world;
  }

  Finder channelRow(String channelId) =>
      find.byKey(ValueKey('circle-channel-row-$channelId'));

  Finder panel() => find.byKey(const ValueKey('voice-connected-panel'));

  testWidgets('voice channels list who is connected, with their state', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voice.states['circle-1'] = [
      voiceMember(
        userId: bart.id,
        name: bart.displayName,
        nickname: 'Bart the Bold',
        roleColor: 0x3498DB,
        selfMute: true,
      ),
      voiceMember(
        userId: grace.id,
        name: grace.displayName,
        selfDeaf: true,
        video: true,
        screen: true,
      ),
    ];
    await world.open(tester, '/circles/circle-1');

    expect(
      find.descendant(
        of: channelRow('ch-lounge'),
        matching: find.byIcon(Icons.volume_up_outlined),
      ),
      findsOneWidget,
    );
    final members = find.byKey(
      const ValueKey('voice-channel-members-ch-lounge'),
    );
    expect(members, findsOneWidget);
    expect(
      find.descendant(of: members, matching: find.text('Bart the Bold')),
      findsOneWidget,
    );
    final bartRow = find.byKey(ValueKey('voice-member-${bart.id}'));
    expect(
      find.descendant(
        of: bartRow,
        matching: find.byIcon(Icons.mic_off_outlined),
      ),
      findsOneWidget,
    );
    final graceRow = find.byKey(ValueKey('voice-member-${grace.id}'));
    for (final icon in [
      Icons.headset_off_outlined,
      Icons.videocam_outlined,
      Icons.screen_share_outlined,
    ]) {
      expect(
        find.descendant(of: graceRow, matching: find.byIcon(icon)),
        findsOneWidget,
      );
    }
    // Deafened implies muted, so only the headset shows.
    expect(
      find.descendant(
        of: graceRow,
        matching: find.byIcon(Icons.mic_off_outlined),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('voice-channel-members-ch-stage')),
      findsNothing,
    );
    expect(panel(), findsNothing);

    // A change on the server shows up.
    world.voice.states['circle-1'] = const [];
    world.voice.emitChange();
    await settle(tester);
    expect(members, findsNothing);
    await world.close(tester);
  });

  testWidgets('without a voice service, joining explains it', (tester) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voice.tokenError = const VoiceNotConfiguredException();
    await world.open(tester, '/circles/circle-1');

    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);

    expect(
      find.byKey(const ValueKey('voice-not-configured-dialog')),
      findsOneWidget,
    );
    expect(find.text("Voice service isn't configured yet"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await settle(tester);

    // The channel view stays, offering to try again.
    expect(find.byKey(const ValueKey('voice-not-connected')), findsOneWidget);
    expect(world.voiceCalls.calls, isEmpty);
    expect(panel(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-join-button')));
    await settle(tester);
    expect(find.text("Voice service isn't configured yet"), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('joining shows the call, its controls and the panel', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: bart.displayName,
          isSpeaking: true,
          microphoneEnabled: true,
        ),
      ];
    };
    await world.open(tester, '/circles/circle-1');

    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);

    expect(world.voice.joined, ['ch-lounge']);
    expect(find.byKey(const ValueKey('voice-call-grid')), findsOneWidget);
    expect(find.byKey(ValueKey('voice-tile-${me.id}')), findsOneWidget);
    expect(find.text('${me.displayName} (you)'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-tile-speaking')), findsOneWidget);
    expect(panel(), findsOneWidget);
    expect(
      find.descendant(of: panel(), matching: find.text('Voice connected')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel(), matching: find.text('Lounge')),
      findsOneWidget,
    );

    final call = world.voiceCalls.last;
    await tester.tap(find.byKey(const ValueKey('voice-control-mic')));
    await settle(tester);
    expect(call.microphone, isFalse);
    expect(world.voice.updates.last.mute, isTrue);
    expect(find.byTooltip('Unmute'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('voice-control-deafen')));
    await settle(tester);
    expect(call.remoteAudio, isFalse);
    expect(world.voice.updates.last.deaf, isTrue);

    await tester.tap(find.byKey(const ValueKey('voice-control-camera')));
    await settle(tester);
    expect(call.camera, isTrue);
    expect(find.byKey(const ValueKey('fake-local-camera')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-control-screen')));
    await settle(tester);
    expect(call.screenSource, 'screen-1');
    expect(find.byKey(ValueKey('voice-screen-tile-${me.id}')), findsOneWidget);
    expect(world.voice.updates.last, (
      mute: true,
      deaf: true,
      video: true,
      screen: true,
    ));

    // Moving to a text channel keeps the call and the panel.
    await tester.tap(channelRow('ch-general'));
    await settle(tester);
    expect(find.byKey(const ValueKey('voice-call-grid')), findsNothing);
    expect(panel(), findsOneWidget);
    expect(call.disconnects, 0);

    // The panel's channel name opens the call again.
    await tester.tap(
      find.descendant(of: panel(), matching: find.text('Lounge')),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('voice-call-grid')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-control-leave')));
    await settle(tester);
    expect(call.disconnects, 1);
    expect(world.voice.leaves, 1);
    expect(panel(), findsNothing);
    expect(find.byKey(const ValueKey('voice-not-connected')), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('a participant menu sets their volume for me', (tester) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(userId: bart.id, name: bart.displayName),
      ];
    };
    await world.open(tester, '/circles/circle-1');
    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);

    await tester.tap(
      find.byKey(ValueKey('voice-tile-${bart.id}')),
      buttons: kSecondaryMouseButton,
    );
    await settle(tester);
    final slider = find.byKey(ValueKey('voice-user-volume-${bart.id}'));
    expect(slider, findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await tester.drag(slider, const Offset(600, 0));
    await settle(tester);
    expect(find.text('200%'), findsOneWidget);
    expect(world.voiceSettings.saved!.volumeFor(bart.id), 2);
    expect(world.voiceCalls.last.userVolumes, {bart.id: 2.0});

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    // There is no volume for yourself.
    await tester.tap(
      find.byKey(ValueKey('voice-tile-${me.id}')),
      buttons: kSecondaryMouseButton,
    );
    await settle(tester);
    expect(find.byKey(ValueKey('voice-user-volume-${me.id}')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await world.close(tester);
  });

  testWidgets('push to talk on a phone holds a button to talk', (tester) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voiceSettings.saved = const VoiceSettings(
      inputMode: VoiceInputMode.pushToTalk,
    );
    await world.open(tester, '/circles/circle-1');
    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);

    final call = world.voiceCalls.last;
    expect(call.microphone, isFalse);
    final hold = find.byKey(const ValueKey('voice-hold-to-talk'));
    expect(hold, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(hold));
    await tester.pump();
    expect(call.microphone, isTrue);
    expect(find.text('Talking…'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(call.microphone, isFalse);
    // Others still see an unmuted member.
    expect(world.voice.updates.every((update) => !update.mute), isTrue);

    await tester.tap(find.byKey(const ValueKey('voice-control-leave')));
    await settle(tester);
    await world.close(tester);
  });

  testWidgets('the sidebar rings members speaking in my call', (tester) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voice.states['circle-1'] = [
      voiceMember(userId: me.id, name: me.displayName),
      voiceMember(userId: bart.id, name: bart.displayName),
    ];
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: bart.displayName,
          isSpeaking: true,
        ),
      ];
    };
    await world.open(tester, '/circles/circle-1');
    final members = find.byKey(
      const ValueKey('voice-channel-members-ch-lounge'),
    );
    expect(
      find.descendant(
        of: members,
        matching: find.byKey(const ValueKey('voice-speaking-ring')),
      ),
      findsNothing,
    );

    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);

    final ring = find.descendant(
      of: find.byKey(ValueKey('voice-member-${bart.id}')),
      matching: find.byKey(const ValueKey('voice-speaking-ring')),
    );
    expect(ring, findsOneWidget);
    world.voiceCalls.last.remotes = const [];
    world.voiceCalls.last.update();
    await settle(tester);
    expect(ring, findsNothing);
    await world.close(tester);
  });

  testWidgets('a live voice event offers to join its channel', (tester) async {
    final world = voiceWorld();
    final live = world.circles.events.first;
    world.circles.events = [
      CircleEvent(
        id: live.id,
        circleId: live.circleId,
        title: live.title,
        description: live.description,
        locationType: CircleEventLocationType.voice,
        channelId: 'ch-lounge',
        channelName: 'Lounge',
        startsAt: live.startsAt,
        endsAt: live.endsAt,
        createdBy: live.createdBy,
        creator: live.creator,
        interestedCount: live.interestedCount,
        interestedByMe: live.interestedByMe,
        canManage: live.canManage,
      ),
      ...world.circles.events.skip(1),
    ];
    await world.open(tester, '/circles/circle-1/events');

    final join = find.byKey(ValueKey('circle-event-join-voice-${live.id}'));
    expect(join, findsOneWidget);
    await tester.tap(join);
    await settle(tester);

    expect(world.voice.joined, ['ch-lounge']);
    expect(find.byKey(const ValueKey('voice-call-grid')), findsOneWidget);
    await world.close(tester);
  });
}
