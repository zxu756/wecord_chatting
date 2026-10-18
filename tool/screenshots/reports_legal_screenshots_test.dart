// Renders the message report and policy screens with real fonts and writes
// PNGs for eyeballing: the Report entry in the message menu and its sheet,
// the circle's Review queue with user reports, the admin console's Messages
// tab and a message report, the three policy pages, the sign-up agreement,
// the prompt for existing accounts and the About page, on a phone (390x844)
// and on the desktop (1440x900). Not part of `flutter test`; run it with:
//
//   flutter test tool/screenshots/reports_legal_screenshots_test.dart
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme (files end in
// -dark) and --dart-define=PHONE_SCREENS_ZH=true for Chinese. The folder is
// build/reports-legal unless REPORTS_LEGAL_DIR says otherwise.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_layout.dart' show AuthLink;
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/legal/about_screen.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart' show WeCordButton;

import '../../test/accessibility/admin_a11y_screens.dart'
    show adminShowcaseBackend;
import '../../test/accessibility/reports_legal_a11y_screens.dart';
import '../../test/features/admin/admin_fakes.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'REPORTS_LEGAL_DIR',
  defaultValue: 'build/reports-legal',
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
    Future<void> Function(WidgetTester tester, PhoneWorld world, bool desktop)
    body, {
    bool phone = true,
    bool desktop = true,
  }) {
    for (final wide in [false, true]) {
      if (wide ? !desktop : !phone) {
        continue;
      }
      testWidgets('$name${wide ? '-desktop' : '-phone'}', (tester) async {
        AppStrings.isChinese = _zh;
        addTearDown(() => AppStrings.isChinese = false);
        if (wide) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, wide ? _desktop : notchedPhone);
          final world = PhoneWorld()
            ..themeMode = _dark ? ThemeMode.dark : ThemeMode.light;
          await body(tester, world, wide);
          await shoot(tester, '$name-${wide ? 'desktop' : 'phone'}');
          await world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  screen('01-message-menu', (tester, world, wide) async {
    await openReportMessageMenu(tester, world, desktop: wide);
  });

  screen('02-report-sheet', (tester, world, wide) async {
    await openReportMessageSheet(tester, world, desktop: wide);
  });

  screen('03-report-sheet-details', (tester, world, wide) async {
    await openReportMessageSheet(tester, world, desktop: wide);
    await tester.tap(find.byKey(const ValueKey('report-reason-harassment')));
    await tester.enterText(
      find.byKey(const ValueKey('report-details')),
      'He keeps sending the same insult to everyone in the channel.',
    );
    await tester.tap(find.byKey(const ValueKey('report-also-block')));
    await settle(tester);
  });

  screen('04-report-sheet-circle', (tester, world, wide) async {
    await openReportMessageSheet(tester, world, circle: true, desktop: wide);
  });

  screen('05-review-queue', (tester, world, wide) async {
    await pumpStandalone(
      tester,
      world,
      CircleReviewScreen(
        circleId: 'circle-1',
        now: () => DateTime.utc(2026, 10, 20, 12),
      ),
      extraOverrides: reviewQueueOverrides(),
    );
  });

  screen('06-review-queue-context', (tester, world, wide) async {
    await pumpStandalone(
      tester,
      world,
      CircleReviewScreen(
        circleId: 'circle-1',
        now: () => DateTime.utc(2026, 10, 20, 12),
      ),
      extraOverrides: reviewQueueOverrides(),
    );
    await tester.tap(find.byKey(const ValueKey('report-toggle-context')).first);
    await settle(tester);
  });

  screen('07-admin-messages-tab', (tester, world, wide) async {
    final backend = adminShowcaseBackend()
      ..reports = [
        adminReportJson(
          'r-msg',
          kind: 'message',
          reason: 'harassment',
          title: 'send me your password or else',
          createdAt: '2026-10-20T11:45:00Z',
        ),
        adminReportJson(
          'r-msg2',
          kind: 'message',
          reason: 'spam',
          title: 'Win a free phone, click here',
          repeat: 2,
          createdAt: '2026-10-20T10:20:00Z',
        ),
      ];
    world.extraOverrides = backend.callOverrides;
    await world.open(tester, '/admin');
    await tester.tap(find.byKey(const ValueKey('admin-kind-message')));
    await settle(tester);
  });

  screen('08-admin-message-report', (tester, world, wide) async {
    await openAdminMessageReport(tester, world);
  });

  screen('09-admin-message-report-actions', (tester, world, wide) async {
    await openAdminMessageReport(tester, world);
    await tester.drag(
      find.byKey(const ValueKey('admin-report-detail')),
      const Offset(0, -2000),
    );
    await settle(tester);
  });

  for (final document in LegalDocument.values) {
    screen('10-legal-${document.slug}', (tester, world, wide) async {
      await pumpStandalone(
        tester,
        world,
        LegalDocumentScreen(document: document),
      );
    });
  }

  screen('11-signup-agreement', (tester, world, wide) async {
    await pumpStandalone(tester, world, const AuthScreen());
    tester
        .widget<AuthLink>(find.byKey(const ValueKey('auth-toggle-mode')))
        .onPressed!();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
    await settle(tester);
  });

  screen('12-signup-agreement-unticked', (tester, world, wide) async {
    await pumpStandalone(tester, world, const AuthScreen());
    tester
        .widget<AuthLink>(find.byKey(const ValueKey('auth-toggle-mode')))
        .onPressed!();
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('auth-username')),
      'ada_l',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-display-name')),
      'Ada Lovelace',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-email')),
      'ada@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password')),
      'password123',
    );
    // The button sits under the phone's home indicator; press it directly.
    tester
        .widget<WeCordButton>(find.byKey(const ValueKey('auth-submit')))
        .onPressed!();
    await settle(tester);
  });

  screen('13-terms-prompt', (tester, world, wide) async {
    world.extraOverrides = [
      circleRpcProvider.overrideWithValue(
        (name, params) async => name == 'get_my_terms_status'
            ? {'accepted_terms_at': null, 'age_confirmed_at': null}
            : throw StateError('Supabase must be initialized first.'),
      ),
    ];
    await world.open(tester, '/home');
  });

  screen('14-about', (tester, world, wide) async {
    await pumpStandalone(tester, world, const AboutScreen(version: '0.1.0'));
  });

  screen('15-settings-about-row', (tester, world, wide) async {
    await world.open(tester, '/me');
    if (!wide) {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-about')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
  }, desktop: false);
}
