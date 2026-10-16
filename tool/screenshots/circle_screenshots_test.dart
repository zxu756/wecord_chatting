// Renders the circle screens (design language C) with real fonts and
// writes PNGs, for eyeballing them. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/circle_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir \
//     --dart-define=DESKTOP_SCREENS_DIR=/some/desktop/dir
//
// Phone shots (390x844) go to PHONE_SCREENS_DIR (build/circle-screens by
// default), desktop shots (1440x900) to DESKTOP_SCREENS_DIR
// (build/circle-screens/desktop). Add --dart-define=PHONE_SCREENS_DARK=true
// for the dark theme and --dart-define=PHONE_SCREENS_ZH=true for Chinese.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../test/features/voice/voice_fakes.dart';
import '../../test/mobile/phone_test_support.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/circle-screens',
);

const _desktopDir = String.fromEnvironment(
  'DESKTOP_SCREENS_DIR',
  defaultValue: 'build/circle-screens/desktop',
);

const _desktop = PhoneViewport(
  name: '1440x900',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(WidgetTester tester, String path) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
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
      final dir = identical(viewport, _desktop) ? _desktopDir : _outputDir;
      await shoot(tester, '$dir/$name.png');
    });
  }

  void desktop(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) => screen(name, open, viewport: _desktop);

  Future<void> fromMenu(WidgetTester tester, String label) async {
    await tester.tap(_tooltip('Circle menu'));
    await settle(tester);
    await tester.ensureVisible(_text(label));
    await settle(tester);
    await tester.tap(_text(label));
    await settle(tester);
  }

  void withVoice(PhoneWorld world) {
    world.circles.detail = circleDetailWithVoice();
    world.voice.states['circle-1'] = [
      voiceMember(
        userId: bart.id,
        name: bart.displayName,
        nickname: 'Bart the Bold',
        roleColor: 0x3498DB,
      ),
      voiceMember(userId: grace.id, name: grace.displayName),
      voiceMember(userId: linus.id, name: 'Linus'),
    ];
    world.voiceCalls.prepare = (call) {
      call.remotes = [
        VoiceCallParticipant(
          userId: bart.id,
          name: 'Bart the Bold',
          isSpeaking: true,
        ),
        VoiceCallParticipant(userId: grace.id, name: grace.displayName),
        VoiceCallParticipant(userId: linus.id, name: 'Linus'),
      ];
    };
  }

  // Phone.

  screen('01-circle-home', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  });

  screen('01b-circle-home-small', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
  }, viewport: smallPhone);

  screen('02-circle-voice-live-card', (tester, world) async {
    withVoice(world);
    await world.open(tester, '/circles/circle-1');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('circle-channel-row-ch-lounge')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
  });

  screen('03-circle-menu', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_tooltip('Circle menu'));
  });

  screen('04-members-sheet', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_text('general'));
    await settle(tester);
    await tester.tap(_tooltip('Show member list'));
  });

  screen('05-invite-sheet', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Invite friends');
  });

  screen('06-add-circle', (tester, world) async {
    await world.open(tester, '/home');
    await tester.tap(find.byKey(const ValueKey('circle-rail-add')));
  });

  screen('07-create-circle', (tester, world) async {
    await world.open(tester, '/home');
    await tester.tap(find.byKey(const ValueKey('circle-rail-add')));
    await settle(tester);
    await tester.tap(_text('Create a circle'));
  });

  screen('08-category-dialog', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Create category');
  });

  screen('09-circle-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Circle settings');
  });

  screen('10-roles', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Roles');
  });

  screen('11-channel-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_text('general'));
    await settle(tester);
    await tester.tap(_tooltip('More'));
    await settle(tester);
    await tester.tap(_text('Channel settings'));
  });

  screen('12-events', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
  });

  screen('13-automod', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'AutoMod');
  });

  screen('14-audit-log', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Audit log');
  });

  screen('15-emoji', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Emoji & stickers');
  });

  screen('16-notification-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Notification settings');
  });

  screen('17-forum', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.scrollUntilVisible(
      _text('help-and-questions'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(_text('help-and-questions'));
  });

  screen('18-bans', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Bans');
  });

  // Desktop.

  desktop('d1-circle-channel', (tester, world) async {
    withVoice(world);
    await world.open(tester, '/circles/circle-1');
  });

  desktop('d2-circle-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Circle settings');
  });

  desktop('d3-roles', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Roles');
  });

  desktop('d4-circle-menu', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_tooltip('Circle menu'));
  });

  desktop('d5-category-dialog', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await fromMenu(tester, 'Create category');
  });

  desktop('d6-channel-settings', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(_tooltip('Channel settings'));
  });

  desktop('d7-events', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
  });
}

/// Loads Roboto and the Material icons from the Flutter SDK, so text is not
/// drawn as boxes, plus the system emoji font where there is one.
Future<void> _loadFonts() async {
  final fonts = _materialFontsDir();
  final roboto = FontLoader('Roboto');
  // The test engine doesn't fall back to other fonts, so Chinese shots
  // draw everything with a font that has both Latin and Chinese.
  const unicodeFont = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  if (const bool.fromEnvironment('PHONE_SCREENS_ZH') &&
      File(unicodeFont).existsSync()) {
    roboto.addFont(_fontData(unicodeFont));
  } else {
    for (final weight in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
      roboto.addFont(_fontData('${fonts.path}/Roboto-$weight.ttf'));
    }
    roboto.addFont(_fontData('${fonts.path}/Roboto-Italic.ttf'));
  }
  await roboto.load();

  // The app's own font, and a Chinese font under the names the theme falls
  // back to for characters it lacks.
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

  // Code blocks ask for "monospace"; borrow a system mono font.
  const monoFont = '/System/Library/Fonts/Supplemental/Courier New.ttf';
  if (File(monoFont).existsSync()) {
    final mono = FontLoader('monospace')..addFont(_fontData(monoFont));
    await mono.load();
  }

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
  // flutter_tester lives under bin/cache/artifacts/engine/<platform>/.
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

// With PHONE_SCREENS_ZH the app shows Chinese, so look the English labels
// up through tr() (data such as names and messages stays as it is).
Finder _text(String text) => find.text(tr(text));

Finder _tooltip(String message) => find.byTooltip(tr(message));
