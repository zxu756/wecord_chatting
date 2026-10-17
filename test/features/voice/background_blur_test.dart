import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/background/video_background.dart';
import 'package:wecord/features/voice/background/video_background_native.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRepository repository;
  late FakeVoiceCallConnector connector;
  late InMemoryVoiceSettingsStore store;
  late ProviderContainer container;

  setUp(() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    store = InMemoryVoiceSettingsStore();
  });

  Future<void> pumpCall(
    WidgetTester tester, {
    VideoBackgroundSupport support = VideoBackgroundSupport.inApp,
  }) async {
    connector.backgroundSupport = support;
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceRepositoryProvider.overrideWithValue(repository),
          voiceCallConnectorProvider.overrideWithValue(connector),
          voiceSettingsStoreProvider.overrideWithValue(store),
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
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: VoiceCallControls(session: session),
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
    // Lets the saved settings load.
    await tester.pump();
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

  Finder blurButton() => find.byKey(const ValueKey('voice-control-blur'));

  Future<void> cameraOn(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('voice-control-camera')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> leave(WidgetTester tester) async {
    await container.read(voiceSessionProvider.notifier).leave();
    await tester.pump();
  }

  group('where it is offered', () {
    testWidgets('not at all where the device cannot blur', (tester) async {
      await pumpCall(tester, support: VideoBackgroundSupport.none);
      await cameraOn(tester);
      expect(connector.last.camera, isTrue);
      expect(blurButton(), findsNothing);
      await leave(tester);
    });

    testWidgets('only while the camera is on', (tester) async {
      await pumpCall(tester);
      expect(blurButton(), findsNothing);
      await cameraOn(tester);
      expect(blurButton(), findsOneWidget);
      expect(find.byTooltip('Blur background'), findsOneWidget);
      await cameraOn(tester);
      expect(blurButton(), findsNothing);
      await leave(tester);
    });
  });

  group('WeCord blurs the camera (browsers)', () {
    testWidgets('the button blurs and unblurs, and remembers', (tester) async {
      await pumpCall(tester);
      await cameraOn(tester);

      await tester.tap(blurButton());
      await tester.pump();
      await tester.pump();
      expect(connector.last.blur, isTrue);
      expect(container.read(voiceSessionProvider)?.backgroundBlur, isTrue);
      expect(store.saved?.backgroundBlur, isTrue);
      expect(find.byTooltip('Turn off background blur'), findsOneWidget);

      await tester.tap(blurButton());
      await tester.pump();
      await tester.pump();
      expect(connector.last.blur, isFalse);
      expect(store.saved?.backgroundBlur, isFalse);
      expect(find.byTooltip('Blur background'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a call starts with the blur chosen before', (tester) async {
      store.saved = const VoiceSettings(backgroundBlur: true);
      await pumpCall(tester);

      // Before the camera is on, so it starts blurred.
      expect(connector.last.blur, isTrue);
      await cameraOn(tester);
      expect(container.read(voiceSessionProvider)?.backgroundBlur, isTrue);
      expect(find.byTooltip('Turn off background blur'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('a blur that cannot start leaves the camera off', (
      tester,
    ) async {
      store.saved = const VoiceSettings(backgroundBlur: true);
      await pumpCall(tester);
      connector.last.blurError = const BackgroundBlurUnavailable();

      await cameraOn(tester);

      // Never sent unblurred: the camera stayed off, and says why.
      expect(connector.last.camera, isFalse);
      expect(container.read(voiceSessionProvider)?.video, isFalse);
      expect(
        find.text('Could not blur the background, so the camera stayed off.'),
        findsOneWidget,
      );
      // The blur is off now, so the next try starts the camera plainly.
      expect(container.read(voiceSessionProvider)?.backgroundBlur, isFalse);
      expect(store.saved?.backgroundBlur, isFalse);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pump();
      await cameraOn(tester);
      expect(connector.last.camera, isTrue);
      expect(container.read(voiceSessionProvider)?.video, isTrue);
      await leave(tester);
    });

    testWidgets('switching the blur on a running camera that fails', (
      tester,
    ) async {
      await pumpCall(tester);
      await cameraOn(tester);
      connector.last.blurError = const BackgroundBlurUnavailable();

      await tester.tap(blurButton());
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Could not blur the background, so the camera stayed off.'),
        findsOneWidget,
      );
      expect(container.read(voiceSessionProvider)?.backgroundBlur, isFalse);
      await leave(tester);
    });
  });

  group('the system blurs the camera (iOS, macOS)', () {
    testWidgets('the button opens the system\'s video effects', (tester) async {
      await pumpCall(tester, support: VideoBackgroundSupport.system);
      await cameraOn(tester);

      expect(find.byTooltip('Video effects'), findsOneWidget);
      await tester.tap(blurButton());
      await tester.pump();
      await tester.pump();
      expect(connector.last.systemEffectsShown, 1);
      // It is the system that blurs; nothing is remembered here.
      expect(store.saved?.backgroundBlur ?? false, isFalse);
      await leave(tester);
    });

    testWidgets('shows whether the system\'s blur is on', (tester) async {
      await pumpCall(tester, support: VideoBackgroundSupport.system);
      await cameraOn(tester);
      expect(container.read(voiceSessionProvider)?.backgroundBlur, isFalse);

      connector.last
        ..blur = true
        ..update();
      await tester.pump();
      expect(container.read(voiceSessionProvider)?.backgroundBlur, isTrue);
      await leave(tester);
    });
  });

  group('settings', () {
    test('the choice is saved with the other voice settings', () {
      const settings = VoiceSettings(backgroundBlur: true);
      expect(settings.toJson()['background_blur'], isTrue);
      expect(VoiceSettings.fromJson(settings.toJson()).backgroundBlur, isTrue);
      expect(
        const VoiceSettings().toJson().containsKey('background_blur'),
        isFalse,
      );
      expect(
        VoiceSettings.fromJson(const <String, dynamic>{}).backgroundBlur,
        isFalse,
      );
      expect(settings == const VoiceSettings(), isFalse);
    });
  });

  group('the Apple side', () {
    const channel = MethodChannel('wecord/video_effects');

    void answer(Future<Object?> Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    test('a camera with the Portrait effect offers the system blur', () async {
      answer((call) async => {'supported': true, 'enabled': true});
      const effects = AppleVideoEffects();
      expect(await effects.detect(), VideoBackgroundSupport.system);
      expect(await effects.systemBlurEnabled(), isTrue);
      expect(effects.createBlurProcessor(), isNull);
    });

    test(
      'without it, or without the native side, nothing is offered',
      () async {
        answer((call) async => {'supported': false, 'enabled': false});
        expect(
          await const AppleVideoEffects().detect(),
          VideoBackgroundSupport.none,
        );
        answer(null);
        expect(
          await const AppleVideoEffects().detect(),
          VideoBackgroundSupport.none,
        );
        expect(await const AppleVideoEffects().systemBlurEnabled(), isFalse);
        // Opening the effects without the native side does nothing.
        await const AppleVideoEffects().showSystemEffects();
      },
    );

    test('showing the effects asks the native side', () async {
      final calls = <String>[];
      answer((call) async {
        calls.add(call.method);
        return true;
      });
      await const AppleVideoEffects().showSystemEffects();
      expect(calls, ['show']);
    });

    test('other platforms have no effects', () async {
      expect(
        await const NoVideoBackgroundEffects().detect(),
        VideoBackgroundSupport.none,
      );
      expect(const NoVideoBackgroundEffects().createBlurProcessor(), isNull);
      // On the desktop the tests run on, the platform has none either.
      expect(
        await platformVideoBackgroundEffects().detect(),
        VideoBackgroundSupport.none,
      );
    });
  });
}
