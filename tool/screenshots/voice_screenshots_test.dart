// Renders the voice screens (stage, soundboard, participant menu, voice
// settings, a desktop voice channel) with real fonts and writes PNGs. Not
// part of `flutter test`; run it like the phone screenshots:
//
//   flutter test tool/screenshots/voice_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=PHONE_SCREENS_ZH=true for the Chinese interface. The
// voice channel, call and incoming call screens are in
// phone_screenshots_test.dart (36*, 37*).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/soundboard_repository.dart';
import 'package:wecord/features/voice/stage_repository.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_sound.dart';
import 'package:wecord/shared/models/voice.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../test/features/voice/voice_fakes.dart';
import '../../test/mobile/phone_test_support.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/phone-screens',
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(_loadFonts);
  // Standalone screens skip the app, which sets the language.
  setUp(
    () => AppStrings.isChinese = const bool.fromEnvironment('PHONE_SCREENS_ZH'),
  );

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

  const audienceNames = [
    'Kai',
    'Rin',
    'Tao',
    'Leo',
    'Jun',
    'Mika',
    'Sora',
    'Noor',
    'Ines',
    'Theo',
    'Yuki',
    'Omar',
  ];

  /// A live stage: three speakers (one talking, one muted), the current
  /// user and twelve more in the audience, one with a raised hand.
  List<VoiceMemberState> stageMembers({bool meSpeaking = false}) => [
    voiceMember(
      userId: me.id,
      name: me.displayName,
      channelId: 'ch-stage',
      stageSpeaker: meSpeaking,
    ),
    voiceMember(
      userId: bart.id,
      name: 'Bart',
      channelId: 'ch-stage',
      stageSpeaker: true,
    ),
    voiceMember(
      userId: grace.id,
      name: 'Grace',
      channelId: 'ch-stage',
      stageSpeaker: true,
      selfMute: true,
    ),
    voiceMember(
      userId: linus.id,
      name: 'Linus',
      channelId: 'ch-stage',
      stageSpeaker: true,
    ),
    voiceMember(
      userId: 'user-30',
      name: 'Zhou',
      channelId: 'ch-stage',
      handRaisedAt: DateTime.utc(2026, 10, 16, 9),
    ),
    for (var i = 0; i < audienceNames.length; i++)
      voiceMember(
        userId: 'user-${40 + i}',
        name: audienceNames[i],
        channelId: 'ch-stage',
      ),
  ];

  final stages = _ScreenshotStageRepository()
    ..live['ch-stage'] = StageInstance(
      channelId: 'ch-stage',
      circleId: 'circle-1',
      topic: 'Route share: the northern loop next week',
      startedAt: DateTime.utc(2026, 10, 16, 9),
    );

  final sounds = [
    for (final (index, (emoji, name)) in const [
      ('📯', 'Airhorn'),
      ('👏', 'Applause'),
      ('🥁', 'Ba dum tss'),
      ('🦗', 'Crickets'),
      ('🎺', 'Sad trombone'),
      ('🔔', 'Bell'),
      ('😂', 'Laugh track'),
      ('🐐', 'Goat'),
    ].indexed)
      CircleSound(
        id: 'sound-$index',
        circleId: 'circle-1',
        name: name,
        emoji: emoji,
        storagePath: 'circle-1/sound-$index.mp3',
        mimeType: 'audio/mpeg',
        duration: const Duration(seconds: 2),
      ),
  ];

  /// Pumps a voice channel view on its own and joins it.
  Future<void> openChannel(
    WidgetTester tester,
    PhoneWorld world, {
    required bool stage,
    bool moderator = false,
    bool join = true,
  }) async {
    world.circles.detail = circleDetailWithVoice();
    await pumpStandalone(
      tester,
      world,
      VoiceChannelView(
        circleId: 'circle-1',
        channelId: stage ? 'ch-stage' : 'ch-lounge',
        conversationId: stage ? 'conv-stage' : 'conv-lounge',
        channelName: stage ? 'Route stage' : 'Lounge',
        isStage: stage,
        stageModerator: moderator,
        canManageSounds: true,
        chatBuilder: (context) => const SizedBox.shrink(),
      ),
      extraOverrides: [
        stageRepositoryProvider.overrideWithValue(stages),
        circleSoundsProvider.overrideWith((ref, circleId) async => sounds),
      ],
    );
    if (!join) {
      return;
    }
    final container = ProviderScope.containerOf(
      tester.element(find.byType(VoiceChannelView)),
    );
    unawaited(
      container
          .read(voiceSessionProvider.notifier)
          .join(
            circleId: 'circle-1',
            channelId: stage ? 'ch-stage' : 'ch-lounge',
            conversationId: stage ? 'conv-stage' : 'conv-lounge',
            channelName: stage ? 'Route stage' : 'Lounge',
          ),
    );
    await settle(tester);
  }

  void stageWorld(PhoneWorld world, {bool speaker = false}) {
    world.voice
      ..tokenStage = true
      ..tokenStageSpeaker = speaker
      ..states['circle-1'] = stageMembers(meSpeaking: speaker);
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: 'Bart',
          isSpeaking: true,
          microphoneEnabled: true,
        ),
        VoiceCallParticipant(userId: grace.id, name: 'Grace'),
        VoiceCallParticipant(
          userId: linus.id,
          name: 'Linus',
          microphoneEnabled: true,
        ),
      ];
    };
  }

  void loungeWorld(PhoneWorld world) {
    world.voice.states['circle-1'] = [
      voiceMember(userId: me.id, name: me.displayName),
      voiceMember(userId: bart.id, name: 'Bart the Bold'),
      voiceMember(userId: grace.id, name: grace.displayName, video: true),
      voiceMember(userId: linus.id, name: 'Linus', selfDeaf: true),
    ];
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: 'Bart the Bold',
          isSpeaking: true,
          microphoneEnabled: true,
        ),
        VoiceCallParticipant(
          userId: grace.id,
          name: grace.displayName,
          microphoneEnabled: true,
          cameraEnabled: true,
          cameraView: (context) => const ColoredBox(
            color: Color(0xFF35506B),
            child: Center(
              child: Icon(Icons.person, size: 64, color: Colors.white54),
            ),
          ),
        ),
        VoiceCallParticipant(userId: linus.id, name: 'Linus'),
      ];
    };
  }

  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open, {
    PhoneViewport viewport = notchedPhone,
  }) {
    testWidgets(name, (tester) async {
      usePhoneViewport(tester, viewport);
      final world = PhoneWorld();
      await open(tester, world);
      await shoot(tester, name);
      // Leave the call so its timers stop.
      final views = find.byType(VoiceChannelView);
      if (views.evaluate().isNotEmpty) {
        await ProviderScope.containerOf(
          tester.element(views.first),
        ).read(voiceSessionProvider.notifier).leave();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  }

  screen('v1-stage-listener', (tester, world) async {
    stageWorld(world);
    await openChannel(tester, world, stage: true, moderator: true);
  });

  screen('v1b-stage-speaker', (tester, world) async {
    stageWorld(world, speaker: true);
    await openChannel(tester, world, stage: true);
  });

  screen('v2-stage-lobby', (tester, world) async {
    stageWorld(world);
    world.voice.states['circle-1'] = stageMembers().skip(1).toList();
    await openChannel(tester, world, stage: true, join: false);
  });

  screen('v3-soundboard', (tester, world) async {
    loungeWorld(world);
    await openChannel(tester, world, stage: false);
    await tester.tap(find.byKey(const ValueKey('voice-control-soundboard')));
  });

  screen('v4-participant-menu', (tester, world) async {
    loungeWorld(world);
    await openChannel(tester, world, stage: false);
    await tester.longPress(find.byKey(ValueKey('voice-tile-${bart.id}')));
  });

  screen('v5-voice-settings', (tester, world) async {
    world.voiceSettings.saved = const VoiceSettings(
      userVolumes: {'user-2': 1.4, 'user-3': 0.6},
    );
    await pumpStandalone(tester, world, const VoiceSettingsScreen());
  });

  screen('v6-voice-hold-to-talk', (tester, world) async {
    world.voiceSettings.saved = const VoiceSettings(
      inputMode: VoiceInputMode.pushToTalk,
    );
    await openChannel(tester, world, stage: false);
  });

  screen('d1-voice-channel', viewport: _desktop, (tester, world) async {
    loungeWorld(world);
    world.circles.detail = circleDetailWithVoice();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
  });

  screen('d2-voice-channel-chat', viewport: _desktop, (tester, world) async {
    loungeWorld(world);
    world.circles.detail = circleDetailWithVoice();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
    );
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('voice-chat-button')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('voice-tile-${bart.id}')), buttons: 2);
  });

  screen('d3-stage', viewport: _desktop, (tester, world) async {
    stageWorld(world);
    await openChannel(tester, world, stage: true, moderator: true);
  });
}

class _ScreenshotStageRepository implements StageRepository {
  final live = <String, StageInstance>{};

  @override
  Future<Map<String, StageInstance>> listStages(String circleId) async =>
      Map.of(live);

  @override
  Stream<void> stageChanges(String circleId) => const Stream.empty();

  @override
  Future<void> startStage({
    required String channelId,
    required String topic,
  }) async {}

  @override
  Future<List<String>> endStage(String channelId) async => const [];

  @override
  Future<void> setHandRaised({
    required String channelId,
    required bool raised,
  }) async {}

  @override
  Future<bool> inviteToSpeak({
    required String channelId,
    required String userId,
  }) async => true;

  @override
  Future<bool> respondToInvite({
    required String channelId,
    required bool accept,
  }) async => accept;

  @override
  Future<void> moveToAudience({
    required String channelId,
    required String userId,
  }) async {}
}

/// Loads Roboto and the Material icons from the Flutter SDK, the app's own
/// font, and system fonts for Chinese and emoji (as the phone screenshots
/// do).
Future<void> _loadFonts() async {
  final fonts = _materialFontsDir();
  final roboto = FontLoader('Roboto');
  const unicodeFont = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  if (const bool.fromEnvironment('PHONE_SCREENS_ZH') &&
      File(unicodeFont).existsSync()) {
    roboto.addFont(_fontData(unicodeFont));
  } else {
    for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
      roboto.addFont(_fontData('${fonts.path}/Roboto-$weight.ttf'));
    }
  }
  await roboto.load();

  final jakarta = FontLoader(WeCordTheme.fontFamily)
    ..addFont(
      _fontData('assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf'),
    );
  await jakarta.load();
  final cjkFont = [
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
    unicodeFont,
  ].where((path) => File(path).existsSync()).firstOrNull;
  const emojiFont = '/System/Library/Fonts/Apple Color Emoji.ttc';
  for (final family in WeCordTheme.fontFamilyFallback) {
    final file = family.contains('Emoji') ? emojiFont : cjkFont;
    if (file != null && File(file).existsSync()) {
      final fallback = FontLoader(family)..addFont(_fontData(file));
      await fallback.load();
    }
  }

  final icons = FontLoader('MaterialIcons')
    ..addFont(_fontData('${fonts.path}/MaterialIcons-Regular.otf'));
  await icons.load();

  if (File(emojiFont).existsSync()) {
    final emoji = FontLoader('Apple Color Emoji')
      ..addFont(_fontData(emojiFont));
    await emoji.load();
  }
}

Future<ByteData> _fontData(String path) async {
  final bytes = File(path).readAsBytesSync();
  return ByteData.sublistView(bytes);
}

Directory _materialFontsDir() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dir = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
    if (dir.existsSync()) {
      return dir;
    }
  }
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path) {
    final candidate = Directory('${dir.path}/material_fonts');
    if (candidate.existsSync()) {
      return candidate;
    }
    dir = dir.parent;
  }
  throw StateError('Could not find the Flutter SDK material fonts.');
}
