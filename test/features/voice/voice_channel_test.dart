import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/conversation.dart';

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

  testWidgets('moderators mute, move and disconnect from the menu', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voice.states['circle-1'] = [
      voiceMember(userId: me.id, name: me.displayName),
      voiceMember(userId: bart.id, name: bart.displayName),
    ];
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(userId: bart.id, name: bart.displayName),
      ];
    };
    await world.open(tester, '/circles/circle-1');
    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);

    Future<void> openMenu() async {
      await tester.tap(
        find.byKey(ValueKey('voice-tile-${bart.id}')),
        buttons: kSecondaryMouseButton,
      );
      await settle(tester);
    }

    await openMenu();
    await tester.tap(find.byKey(const ValueKey('voice-menu-server-mute')));
    await settle(tester);
    expect(world.voice.moderation, ['mute:${bart.id}:true']);
    expect(world.voice.enforced, ['ch-lounge:${bart.id}']);

    await openMenu();
    await tester.tap(find.byKey(const ValueKey('voice-menu-server-deafen')));
    await settle(tester);
    expect(world.voice.moderation.last, 'deafen:${bart.id}:true');

    await openMenu();
    await tester.tap(find.byKey(const ValueKey('voice-menu-move')));
    await settle(tester);
    expect(find.byKey(const ValueKey('voice-move-dialog')), findsOneWidget);
    // Not back into the channel they are in.
    expect(
      find.byKey(const ValueKey('voice-move-target-ch-lounge')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('voice-move-target-ch-stage')));
    await settle(tester);
    expect(world.voice.moderation.last, 'move:${bart.id}:ch-stage');
    // The room they left is told to let them go.
    expect(world.voice.enforced.last, 'ch-lounge:${bart.id}');

    await openMenu();
    await tester.tap(find.byKey(const ValueKey('voice-menu-disconnect')));
    await settle(tester);
    expect(world.voice.moderation.last, 'disconnect:${bart.id}');

    // Your own menu has no volume, but you can server mute yourself.
    await tester.tap(
      find.byKey(ValueKey('voice-tile-${me.id}')),
      buttons: kSecondaryMouseButton,
    );
    await settle(tester);
    expect(
      find.byKey(const ValueKey('voice-menu-server-mute')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-menu-disconnect')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await world.close(tester);
  });

  testWidgets('server muted members show it, and so do my controls', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voice.states['circle-1'] = [
      voiceMember(userId: bart.id, name: bart.displayName, serverMute: true),
    ];
    world.voice.tokenServerMute = true;
    await world.open(tester, '/circles/circle-1');

    expect(
      find.descendant(
        of: find.byKey(ValueKey('voice-member-${bart.id}')),
        // Filled, unlike muting yourself.
        matching: find.byIcon(Icons.mic_off),
      ),
      findsOneWidget,
    );

    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);
    final mic = tester.widget<IconButton>(
      find.byKey(const ValueKey('voice-control-mic')),
    );
    expect(mic.onPressed, isNull);
    expect(mic.tooltip, 'Server muted');
    expect(world.voiceCalls.last.microphone, isFalse);
    await tester.tap(find.byKey(const ValueKey('voice-control-leave')));
    await settle(tester);
    await world.close(tester);
  });

  testWidgets('user limits show in the sidebar and stop joining', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.voice.userLimits['circle-1'] = {'ch-lounge': 2};
    world.voice.states['circle-1'] = [
      voiceMember(userId: bart.id, name: bart.displayName),
      voiceMember(userId: grace.id, name: grace.displayName),
    ];
    world.voice.tokenError = const VoiceChannelFullException();
    await world.open(tester, '/circles/circle-1');

    final badge = find.descendant(
      of: channelRow('ch-lounge'),
      matching: find.byKey(const ValueKey('voice-user-limit-badge')),
    );
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('02/02')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: channelRow('ch-stage'),
        matching: find.byKey(const ValueKey('voice-user-limit-badge')),
      ),
      findsNothing,
    );

    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);
    expect(find.text('This voice channel is full.'), findsOneWidget);
    expect(world.voiceCalls.calls, isEmpty);

    // Channel settings change the limit.
    await tester.tap(find.byTooltip('Channel settings').first);
    await settle(tester);
    final slider = find.byKey(const ValueKey('voice-user-limit-slider'));
    await tester.ensureVisible(slider);
    await settle(tester);
    expect(find.text('2 people'), findsOneWidget);
    await tester.drag(slider, const Offset(-2000, 0));
    await settle(tester);
    expect(world.voice.setLimits, {'ch-lounge': 0});
    await world.close(tester);
  });

  testWidgets('voice channels have their own text chat beside the call', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = voiceWorld();
    world.chats.conversations = [
      ...world.chats.conversations,
      ConversationSummary(
        id: 'conv-lounge',
        type: ConversationType.channel,
        unreadCount: 3,
        title: 'Lounge',
        lastMessageAt: DateTime.utc(2026, 10, 16, 9),
        circleId: 'circle-1',
      ),
    ];
    await world.open(tester, '/circles/circle-1');

    // Unread chat marks the voice channel like a text channel.
    expect(
      find.descendant(
        of: channelRow('ch-lounge'),
        matching: find.byKey(const ValueKey('channel-unread-pill')),
      ),
      findsOneWidget,
    );

    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('voice-chat-unread-badge')),
      findsOneWidget,
    );
    final panel = find.byKey(const ValueKey('voice-chat-panel-ch-lounge'));
    expect(panel, findsNothing);

    await tester.tap(find.byKey(const ValueKey('voice-chat-button')));
    await settle(tester);
    expect(panel, findsOneWidget);
    // The call stays beside it.
    expect(find.byKey(const ValueKey('voice-call-grid')), findsOneWidget);
    expect(world.chats.markReadCalls, contains('conv-lounge'));

    await tester.enterText(
      find.descendant(of: panel, matching: find.byType(TextField)),
      'On my way',
    );
    await tester.tap(
      find.descendant(of: panel, matching: find.byTooltip('Send')),
    );
    await settle(tester);
    expect(world.chats.sentMessages.last.conversationId, 'conv-lounge');
    expect(world.chats.sentMessages.last.body, 'On my way');

    await tester.tap(find.byKey(const ValueKey('voice-chat-button')));
    await settle(tester);
    expect(panel, findsNothing);
    await world.close(tester);
  });

  testWidgets('on a phone the voice chat opens full screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final world = voiceWorld();
    await world.open(tester, '/circles/circle-1/channels/conv-lounge');

    expect(
      find.byKey(const ValueKey('voice-channel-view-ch-lounge')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('voice-chat-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-chat-button')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('voice-chat-page-ch-lounge')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsWidgets);
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
