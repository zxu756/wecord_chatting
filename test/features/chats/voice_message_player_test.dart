import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../transcribe/transcribe_fakes.dart';

void main() {
  setUp(() => VoiceMessagePlayer.debugPlayersCreated = 0);

  Widget app(int count) {
    return ProviderScope(
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (var index = 0; index < count; index++)
                  SizedBox(
                    width: 320,
                    child: VoiceMessagePlayer(attachment: testVoice),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('voice bubbles make no audio player until one is played', (
    tester,
  ) async {
    await tester.pumpWidget(app(12));

    expect(find.byTooltip('Play voice message'), findsNWidgets(12));
    // The length shows without a player.
    expect(find.text('0:04'), findsNWidgets(12));
    expect(VoiceMessagePlayer.debugPlayersCreated, 0);

    await tester.tap(find.byTooltip('Play voice message').first);
    await tester.pump();
    await tester.pump();

    // Only the played one made a player.
    expect(VoiceMessagePlayer.debugPlayersCreated, 1);
  });
}
