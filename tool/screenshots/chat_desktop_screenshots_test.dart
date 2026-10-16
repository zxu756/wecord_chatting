// Renders the chat thread on a 1440x900 desktop (a direct message and a
// circle channel) with real fonts and writes PNGs, for eyeballing design
// language C. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/chat_desktop_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=/some/output/dir
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=PHONE_SCREENS_ZH=true for the Chinese interface.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../test/mobile/phone_test_support.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/chat-desktop',
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(_loadFonts);

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

  void screen(
    String name,
    Future<void> Function(WidgetTester tester, PhoneWorld world) open,
  ) {
    testWidgets(name, (tester) async {
      // A desktop platform: mouse hover, right-click menus.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        usePhoneViewport(tester, _desktop);
        final world = PhoneWorld();
        await open(tester, world);
        await shoot(tester, name);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
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

  Future<void> openChannel(WidgetTester tester, PhoneWorld world) async {
    world.chats.messages = richMessages(withThread: true);
    // The circle workspace: channel sidebar, the channel, members.
    await world.open(tester, '/circles/circle-1');
  }

  Future<void> hover(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(finder.first));
    await settle(tester);
  }

  screen('d1-direct-message', (tester, world) async {
    await openDirect(tester, world);
  });

  screen('d2-direct-message-hover', (tester, world) async {
    await openDirect(tester, world);
    await hover(tester, find.textContaining('Forwarding', findRichText: true));
  });

  screen('d3-direct-message-context-menu', (tester, world) async {
    await openDirect(tester, world);
    final message = find.textContaining('Also this', findRichText: true);
    await tester.tap(message.first, buttons: kSecondaryButton);
  });

  screen('d4-channel', (tester, world) async {
    await openChannel(tester, world);
  });

  screen('d5-channel-hover', (tester, world) async {
    await openChannel(tester, world);
    await hover(tester, find.textContaining('Forwarding', findRichText: true));
  });

  screen('d6-channel-older', (tester, world) async {
    await openChannel(tester, world);
    await tester.drag(
      find.byKey(const ValueKey('chat-message-list')),
      const Offset(0, 600),
    );
  });

  screen('d7-attach-menu', (tester, world) async {
    await openDirect(tester, world);
    await tester.tap(find.byTooltip(tr('Attach')));
  });
}

/// Loads the app font, a Chinese font under the fallback names, emoji and
/// the Material icons (the same set as phone_screenshots_test.dart).
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
