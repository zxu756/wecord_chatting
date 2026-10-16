// Renders the time tokens, group events, group clean-up and data export
// screens on a phone and a desktop, light and dark, with real fonts, and
// writes PNGs for eyeballing. Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/misc_features_screenshots_test.dart \
//     --dart-define=MISC_SCREENS_DIR=build/misc-features
//
// Pick screens with --dart-define=MISC_ONLY=time,events.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'MISC_SCREENS_DIR',
  defaultValue: 'build/misc-features',
);
const _only = String.fromEnvironment('MISC_ONLY');

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
    String group,
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      _Variant variant,
    )
    open,
  ) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          world.extraOverrides = [
            timeTokenFollowsClockProvider.overrideWithValue(false),
          ];
          await open(tester, world, variant);
          await shoot(tester, '$name-${variant.name}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  Future<void> openDirect(WidgetTester tester, PhoneWorld world) async {
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
  }

  // ------------------------------------------------------- time tokens

  List<ChatMessage> timeMessages() {
    final soon = TimeToken.fromDateTime(
      DateTime.now().add(const Duration(hours: 2, minutes: 5)),
    );
    final dinner = TimeToken.fromDateTime(
      DateTime.now().add(const Duration(days: 2, hours: 4)),
      TimeTokenStyle.longDateTime,
    );
    final countdown = TimeToken.fromDateTime(
      DateTime.now().add(const Duration(hours: 30)),
      TimeTokenStyle.relative,
    );
    return [
      phoneMessage(
        't1',
        bart,
        'Are we still on for the climbing gym at ${soon.markup}?',
        minutesAgo: 20,
      ),
      phoneMessage(
        't2',
        me,
        'Yes! And dinner after, ${dinner.markup}. Booking closes ${countdown.markup}.',
        minutesAgo: 18,
      ),
      phoneMessage(
        't3',
        bart,
        'Perfect, I will add it to my calendar.',
        minutesAgo: 17,
      ),
    ];
  }

  screen('time', 'time1-message', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
  });

  screen('time', 'time2-details', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
    await tester.tapOnText(find.textRange.ofSubstring('in 2 hours'));
    await settle(tester);
  });

  screen('time', 'time3-suggestion', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
    await tester.enterText(
      find.byType(EditableText).last,
      'see you tomorrow 8pm at the gym',
    );
    await tester.pump(const Duration(milliseconds: 500));
  });

  screen('time', 'time4-insert', (tester, world, variant) async {
    world.chats.messages = timeMessages();
    await openDirect(tester, world);
    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await settle(tester);
    await tester.tap(find.text('Insert time'));
    await settle(tester);
  });
}
