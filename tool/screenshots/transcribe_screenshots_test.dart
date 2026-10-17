// Renders transcribing voice messages (the button, progress, the text, an
// error, the "not here" note, the Apple-servers question, a circle channel
// and the Settings switch) on a phone and a desktop, light and dark, with
// real fonts and a fake transcriber, and writes PNGs for eyeballing. Not part
// of `flutter test`; run it with:
//
//   flutter test tool/screenshots/transcribe_screenshots_test.dart \
//     --dart-define=TRANSCRIBE_SCREENS_DIR=build/transcribe
//
// Pick screens with --dart-define=TRANSCRIBE_ONLY=done,error.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/ai/ai_fakes.dart';
import '../../test/features/transcribe/transcribe_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'TRANSCRIBE_SCREENS_DIR',
  defaultValue: 'build/transcribe',
);
const _only = String.fromEnvironment('TRANSCRIBE_ONLY');

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

class _Variant {
  const _Variant(this.name, this.viewport, this.dark);

  final String name;
  final PhoneViewport viewport;
  final bool dark;

  bool get desktop => viewport == _desktop;
}

const _variants = [
  _Variant('phone-light', notchedPhone, false),
  _Variant('phone-dark', notchedPhone, true),
  _Variant('desktop-light', _desktop, false),
  _Variant('desktop-dark', _desktop, true),
];

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  final only = _only.isEmpty ? null : _only.split(',').toSet();

  void screen(
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      FakeVoiceTranscriber transcriber,
      _Variant variant,
    )
    open, {
    bool ai = false,
  }) {
    if (only != null && !only.contains(name)) {
      return;
    }
    for (final variant in _variants) {
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final transcriber = FakeVoiceTranscriber()
            ..text =
                'Hey, are we still on for lunch tomorrow? I was thinking '
                'the noodle place near the station, around noon.';
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          world.extraOverrides = [
            ...transcribeOverrides(transcriber),
            // The catch-up offer would sit over the voice message.
            if (ai) aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
            aiEnabledStoreProvider.overrideWithValue(InMemoryAiEnabledStore()),
          ];
          await open(tester, world, transcriber, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  Future<void> tapTranscribe(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('voice-transcribe-button')).first,
    );
    await settle(tester);
  }

  screen('idle', (tester, world, transcriber, variant) async {
    await openDirect(tester, world);
  });

  screen('loading', (tester, world, transcriber, variant) async {
    transcriber.gate = Completer<void>();
    await openDirect(tester, world);
    await tester.tap(
      find.byKey(const ValueKey('voice-transcribe-button')).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
  });

  screen('done', (tester, world, transcriber, variant) async {
    await openDirect(tester, world);
    await tapTranscribe(tester);
  });

  screen('error', (tester, world, transcriber, variant) async {
    transcriber.error = const TranscribeException(
      TranscribeFailureKind.notAuthorized,
    );
    await openDirect(tester, world);
    await tapTranscribe(tester);
  });

  screen('unavailable', (tester, world, transcriber, variant) async {
    transcriber.planValue = const TranscribePlan.unavailable(
      TranscribeUnavailable.platform,
    );
    await openDirect(tester, world);
    await tapTranscribe(tester);
  });

  screen('apple-consent', (tester, world, transcriber, variant) async {
    transcriber.planValue = const TranscribePlan.engine(
      TranscribeEngine.appleServer,
    );
    await openDirect(tester, world);
    await tapTranscribe(tester);
  });

  screen('channel', (tester, world, transcriber, variant) async {
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    await tapTranscribe(tester);
  });

  screen('message-menu', (tester, world, transcriber, variant) async {
    await openDirect(tester, world);
    final voice = find.byKey(const ValueKey('voice-transcribe-button')).first;
    if (variant.desktop) {
      await tester.tap(voice, buttons: kSecondaryButton);
    } else {
      await tester.longPress(voice);
    }
    await settle(tester);
  });

  screen('settings', (tester, world, transcriber, variant) async {
    await world.open(tester, '/me');
    if (variant.desktop) {
      await tester.tap(find.byKey(const ValueKey('settings-nav-ai')));
    } else {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('auto-transcribe-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await settle(tester);
  }, ai: true);
}
