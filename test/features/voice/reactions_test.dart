import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/reactions/floating_reactions.dart';
import 'package:wecord/features/voice/reactions/reaction_message.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRepository repository;
  late FakeVoiceCallConnector connector;
  late ProviderContainer container;

  setUp(() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    connector.prepare = (call) => call.remotes = const [
      VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
      VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
    ];
  });

  /// A call with its grid and control bar, like the voice room.
  Future<void> pumpCall(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceRepositoryProvider.overrideWithValue(repository),
          voiceCallConnectorProvider.overrideWithValue(connector),
          authStateProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(id: 'user-1')),
          ),
        ],
        child: MaterialApp(
          theme: WeCordTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final session = ref.watch(voiceSessionProvider);
                if (session == null || !session.isConnected) {
                  return const SizedBox();
                }
                return Column(
                  children: [
                    Expanded(
                      child: VoiceCallGrid(session: session, people: const {}),
                    ),
                    VoiceCallControls(session: session),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
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

  Future<void> leave(WidgetTester tester) async {
    await container.read(voiceSessionProvider.notifier).leave();
    await tester.pump();
  }

  /// [userId] reacts; the event takes a few microtasks to reach the tiles.
  Future<void> receive(
    WidgetTester tester,
    String userId,
    String emoji, {
    int times = 1,
  }) async {
    for (var i = 0; i < times; i++) {
      connector.last.receiveReaction(userId, emoji);
    }
    await tester.pump();
    await tester.pump();
  }

  Finder onTile(String userId, String emoji) => find.descendant(
    of: find.byKey(ValueKey('voice-tile-$userId')),
    matching: find.text(emoji),
  );

  group('sending', () {
    testWidgets('the reactions button opens the emoji and a tap sends one', (
      tester,
    ) async {
      await pumpCall(tester);
      expect(find.byKey(const ValueKey('voice-reaction-tray')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('voice-control-reactions')));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-reaction-tray')), findsOneWidget);
      for (final emoji in callReactionEmojis) {
        expect(find.byKey(ValueKey('voice-reaction-$emoji')), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('voice-reaction-🎉')));
      await tester.pump();

      // Sent to the room, and shown over the sender's own tile at once.
      expect(connector.last.sentReactions, ['🎉']);
      expect(onTile('user-1', '🎉'), findsOneWidget);
      // The tray gets out of the way.
      expect(find.byKey(const ValueKey('voice-reaction-tray')), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await leave(tester);
    });

    testWidgets('only five in three seconds go out', (tester) async {
      await pumpCall(tester);
      final controller = container.read(voiceSessionProvider.notifier);

      final results = [
        for (var i = 0; i < 7; i++) await controller.sendReaction('👍'),
      ];
      expect(results, [true, true, true, true, true, false, false]);
      expect(connector.last.sentReactions, hasLength(5));
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await leave(tester);
    });

    testWidgets('a held back tap leaves the tray open', (tester) async {
      await pumpCall(tester);
      final controller = container.read(voiceSessionProvider.notifier);
      for (var i = 0; i < 5; i++) {
        await controller.sendReaction('👍');
      }
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('voice-control-reactions')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-reaction-❤️')));
      await tester.pump();

      expect(connector.last.sentReactions, hasLength(5));
      expect(find.byKey(const ValueKey('voice-reaction-tray')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await leave(tester);
    });

    testWidgets('other emoji are not sent', (tester) async {
      await pumpCall(tester);
      final controller = container.read(voiceSessionProvider.notifier);
      expect(await controller.sendReaction('💩'), isFalse);
      expect(connector.last.sentReactions, isEmpty);
      await leave(tester);
    });
  });

  group('receiving', () {
    testWidgets('floats up over the sender\'s tile and fades away', (
      tester,
    ) async {
      await pumpCall(tester);
      await receive(tester, 'user-2', '😂');

      final emoji = onTile('user-2', '😂');
      expect(emoji, findsOneWidget);
      expect(onTile('user-3', '😂'), findsNothing);
      final start = tester.getCenter(emoji).dy;

      await tester.pump(const Duration(milliseconds: 1200));
      expect(emoji, findsOneWidget);
      expect(tester.getCenter(emoji).dy, lessThan(start - 20));

      await tester.pump(reactionFloatDuration);
      await tester.pump();
      expect(emoji, findsNothing);
      await leave(tester);
    });

    testWidgets('several at once, but not more than the tile can hold', (
      tester,
    ) async {
      await pumpCall(tester);
      await receive(tester, 'user-3', '👏', times: 12);

      expect(onTile('user-3', '👏'), findsNWidgets(maxFloatingReactions));
      await tester.pump(
        reactionFloatDuration + const Duration(milliseconds: 100),
      );
      await tester.pump();
      expect(onTile('user-3', '👏'), findsNothing);
      await leave(tester);
    });

    testWidgets('your own reaction shows on your tile too', (tester) async {
      await pumpCall(tester);
      await container.read(voiceSessionProvider.notifier).sendReaction('👍');
      await tester.pump();
      expect(onTile('user-1', '👍'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
      await leave(tester);
    });

    testWidgets('with reduced motion it stays put and fades', (tester) async {
      await pumpCall(tester, disableAnimations: true);
      await receive(tester, 'user-2', '❤️');

      final emoji = onTile('user-2', '❤️');
      final start = tester.getCenter(emoji);
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.getCenter(emoji), start);

      await tester.pump(reducedMotionDuration);
      await tester.pump();
      expect(emoji, findsNothing);
      await leave(tester);
    });

    testWidgets('screen readers hear who reacted', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCall(tester);
      await receive(tester, 'user-2', '🎉');
      // The floating emoji itself is not read out.
      expect(find.bySemanticsLabel('🎉'), findsNothing);
      await tester.pump(reactionFloatDuration);
      await tester.pump();
      handle.dispose();
      await leave(tester);
    });

    testWidgets('reactions end with the call', (tester) async {
      await pumpCall(tester);
      final call = connector.last;
      await leave(tester);
      // Nothing listens any more and nothing throws.
      call.receiveReaction('user-2', '👍');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
