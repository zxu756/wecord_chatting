// Renders the admin console with real fonts and writes PNGs for eyeballing:
// the report queue, a report of each kind, the action dialogs, the audit
// log, Settings with the admin row and the "This circle was suspended"
// state, on a phone (390x844) and on the desktop (1440x900). Not part of
// `flutter test`; run it with:
//
//   flutter test tool/screenshots/admin_screenshots_test.dart
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (files end in
// -dark) and --dart-define=PHONE_SCREENS_ZH=true for Chinese. The folder is
// build/admin unless ADMIN_SCREENS_DIR says otherwise.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../test/accessibility/admin_a11y_screens.dart'
    show adminShowcaseBackend;
import '../../test/features/admin/admin_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'ADMIN_SCREENS_DIR',
  defaultValue: 'build/admin',
);
const _dark = bool.fromEnvironment('PHONE_SCREENS_DARK');
const _zh = bool.fromEnvironment('PHONE_SCREENS_ZH');

const _desktop = PhoneViewport(
  name: '1440x900',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(loadScreenshotFonts);

  final suffix = '${_dark ? '-dark' : '-light'}${_zh ? '-zh' : ''}';

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name$suffix.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  void screen(
    String name,
    Future<void> Function(
      WidgetTester tester,
      PhoneWorld world,
      FakeAdminBackend backend,
    )
    body, {
    bool desktop = false,
    String role = 'owner',
  }) {
    testWidgets('$name${desktop ? '-desktop' : '-phone'}', (tester) async {
      AppStrings.isChinese = _zh;
      addTearDown(() => AppStrings.isChinese = false);
      usePhoneViewport(tester, desktop ? _desktop : notchedPhone);
      final backend = adminShowcaseBackend(role: role);
      final world = PhoneWorld()
        ..themeMode = _dark ? ThemeMode.dark : ThemeMode.light
        ..extraOverrides = backend.callOverrides;
      await body(tester, world, backend);
      await shoot(tester, '$name-${desktop ? 'desktop' : 'phone'}');
      await world.close(tester);
    });
  }

  Future<void> openReport(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('admin-report-$id')));
    await settle(tester);
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    final action = find.byKey(ValueKey(key));
    await tester.scrollUntilVisible(
      action,
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('admin-report-detail')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);
    await tester.tap(action);
    await settle(tester);
  }

  Future<void> scrollReport(WidgetTester tester, double dy) async {
    await tester.drag(
      find.byKey(const ValueKey('admin-report-detail')),
      Offset(0, dy),
    );
    await settle(tester);
  }

  for (final desktop in [false, true]) {
    final d = desktop;
    screen('01-queue', (tester, world, backend) async {
      await world.open(tester, '/admin');
    }, desktop: d);

    screen('02-queue-handled', (tester, world, backend) async {
      backend.reports = [
        adminReportJson(
          'r-done',
          kind: 'post',
          status: 'dismissed',
          title: 'Check out my new crypto coin',
          resolution: 'no_violation',
          handledBy: 'mia',
        ),
        adminReportJson(
          'r-done2',
          kind: 'circle',
          status: 'reviewed',
          title: 'Free Gift Cards',
          resolution: 'circle_delisted',
          handledBy: 'mia',
        ),
        adminReportJson(
          'r-done3',
          kind: 'user',
          status: 'reviewed',
          title: 'Eve Adams (@eve)',
          resolution: 'user_suspended',
          handledBy: 'root',
        ),
      ];
      await world.open(tester, '/admin');
      await tester.tap(find.byKey(const ValueKey('admin-status-handled')));
    }, desktop: d);

    screen('03-report-post', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-post');
    }, desktop: d);

    screen('04-report-post-actions', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-post');
      await scrollReport(tester, -2000);
    }, desktop: d);

    screen('05-report-circle', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-circle');
    }, desktop: d);

    screen('06-report-user', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-user');
    }, desktop: d);

    screen('07-suspend-reason', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-user');
      await tapAction(tester, 'admin-action-suspend-person');
      await tester.enterText(
        find.byKey(const ValueKey('admin-reason-field')),
        'Harassment after a warning',
      );
      await tester.pump();
    }, desktop: d);

    screen('08-suspend-confirm', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-user');
      await tapAction(tester, 'admin-action-suspend-person');
      await tester.enterText(
        find.byKey(const ValueKey('admin-reason-field')),
        'Harassment after a warning',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('admin-reason-confirm')));
      await settle(tester);
    }, desktop: d);

    screen('09-delist-reason', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await openReport(tester, 'r-circle');
      await tapAction(tester, 'admin-action-delist');
    }, desktop: d);

    screen('10-audit-log', (tester, world, backend) async {
      await world.open(tester, '/admin');
      await tester.tap(find.byKey(const ValueKey('admin-tab-audit')));
    }, desktop: d);

    screen(
      '11-support-role',
      (tester, world, backend) async {
        await world.open(tester, '/admin');
        await openReport(tester, 'r-post');
        await scrollReport(tester, -2000);
      },
      desktop: d,
      role: 'support',
    );

    screen('12-not-admin', (tester, world, backend) async {
      backend.role = null;
      await world.open(tester, '/admin');
    }, desktop: d);

    screen('13-circle-suspended', (tester, world, backend) async {
      backend.takedowns = [
        {'circle_id': 'circle-1', 'mode': 'suspend'},
      ];
      world.circles.detailError = const CircleMembershipLostException(
        'circle-1',
      );
      await world.open(tester, '/circles/circle-1');
    }, desktop: d);
  }

  screen('14-settings-row', (tester, world, backend) async {
    await world.open(tester, '/me');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-admin-console')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  });
}
