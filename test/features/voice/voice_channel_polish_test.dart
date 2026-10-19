import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_polish.dart';
import 'package:wecord/features/voice/voice_session.dart';

import '../../mobile/phone_test_support.dart';
import 'voice_fakes.dart';

/// Voice channel status, connection quality and audio only (E6) in the full
/// app, with a fake voice server and call.
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

  VoiceCallParticipant withCamera() => VoiceCallParticipant(
    userId: bart.id,
    name: bart.displayName,
    microphoneEnabled: true,
    cameraEnabled: true,
    cameraView: (context) => const ColoredBox(
      key: ValueKey('fake-remote-camera'),
      color: Colors.teal,
    ),
  );

  Future<FakeVoiceCall> join(WidgetTester tester, PhoneWorld world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(channelRow('ch-lounge'));
    await settle(tester);
    return world.voiceCalls.last;
  }

  group('the channel status line', () {
    testWidgets('shows under a voice channel somebody is in', (tester) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voice.states['circle-1'] = [
        voiceMember(userId: bart.id, name: bart.displayName),
      ];
      world.voice.channelStatuses['circle-1'] = {'ch-lounge': 'Playing ranked'};
      await world.open(tester, '/circles/circle-1');

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('circle-channel-ch-lounge')),
          matching: find.text('Playing ranked'),
        ),
        findsOneWidget,
      );

      // A change reaches the list.
      world.voice.channelStatuses['circle-1'] = {'ch-lounge': 'Movie night'};
      world.voice.emitChange();
      await settle(tester);
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('Playing ranked'), findsNothing);

      // And clearing it removes the line.
      world.voice.channelStatuses['circle-1'] = const {};
      world.voice.emitChange();
      await settle(tester);
      expect(find.byKey(const ValueKey('voice-channel-status')), findsNothing);
      await world.close(tester);
    });

    testWidgets('people in the channel set it from the room header', (
      tester,
    ) async {
      useWideScreen(tester);
      final world = voiceWorld();
      await join(tester, world);

      await tester.tap(find.byKey(const ValueKey('voice-status-button')));
      await settle(tester);
      expect(
        find.text('Tell everyone what this channel is about right now.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('voice-status-field')),
        '  Playing   ranked ',
      );
      await tester.tap(find.byKey(const ValueKey('voice-status-save')));
      await settle(tester);

      expect(world.voice.setStatuses, {'ch-lounge': 'Playing ranked'});
      // The sheet is gone.
      expect(find.byKey(const ValueKey('voice-status-field')), findsNothing);
      await world.close(tester);
    });

    testWidgets('shows in the header and can be cleared', (tester) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voice.channelStatuses['circle-1'] = {'ch-lounge': 'Study together'};
      await join(tester, world);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('voice-channel-view-ch-lounge')),
          matching: find.text('Study together'),
        ),
        findsWidgets,
      );
      await tester.tap(find.byKey(const ValueKey('voice-status-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('voice-status-clear')));
      await settle(tester);
      expect(world.voice.setStatuses, {'ch-lounge': ''});
      await world.close(tester);
    });

    testWidgets('a status over 60 characters is not sent', (tester) async {
      useWideScreen(tester);
      final world = voiceWorld();
      await join(tester, world);

      await tester.tap(find.byKey(const ValueKey('voice-status-button')));
      await settle(tester);
      // The field itself stops at 60, so a long paste is cut.
      await tester.enterText(
        find.byKey(const ValueKey('voice-status-field')),
        'x' * 80,
      );
      await tester.tap(find.byKey(const ValueKey('voice-status-save')));
      await settle(tester);
      expect(
        world.voice.setStatuses['ch-lounge']?.length ?? 0,
        lessThanOrEqualTo(60),
      );
      await world.close(tester);
    });

    test('tidying makes one line', () {
      expect(tidyVoiceStatus('  a \n  b\t c '), 'a b c');
      expect(tidyVoiceStatus('   '), '');
    });
  });

  group('connection quality', () {
    testWidgets('shows on your own tile only', (tester) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voiceCalls.prepare = (call) {
        call.remotes = [
          VoiceCallParticipant(userId: bart.id, name: bart.displayName),
        ];
        call.connectionQuality = VoiceConnectionQuality.poor;
      };
      final call = await join(tester, world);

      expect(
        find.byKey(const ValueKey('voice-quality-badge-poor')),
        findsOneWidget,
      );
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Poor connection')), findsWidgets);
      handle.dispose();

      call.connectionQuality = VoiceConnectionQuality.excellent;
      call.update();
      await settle(tester);
      expect(
        find.byKey(const ValueKey('voice-quality-badge-poor')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('voice-quality-badge-excellent')),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a poor connection offers audio only after a while', (
      tester,
    ) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voiceCalls.prepare = (call) {
        call.remotes = [withCamera()];
        call.connectionQuality = VoiceConnectionQuality.poor;
      };
      final call = await join(tester, world);

      // Not at once: a blip is no reason to bother anyone.
      expect(find.byKey(const ValueKey('voice-quality-banner')), findsNothing);
      await tester.pump(poorConnectionHintDelay + const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('voice-quality-banner')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('voice-quality-audio-only')));
      await settle(tester);
      expect(call.audioOnly, isTrue);
      expect(find.byKey(const ValueKey('voice-quality-banner')), findsNothing);
      expect(find.text('Voice connected · Audio only'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('a connection that recovers in time shows no hint', (
      tester,
    ) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voiceCalls.prepare = (call) {
        call.remotes = [withCamera()];
        call.connectionQuality = VoiceConnectionQuality.poor;
      };
      final call = await join(tester, world);

      await tester.pump(const Duration(seconds: 2));
      call.connectionQuality = VoiceConnectionQuality.good;
      call.update();
      await settle(tester);
      await tester.pump(poorConnectionHintDelay * 2);
      expect(find.byKey(const ValueKey('voice-quality-banner')), findsNothing);
      await world.close(tester);
    });

    testWidgets('with nobody on video there is nothing to save', (
      tester,
    ) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voiceCalls.prepare = (call) {
        call.remotes = [
          VoiceCallParticipant(userId: bart.id, name: bart.displayName),
        ];
        call.connectionQuality = VoiceConnectionQuality.lost;
      };
      await join(tester, world);
      await tester.pump(poorConnectionHintDelay + const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('voice-quality-banner')), findsNothing);
      await world.close(tester);
    });

    testWidgets('can be dismissed, and comes back after a recovery', (
      tester,
    ) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voiceCalls.prepare = (call) {
        call.remotes = [withCamera()];
        call.connectionQuality = VoiceConnectionQuality.poor;
      };
      final call = await join(tester, world);
      await tester.pump(poorConnectionHintDelay + const Duration(seconds: 1));

      await tester.tap(find.byKey(const ValueKey('voice-quality-dismiss')));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-quality-banner')), findsNothing);

      call.connectionQuality = VoiceConnectionQuality.good;
      call.update();
      await tester.pump();
      call.connectionQuality = VoiceConnectionQuality.poor;
      call.update();
      await tester.pump();
      await tester.pump(poorConnectionHintDelay + const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('voice-quality-banner')),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });

  group('audio only', () {
    testWidgets('the header button stops and resumes receiving video', (
      tester,
    ) async {
      useWideScreen(tester);
      final world = voiceWorld();
      world.voiceCalls.prepare = (call) => call.remotes = [withCamera()];
      final call = await join(tester, world);

      expect(find.byTooltip('Audio only'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-audio-only-button')));
      await settle(tester);
      expect(call.audioOnly, isTrue);
      expect(find.byTooltip('Receive video again'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('voice-audio-only-button')));
      await settle(tester);
      expect(call.audioOnly, isFalse);
      await world.close(tester);
    });

    test('a session starts out receiving video', () {
      const session = VoiceSession(conversationId: 'c', channelName: 'Lounge');
      expect(session.audioOnly, isFalse);
      expect(session.copyWith(audioOnly: true).audioOnly, isTrue);
      expect(session.copyWith(audioOnly: true).copyWith().audioOnly, isTrue);
    });
  });
}
