import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';

import '../../mobile/phone_test_support.dart';
import 'voice_fakes.dart';

/// Who is speaking changes the voice session many times a second during a
/// call. Only what shows who speaks may rebuild for it, not the
/// conversation list that merely notes a call is on.
void main() {
  testWidgets('the Home sidebar does not rebuild when someone speaks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final world = PhoneWorld();
    world.circles.detail = circleDetailWithVoice();
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
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
    // The call goes on while the reader is on Home.
    world.router.go('/home');
    await settle(tester);
    expect(find.byKey(const ValueKey('voice-connected-panel')), findsWidgets);

    var rebuilds = 0;
    var total = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      total += 1;
      if (element.widget.runtimeType.toString() == 'HomeSidebar') {
        rebuilds += 1;
      }
    };
    for (var i = 0; i < 10; i++) {
      world.voiceCalls.last.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: bart.displayName,
          isSpeaking: i.isEven,
        ),
      ];
      world.voiceCalls.last.update();
      await tester.pump();
    }
    debugOnRebuildDirtyWidget = null;
    debugPrint(
      'Home sidebar rebuilds while someone speaks (10 changes): $rebuilds '
      '($total widgets rebuilt in all)',
    );

    expect(rebuilds, 0);
    await world.close(tester);
  });
}
