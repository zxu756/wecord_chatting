// Renders the quiet hours screens on a phone and a desktop, light and dark,
// with real fonts, and writes PNGs for eyeballing. Not part of `flutter
// test`; run it with:
//
//   flutter test tool/screenshots/quiet_hours_screenshots_test.dart \
//     --dart-define=QUIET_HOURS_SCREENS_DIR=build/quiet-hours
//
// Pick screens with --dart-define=QUIET_HOURS_ONLY=on,days,contacts, and
// Chinese with --dart-define=PHONE_SCREENS_ZH=true.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/friend_tags/friend_tags_repository.dart';
import 'package:wecord/features/notifications/quiet_hours_screen.dart';

import '../../test/features/moments/moments_fakes.dart'
    show FakeFriendTagsRepository;
import '../../test/features/notifications/quiet_hours_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'QUIET_HOURS_SCREENS_DIR',
  defaultValue: 'build/quiet-hours',
);
const _only = String.fromEnvironment('QUIET_HOURS_ONLY');

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

// Tuesday 23:30 on the clock of the device: inside the window.
final _night = DateTime(2026, 10, 20, 23, 30);

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await settle(tester);
    }
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
    Future<void> Function(WidgetTester tester, PhoneWorld world, _Variant v)
    open, {
    bool enabled = true,
    List<String> variants = const [
      'phone-light',
      'phone-dark',
      'desktop-light',
      'desktop-dark',
    ],
  }) {
    if (only != null && !only.contains(group)) {
      return;
    }
    for (final variant in _variants) {
      if (!variants.contains(variant.name)) {
        continue;
      }
      testWidgets('$name ${variant.name}', (tester) async {
        if (variant.desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, variant.viewport);
          final world = PhoneWorld()
            ..themeMode = variant.dark ? ThemeMode.dark : ThemeMode.light;
          world.extraOverrides = [
            ...quietHoursOverrides(
              repository: quietHoursServer(enabled: enabled),
              now: _night,
            ),
            friendTagsRepositoryProvider.overrideWithValue(
              FakeFriendTagsRepository(),
            ),
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    final list = find.byKey(const ValueKey('settings-page-list'));
    if (finder.evaluate().isEmpty && list.evaluate().isNotEmpty) {
      await tester.dragUntilVisible(finder, list, const Offset(0, -150));
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> openQuiet(
    WidgetTester tester,
    PhoneWorld world,
    _Variant variant,
  ) async {
    await pumpStandalone(tester, world, const QuietHoursScreen());
  }

  screen('off', 'quiet-hours-off', openQuiet, enabled: false);
  screen('on', 'quiet-hours-on', openQuiet);
  screen('on', 'quiet-hours-on-lower', (tester, world, variant) async {
    await openQuiet(tester, world, variant);
    final list = find.byKey(const ValueKey('settings-page-list'));
    await tester.drag(list, const Offset(0, -900));
    await settle(tester);
  }, variants: const ['phone-light', 'phone-dark']);
  screen('days', 'quiet-hours-days', (tester, world, variant) async {
    await openQuiet(tester, world, variant);
    await tapKey(tester, 'quiet-hours-days');
  });
  screen('contacts', 'quiet-hours-contacts', (tester, world, variant) async {
    await openQuiet(tester, world, variant);
    await tapKey(tester, 'quiet-hours-contacts');
  });

  screen('settings', 'settings-notifications', (tester, world, variant) async {
    await world.open(tester, '/me');
    if (variant.desktop) {
      await tester.tap(find.text('Notifications').last);
      await settle(tester);
    } else {
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('quiet-hours-tile')),
        find.byKey(const ValueKey('settings-page-list')),
        const Offset(0, -150),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('quiet-hours-tile')),
      );
      await settle(tester);
    }
  });

  screen('profile', 'friend-profile', (tester, world, variant) async {
    await world.open(tester, '/profile/user-2');
    final row = find.byKey(const ValueKey('profile-important'));
    final scrollable = find.byType(Scrollable).first;
    if (row.evaluate().isEmpty) {
      await tester.dragUntilVisible(row, scrollable, const Offset(0, -150));
    }
    await tester.ensureVisible(row);
    await settle(tester);
  });

  screen('home', 'home-with-moon', (tester, world, variant) async {
    await world.open(tester, '/home');
  });
}
