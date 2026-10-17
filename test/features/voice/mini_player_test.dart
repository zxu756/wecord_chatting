import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/mini_player/call_mini_player.dart';
import 'package:wecord/features/voice/mini_player/call_surfaces.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRepository repository;
  late FakeVoiceCallConnector connector;
  late ProviderContainer container;
  VoiceSession? opened;

  setUp(() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    opened = null;
  });

  final windowKey = find.byKey(const ValueKey('call-mini-player-position'));
  final miniPlayer = find.byKey(const ValueKey('call-mini-player-host'));

  Future<void> pumpApp(
    WidgetTester tester, {
    Widget page = const Center(child: Text('another page')),
    bool disableAnimations = false,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
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
          theme: WeCordTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          // Like the shell: the mini player sits above the pages, which
          // are in a navigator of their own.
          home: CallMiniPlayerHost(
            onOpen: (session) => opened = session,
            child: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (context) => Scaffold(body: page),
              ),
            ),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(CallMiniPlayerHost)),
    );
  }

  Future<void> joinChannel(WidgetTester tester) async {
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

  testWidgets('there is no mini player without a call', (tester) async {
    await pumpApp(tester);
    await tester.pump();
    expect(miniPlayer, findsNothing);
  });

  testWidgets('a call you went away from floats over the page', (tester) async {
    repository.calls = const [];
    connector.prepare = (call) => call.remotes = [
      const VoiceCallParticipant(
        userId: 'user-2',
        name: 'Bart',
        isSpeaking: true,
        microphoneEnabled: true,
      ),
    ];
    await pumpApp(tester);
    await joinChannel(tester);

    expect(miniPlayer, findsOneWidget);
    expect(find.text('another page'), findsOneWidget);
    // The active speaker, with a way back and mute / leave.
    expect(find.text('Bart'), findsOneWidget);
    expect(find.byKey(const ValueKey('call-mini-player-mute')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('call-mini-player-leave')),
      findsOneWidget,
    );
    // Bottom right, clear of the user panel.
    final rect = tester.getRect(windowKey);
    expect(rect.right, 400 - 12);
    expect(rect.bottom, lessThan(800 - 12 - 80));
    await leave(tester);
  });

  testWidgets('shows the speaker\'s video when they have a camera', (
    tester,
  ) async {
    connector.prepare = (call) => call.remotes = [
      VoiceCallParticipant(
        userId: 'user-2',
        name: 'Bart',
        isSpeaking: true,
        cameraEnabled: true,
        cameraView: (context) =>
            const ColoredBox(key: ValueKey('bart-camera'), color: Colors.teal),
      ),
    ];
    await pumpApp(tester);
    await joinChannel(tester);

    expect(find.byKey(const ValueKey('bart-camera')), findsOneWidget);
    await leave(tester);
  });

  testWidgets('follows who speaks, and stays on the last speaker', (
    tester,
  ) async {
    connector.prepare = (call) => call.remotes = const [
      VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
      VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
    ];
    await pumpApp(tester);
    await joinChannel(tester);
    final call = connector.last;
    expect(find.text('Bart'), findsOneWidget);

    call.remotes = const [
      VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
      VoiceCallParticipant(userId: 'user-3', name: 'Grace', isSpeaking: true),
    ];
    call.update();
    await tester.pump();
    expect(find.text('Grace'), findsOneWidget);

    call.remotes = const [
      VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
      VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
    ];
    call.update();
    await tester.pump();
    expect(find.text('Grace'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('stays away while a page shows the call', (tester) async {
    await pumpApp(tester, page: const CallSurface(child: Text('the call')));
    await joinChannel(tester);
    await tester.pump();

    expect(find.text('the call'), findsOneWidget);
    expect(miniPlayer, findsNothing);
    await leave(tester);
  });

  testWidgets('appears when the page showing the call goes away', (
    tester,
  ) async {
    final showCall = ValueNotifier(true);
    addTearDown(showCall.dispose);
    await pumpApp(
      tester,
      page: ValueListenableBuilder<bool>(
        valueListenable: showCall,
        builder: (context, shown, child) => shown
            ? const CallSurface(child: Text('the call'))
            : const Text('elsewhere'),
      ),
    );
    await joinChannel(tester);
    await tester.pump();
    expect(miniPlayer, findsNothing);

    showCall.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.text('elsewhere'), findsOneWidget);
    expect(miniPlayer, findsOneWidget);

    showCall.value = true;
    await tester.pump();
    await tester.pump();
    expect(miniPlayer, findsNothing);
    await leave(tester);
  });

  testWidgets('a page covered by another does not count as showing it', (
    tester,
  ) async {
    await pumpApp(tester);
    await joinChannel(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    // The call page is open: the mini player stays away.
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) =>
              const Scaffold(body: CallSurface(child: Text('the call'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(miniPlayer, findsNothing);

    // Another page opens on top of it: the call is out of sight.
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => const Scaffold(body: Text('settings')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(miniPlayer, findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(miniPlayer, findsNothing);
    await leave(tester);
  });

  testWidgets('mutes and leaves from the window', (tester) async {
    await pumpApp(tester);
    await joinChannel(tester);
    final call = connector.last;

    await tester.tap(find.byKey(const ValueKey('call-mini-player-mute')));
    await tester.pump();
    await tester.pump();
    expect(call.microphone, isFalse);
    expect(container.read(voiceSessionProvider)?.selfMute, isTrue);
    expect(find.byTooltip('Unmute'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('call-mini-player-mute')));
    await tester.pump();
    await tester.pump();
    expect(call.microphone, isTrue);

    await tester.tap(find.byKey(const ValueKey('call-mini-player-leave')));
    await tester.pump();
    await tester.pump();
    expect(call.disconnects, 1);
    expect(container.read(voiceSessionProvider), isNull);
    expect(miniPlayer, findsNothing);
  });

  testWidgets('tapping it returns to the call', (tester) async {
    await pumpApp(tester);
    await joinChannel(tester);

    await tester.tap(find.byKey(const ValueKey('call-mini-player-open')));
    await tester.pump();
    expect(opened?.channelId, 'ch-lounge');
    await leave(tester);
  });

  testWidgets('dragging moves it to the nearest corner', (tester) async {
    await pumpApp(tester);
    await joinChannel(tester);
    final start = tester.getTopLeft(windowKey);

    // Pick it up by its picture and drop it near the top left.
    final grab = tester.getCenter(windowKey) - const Offset(40, 0);
    final gesture = await tester.startGesture(grab);
    // The first move only starts the drag.
    await gesture.moveBy(const Offset(-20, -20));
    await gesture.moveBy(const Offset(-120, -300));
    await tester.pump();
    expect(tester.getTopLeft(windowKey), isNot(start));
    await gesture.moveBy(const Offset(-120, -300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final rect = tester.getRect(windowKey);
    expect(rect.left, 12);
    expect(rect.top, lessThan(100));
    await leave(tester);
  });

  testWidgets('a drag past the screen edge stays on screen', (tester) async {
    await pumpApp(tester);
    await joinChannel(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(windowKey) - const Offset(40, 0),
    );
    await gesture.moveBy(const Offset(20, 20));
    await gesture.moveBy(const Offset(900, 900));
    await tester.pump();
    final dragged = tester.getRect(windowKey);
    expect(dragged.right, lessThanOrEqualTo(400));
    expect(dragged.bottom, lessThanOrEqualTo(800));
    await gesture.up();
    await tester.pumpAndSettle();
    await leave(tester);
  });

  testWidgets('with reduced motion it jumps to the corner', (tester) async {
    await pumpApp(tester, disableAnimations: true);
    await joinChannel(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(windowKey) - const Offset(40, 0),
    );
    await gesture.moveBy(const Offset(-20, -20));
    await gesture.moveBy(const Offset(-250, -500));
    await gesture.up();
    // One frame: no spring to wait for.
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(windowKey).left, 12);
    await leave(tester);
  });

  testWidgets('screen readers can move it to a corner', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await joinChannel(tester);

    final withActions = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.customSemanticsActions?.length ?? 0) == 4,
    );
    final node = tester.getSemantics(withActions);
    final data = node.getSemanticsData();
    final byLabel = {
      for (final id in data.customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)!.label!: id,
    };
    expect(byLabel.keys, contains('Move to top left'));

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      byLabel['Move to top left'],
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(windowKey).dx, 12);
    expect(tester.getTopLeft(windowKey).dy, lessThan(100));
    handle.dispose();
    await leave(tester);
  });

  testWidgets('it is a little bigger on a wide window', (tester) async {
    await pumpApp(tester, size: const Size(1400, 900));
    await joinChannel(tester);

    expect(tester.getSize(windowKey), miniPlayerSize(wide: true));
    await leave(tester);
  });
}
