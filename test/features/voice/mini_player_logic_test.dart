import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/mini_player/active_speaker.dart';
import 'package:wecord/features/voice/mini_player/call_mini_player.dart';
import 'package:wecord/features/voice/voice_call.dart';

VoiceCallParticipant person(
  String id, {
  bool local = false,
  bool speaking = false,
  bool camera = false,
  bool screen = false,
}) {
  return VoiceCallParticipant(
    userId: id,
    name: id,
    isLocal: local,
    isSpeaking: speaking,
    cameraEnabled: camera,
    screenShareEnabled: screen,
  );
}

void main() {
  group('who the mini player shows', () {
    test('nobody in the room', () {
      expect(activeSpeakerOf(const []), isNull);
    });

    test('alone, the current user', () {
      expect(activeSpeakerOf([person('me', local: true)])?.userId, 'me');
    });

    test('someone else speaking comes first, not the current user', () {
      final speaker = activeSpeakerOf([
        person('me', local: true, speaking: true),
        person('ada'),
        person('bob', speaking: true),
      ]);
      expect(speaker?.userId, 'bob');
    });

    test('when it goes quiet, the last speaker stays', () {
      final participants = [
        person('me', local: true),
        person('ada'),
        person('bob'),
      ];
      expect(activeSpeakerOf(participants, previousId: 'bob')?.userId, 'bob');
      // Unless they left.
      expect(activeSpeakerOf(participants, previousId: 'cy')?.userId, 'ada');
    });

    test('before anyone spoke, someone with video or a screen', () {
      final speaker = activeSpeakerOf([
        person('me', local: true, camera: true),
        person('ada'),
        person('bob', screen: true),
      ]);
      expect(speaker?.userId, 'bob');
    });
  });

  group('where the window sits', () {
    const area = Size(400, 800);
    const window = Size(188, 120);
    const padding = EdgeInsets.only(top: 47, bottom: 34);

    Offset at(MiniPlayerCorner corner) => miniPlayerOffset(
      corner: corner,
      area: area,
      window: window,
      padding: padding,
      bottomClearance: 84,
    );

    test('four corners inside the system bars and clear of the bottom bar', () {
      expect(at(MiniPlayerCorner.topLeft), const Offset(12, 59));
      expect(at(MiniPlayerCorner.topRight), const Offset(200, 59));
      expect(at(MiniPlayerCorner.bottomLeft), const Offset(12, 550));
      expect(at(MiniPlayerCorner.bottomRight), const Offset(200, 550));
    });

    test('wide windows keep clear of the rail and the title bar', () {
      Offset wide(MiniPlayerCorner corner) => miniPlayerOffset(
        corner: corner,
        area: const Size(1400, 900),
        window: const Size(244, 150),
        padding: EdgeInsets.zero,
        leftClearance: 72,
        topClearance: 10,
      );
      expect(wide(MiniPlayerCorner.topLeft), const Offset(84, 22));
      expect(wide(MiniPlayerCorner.topRight), const Offset(1144, 22));
      expect(wide(MiniPlayerCorner.bottomLeft), const Offset(84, 738));
      expect(wide(MiniPlayerCorner.bottomRight), const Offset(1144, 738));
    });

    test('a window bigger than the area still has a place', () {
      final tight = miniPlayerOffset(
        corner: MiniPlayerCorner.bottomRight,
        area: const Size(100, 100),
        window: window,
        padding: EdgeInsets.zero,
      );
      expect(tight.dx, greaterThanOrEqualTo(0));
      expect(tight.dy, greaterThanOrEqualTo(0));
    });

    test('let go, it settles in the nearest corner', () {
      MiniPlayerCorner settle(
        Offset position, [
        Offset velocity = Offset.zero,
      ]) {
        return nearestMiniPlayerCorner(
          position: position,
          velocity: velocity,
          area: area,
          window: window,
        );
      }

      expect(settle(const Offset(20, 80)), MiniPlayerCorner.topLeft);
      expect(settle(const Offset(190, 80)), MiniPlayerCorner.topRight);
      expect(settle(const Offset(30, 600)), MiniPlayerCorner.bottomLeft);
      expect(settle(const Offset(180, 600)), MiniPlayerCorner.bottomRight);
    });

    test('a flick carries it to the corner it was thrown at', () {
      // Left of centre, thrown right and down.
      final corner = nearestMiniPlayerCorner(
        position: const Offset(60, 300),
        velocity: const Offset(2500, 2500),
        area: area,
        window: window,
      );
      expect(corner, MiniPlayerCorner.bottomRight);
    });
  });
}
