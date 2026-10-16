import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/voice/direct_call_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/voice.dart';

import 'voice_fakes.dart';

const _bob = DirectCallParticipant(
  userId: 'user-2',
  username: 'bob',
  displayName: 'Bob',
);

DirectCall _call({bool ringing = false}) => DirectCall(
  callId: 'call-1',
  conversationId: 'dm-bob',
  startedBy: 'user-2',
  createdAt: DateTime.utc(2026, 10, 14, 9),
  ringing: ringing,
  participants: const [_bob],
);

void main() {
  late FakeVoiceRepository repository;
  late FakeVoiceCallConnector connector;

  setUp(() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
  });

  Widget app(Widget child) {
    return ProviderScope(
      overrides: [
        voiceRepositoryProvider.overrideWithValue(repository),
        voiceCallConnectorProvider.overrideWithValue(connector),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'user-1')),
        ),
        conversationsProvider.overrideWith(
          (ref) async => const [
            ConversationSummary(
              id: 'dm-bob',
              type: ConversationType.direct,
              title: 'Bob',
              unreadCount: 0,
            ),
          ],
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  Future<void> leaveCall(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    await container.read(voiceSessionProvider.notifier).leave();
  }

  group('call bar', () {
    testWidgets('shows nothing without a call', (tester) async {
      await tester.pumpWidget(
        app(const DirectCallBar(conversationId: 'dm-bob', title: 'Bob')),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('direct-call-bar-join')), findsNothing);
      expect(
        find.byKey(const ValueKey('direct-call-bar-connected')),
        findsNothing,
      );
    });

    testWidgets('offers to join a call going on and shows it once in', (
      tester,
    ) async {
      repository.calls = [_call()];
      await tester.pumpWidget(
        app(const DirectCallBar(conversationId: 'dm-bob', title: 'Bob')),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Bob is in a call'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('direct-call-join')));
      await tester.pump();
      await tester.pump();

      expect(repository.startedCalls, ['dm-bob']);
      expect(
        find.byKey(const ValueKey('direct-call-bar-connected')),
        findsOneWidget,
      );
      expect(find.byTooltip('Disconnect'), findsOneWidget);
      await leaveCall(tester);
    });

    testWidgets('a call in progress offers to copy its link', (tester) async {
      repository.calls = [_call()];
      await tester.pumpWidget(
        app(const DirectCallBar(conversationId: 'dm-bob', title: 'Bob')),
      );
      await tester.pump();
      // The link is only offered once in the call.
      expect(
        find.byKey(const ValueKey('voice-call-link-button')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('direct-call-join')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-call-link-button')));
      await tester.pumpAndSettle();

      expect(find.text('Call link'), findsOneWidget);
      expect(find.byKey(const ValueKey('call-link-create')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await leaveCall(tester);
    });
  });

  testWidgets('a long name is cut short, not the sentence', (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const longName =
        'Bartholomew Montgomery-Fitzgerald the Third of Somewhere Far Away';
    repository.calls = [
      DirectCall(
        callId: 'call-1',
        conversationId: 'dm-bob',
        startedBy: 'user-2',
        createdAt: DateTime.utc(2026, 10, 14, 9),
        participants: const [
          DirectCallParticipant(
            userId: 'user-2',
            username: 'bart',
            displayName: longName,
          ),
        ],
      ),
    ];
    await tester.pumpWidget(
      app(const DirectCallBar(conversationId: 'dm-bob', title: 'Bart')),
    );
    await tester.pump();

    final strip = find.byKey(const ValueKey('direct-call-join-text'));
    RenderParagraph paragraph(String text) => tester.renderObject(
      find.descendant(of: strip, matching: find.text(text)),
    );
    expect(paragraph(longName).didExceedMaxLines, isTrue);
    expect(paragraph(' is in a call').didExceedMaxLines, isFalse);
    expect(find.bySemanticsLabel('$longName is in a call'), findsOneWidget);
    // Join stays on screen.
    final join = tester.getRect(find.byKey(const ValueKey('direct-call-join')));
    expect(join.right, lessThanOrEqualTo(600));

    // Too narrow for the sentence: the whole line is cut, nothing
    // overflows.
    tester.view.physicalSize = const Size(320, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: strip, matching: find.text('$longName is in a call')),
      findsOneWidget,
    );
  });

  group('incoming calls', () {
    Future<void> pumpListener(WidgetTester tester) async {
      await tester.pumpWidget(
        app(const IncomingCallListener(child: Text('chats'))),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a ringing call shows who is calling', (tester) async {
      repository.calls = [_call(ringing: true)];
      await pumpListener(tester);

      expect(find.byKey(const ValueKey('incoming-call-card')), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Incoming call'), findsOneWidget);
    });

    testWidgets('calls that stopped ringing show nothing', (tester) async {
      repository.calls = [_call()];
      await pumpListener(tester);

      expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);
    });

    testWidgets('declining tells the server and hides the call', (
      tester,
    ) async {
      repository.calls = [_call(ringing: true)];
      await pumpListener(tester);

      await tester.tap(find.byKey(const ValueKey('incoming-call-decline')));
      await tester.pump();

      expect(repository.declinedCalls, ['call-1']);
      expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);
    });

    testWidgets('joining connects to the call', (tester) async {
      repository.calls = [_call(ringing: true)];
      await pumpListener(tester);

      await tester.tap(find.byKey(const ValueKey('incoming-call-join')));
      await tester.pump();
      await tester.pump();

      expect(repository.startedCalls, ['dm-bob']);
      expect(find.byKey(const ValueKey('incoming-call-card')), findsNothing);
      await leaveCall(tester);
    });
  });
}
