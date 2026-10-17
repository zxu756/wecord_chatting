import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/screen_zoom/zoom_pan_viewer.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'voice_fakes.dart';

void main() {
  group('zooming a shared screen', () {
    late TransformationController transform;
    var focuses = 0;
    final zoomedChanges = <bool>[];

    setUp(() {
      transform = TransformationController();
      focuses = 0;
      zoomedChanges.clear();
    });

    tearDown(() => transform.dispose());

    Future<void> pumpViewer(WidgetTester tester, {bool focus = true}) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 225,
                child: ZoomPanViewer(
                  controller: transform,
                  onFocus: focus ? () => focuses++ : null,
                  onZoomedChanged: zoomedChanges.add,
                  child: const ColoredBox(
                    key: ValueKey('picture'),
                    color: Colors.indigo,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    double scale() => transform.value.getMaxScaleOnAxis();

    Future<void> wheel(WidgetTester tester, double dy) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byKey(const ValueKey('picture')))),
      );
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pump();
    }

    testWidgets('starts at normal size with nothing to reset', (tester) async {
      await pumpViewer(tester);
      expect(scale(), 1);
      expect(find.byKey(const ValueKey('screen-zoom-pill')), findsNothing);
      expect(find.byKey(const ValueKey('screen-focus-button')), findsOneWidget);
    });

    testWidgets('the scroll wheel zooms in and back out', (tester) async {
      await pumpViewer(tester);
      await wheel(tester, -200);
      expect(scale(), greaterThan(1.5));
      expect(find.byKey(const ValueKey('screen-zoom-pill')), findsOneWidget);
      expect(zoomedChanges, [true]);

      // Never smaller than the picture itself.
      await wheel(tester, 2000);
      await tester.pump();
      expect(scale(), 1);
      expect(find.byKey(const ValueKey('screen-zoom-pill')), findsNothing);
      expect(zoomedChanges, [true, false]);
    });

    testWidgets('zoom stops at the maximum', (tester) async {
      await pumpViewer(tester);
      await wheel(tester, -5000);
      expect(scale(), maxScreenZoom);
      // The zoom-in button has nothing left to do.
      await tester.tap(find.byKey(const ValueKey('screen-zoom-in')));
      await tester.pumpAndSettle();
      expect(scale(), maxScreenZoom);
    });

    testWidgets('a pinch zooms', (tester) async {
      await pumpViewer(tester);
      final center = tester.getCenter(find.byKey(const ValueKey('picture')));
      final one = await tester.startGesture(center - const Offset(20, 0));
      final two = await tester.startGesture(center + const Offset(20, 0));
      await tester.pump();
      await one.moveBy(const Offset(-60, 0));
      await two.moveBy(const Offset(60, 0));
      await tester.pump();
      await one.up();
      await two.up();
      await tester.pumpAndSettle();

      expect(scale(), greaterThan(1.3));
    });

    testWidgets('dragging pans a zoomed picture, not an unzoomed one', (
      tester,
    ) async {
      await pumpViewer(tester);
      final picture = find.byKey(const ValueKey('picture'));
      await tester.drag(picture, const Offset(-80, -40));
      await tester.pumpAndSettle();
      expect(transform.value.getTranslation().x, 0);

      await wheel(tester, -400);
      final before = transform.value.getTranslation();
      await tester.drag(picture, const Offset(-60, -30));
      await tester.pumpAndSettle();
      final after = transform.value.getTranslation();
      expect(after.x, lessThan(before.x));
      expect(after.y, lessThan(before.y));
    });

    testWidgets('double-click resets a zoomed picture', (tester) async {
      await pumpViewer(tester);
      await wheel(tester, -400);
      expect(scale(), greaterThan(1));

      final picture = find.byKey(const ValueKey('screen-zoom-surface'));
      await tester.tap(picture);
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(picture);
      await tester.pumpAndSettle();

      expect(scale(), 1);
      expect(transform.value, Matrix4.identity());
    });

    testWidgets('double-click on an unzoomed picture zooms in there', (
      tester,
    ) async {
      await pumpViewer(tester);
      final picture = find.byKey(const ValueKey('screen-zoom-surface'));
      final corner = tester.getTopLeft(picture) + const Offset(40, 30);
      await tester.tapAt(corner);
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(corner);
      await tester.pumpAndSettle();

      expect(scale(), closeTo(doubleTapZoom, 0.01));
      // The spot that was tapped stays under the pointer.
      final scene = transform.toScene(const Offset(40, 30));
      expect(scene.dx, closeTo(40, 0.5));
      expect(scene.dy, closeTo(30, 0.5));
    });

    testWidgets('the buttons zoom in, out and reset', (tester) async {
      await pumpViewer(tester);
      await wheel(tester, -200);
      final start = scale();

      await tester.tap(find.byKey(const ValueKey('screen-zoom-in')));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(start * zoomStep, 0.01));
      expect(find.text('${(scale() * 100).round()}%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('screen-zoom-out')));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(start, 0.01));

      await tester.tap(find.byKey(const ValueKey('screen-zoom-reset')));
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(find.byKey(const ValueKey('screen-zoom-pill')), findsNothing);
    });

    testWidgets('keys zoom, pan and reset', (tester) async {
      await pumpViewer(tester);
      final focus = Focus.of(
        tester.element(find.byKey(const ValueKey('screen-zoom-surface'))),
      );
      focus.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      expect(scale(), closeTo(zoomStep, 0.01));
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.pumpAndSettle();
      final zoomedIn = scale();
      expect(zoomedIn, closeTo(zoomStep * zoomStep, 0.01));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(transform.value.getTranslation().x, lessThan(0));

      await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      await tester.pumpAndSettle();
      expect(scale(), lessThan(zoomedIn));

      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pumpAndSettle();
      expect(scale(), 1);
    });

    testWidgets('reduced motion jumps instead of animating', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: SizedBox(
                width: 400,
                height: 225,
                child: ZoomPanViewer(
                  controller: transform,
                  child: const ColoredBox(
                    key: ValueKey('picture'),
                    color: Colors.indigo,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await wheel(tester, -400);
      await tester.tap(find.byKey(const ValueKey('screen-zoom-reset')));
      // One frame is enough: no animation to wait for.
      await tester.pump();
      expect(scale(), 1);
    });

    testWidgets('the focus button calls back', (tester) async {
      await pumpViewer(tester);
      await tester.tap(find.byKey(const ValueKey('screen-focus-button')));
      expect(focuses, 1);
    });

    testWidgets('screen readers get zoom actions', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpViewer(tester);
      List<String> actions() {
        final data = tester
            .getSemantics(find.byType(ZoomPanViewer))
            .getSemanticsData();
        return [
          for (final id in data.customSemanticsActionIds ?? const <int>[])
            CustomSemanticsAction.getAction(id)!.label!,
        ];
      }

      expect(actions(), ['Zoom in']);
      await wheel(tester, -200);
      expect(actions(), containsAll(['Zoom in', 'Zoom out', 'Reset zoom']));
      handle.dispose();
    });
  });

  group('screens in a call', () {
    late FakeVoiceRepository repository;
    late FakeVoiceCallConnector connector;

    setUp(() {
      repository = FakeVoiceRepository();
      connector = FakeVoiceCallConnector();
    });

    Future<ProviderContainer> pumpCall(
      WidgetTester tester, {
      void Function(FakeVoiceCall call)? prepare,
      Size size = const Size(1000, 700),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      connector.prepare = prepare;
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
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, child) {
                  final session = ref.watch(voiceSessionProvider);
                  if (session == null || !session.isConnected) {
                    return const SizedBox();
                  }
                  return VoiceCallGrid(session: session, people: const {});
                },
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
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
      return container;
    }

    VoiceCallParticipant sharer() => VoiceCallParticipant(
      userId: 'user-2',
      name: 'Bart',
      screenShareEnabled: true,
      screenView: (context) =>
          const ColoredBox(key: ValueKey('bart-screen'), color: Colors.indigo),
    );

    testWidgets('a shared screen can be zoomed', (tester) async {
      final container = await pumpCall(
        tester,
        prepare: (call) => call.remotes = [sharer()],
      );

      final tile = find.byKey(const ValueKey('voice-screen-tile-user-2'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.byType(ZoomPanViewer)),
        findsOneWidget,
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(find.byKey(const ValueKey('bart-screen'))),
        ),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
      await tester.pump();
      expect(find.byKey(const ValueKey('screen-zoom-pill')), findsOneWidget);

      // While zoomed the page doesn't scroll away from the picture.
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('voice-call-grid')),
      );
      expect(scroll.physics, isA<NeverScrollableScrollPhysics>());

      await tester.tap(find.byKey(const ValueKey('screen-zoom-reset')));
      await tester.pumpAndSettle();
      final after = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('voice-call-grid')),
      );
      expect(after.physics, isNull);
      await container.read(voiceSessionProvider.notifier).leave();
    });

    testWidgets('the page scrolls again when a zoomed screen goes away', (
      tester,
    ) async {
      final container = await pumpCall(
        tester,
        prepare: (call) => call.remotes = [sharer()],
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(
          tester.getCenter(find.byKey(const ValueKey('bart-screen'))),
        ),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -300)));
      await tester.pump();
      var scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('voice-call-grid')),
      );
      expect(scroll.physics, isA<NeverScrollableScrollPhysics>());

      // They stop sharing while zoomed in.
      connector.last
        ..remotes = const [VoiceCallParticipant(userId: 'user-2', name: 'Bart')]
        ..update();
      await tester.pumpAndSettle();
      scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('voice-call-grid')),
      );
      expect(scroll.physics, isNull);

      // And a new share starts normal.
      connector.last
        ..remotes = [sharer()]
        ..update();
      await tester.pumpAndSettle();
      scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('voice-call-grid')),
      );
      expect(scroll.physics, isNull);
      await container.read(voiceSessionProvider.notifier).leave();
    });

    testWidgets('focusing a shared screen puts it large with others below', (
      tester,
    ) async {
      final container = await pumpCall(
        tester,
        prepare: (call) => call.remotes = [sharer()],
      );
      final screen = tester.getSize(
        find.byKey(const ValueKey('voice-screen-tile-user-2')),
      );

      await tester.tap(find.byKey(const ValueKey('screen-focus-button')));
      await tester.pumpAndSettle();

      final focused = tester.getSize(
        find.byKey(const ValueKey('voice-screen-tile-user-2')),
      );
      expect(focused.height, greaterThan(screen.height));
      // Everyone else sits in the strip, at the bottom.
      final strip = find.byKey(const ValueKey('voice-spotlight-strip'));
      expect(strip, findsOneWidget);
      for (final id in ['user-1']) {
        expect(
          find.descendant(
            of: strip,
            matching: find.byKey(ValueKey('voice-tile-$id')),
          ),
          findsOneWidget,
        );
      }
      expect(
        tester.getTopLeft(strip).dy,
        greaterThan(
          tester
              .getBottomLeft(
                find.byKey(const ValueKey('voice-screen-tile-user-2')),
              )
              .dy,
        ),
      );

      // Again: everyone is back.
      await tester.tap(find.byKey(const ValueKey('screen-focus-button')));
      await tester.pumpAndSettle();
      expect(strip, findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('voice-screen-tile-user-2'))),
        screen,
      );
      await container.read(voiceSessionProvider.notifier).leave();
    });

    testWidgets('tapping a person spotlights them, and tapping again lets go', (
      tester,
    ) async {
      final container = await pumpCall(
        tester,
        prepare: (call) => call.remotes = [
          const VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
          const VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
        ],
      );
      final before = tester.getSize(
        find.byKey(const ValueKey('voice-tile-user-2')),
      );

      await tester.tap(find.byKey(const ValueKey('voice-tile-user-2')));
      await tester.pumpAndSettle();
      final big = tester.getSize(
        find.byKey(const ValueKey('voice-tile-user-2')),
      );
      expect(big.width, greaterThan(before.width));
      final strip = find.byKey(const ValueKey('voice-spotlight-strip'));
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const ValueKey('voice-tile-user-3')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const ValueKey('voice-tile-user-2')),
        ),
        findsNothing,
      );

      // Another tile from the strip takes over.
      await tester.tap(find.byKey(const ValueKey('voice-tile-user-3')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: strip,
          matching: find.byKey(const ValueKey('voice-tile-user-2')),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('voice-tile-user-3')));
      await tester.pumpAndSettle();
      expect(strip, findsNothing);
      await container.read(voiceSessionProvider.notifier).leave();
    });

    testWidgets('a spotlighted person who leaves gives way to the grid', (
      tester,
    ) async {
      final container = await pumpCall(
        tester,
        prepare: (call) => call.remotes = [
          const VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('voice-tile-user-2')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('voice-spotlight-strip')),
        findsOneWidget,
      );

      final call = connector.last;
      call.remotes = const [];
      call.update();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('voice-spotlight-strip')), findsNothing);
      expect(find.byKey(const ValueKey('voice-tile-user-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await container.read(voiceSessionProvider.notifier).leave();
    });
  });
}
