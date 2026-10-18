// The message report and policy screens, for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: the Report entry in the
// message menu and its sheet, the circle's Review queue with user reports,
// the admin console's Messages tab, the three policy pages, the sign-up
// agreement, the prompt for existing accounts and the About page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_layout.dart' show AuthLink;
import 'package:wecord/features/auth/auth_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_review_screen.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/legal/about_screen.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/admin/admin_fakes.dart';
import '../features/circles/ai_guard_fakes.dart';
import '../features/reports/report_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';
import 'admin_a11y_screens.dart' show adminShowcaseBackend;

/// Reports for the Review queue, with an AI-guarded message under them.
List<Override> reviewQueueOverrides() {
  final reports = FakeReportRpc()
    ..results['list_circle_message_reports'] = [
      circleReportJson(
        reason: 'unsafe_content',
        details: 'He sends the same link to everybody who joins.',
        repeat: 3,
      ),
      circleReportJson(
        id: 'report-2',
        reason: 'harassment',
        body: 'nobody wants you here, just leave',
        reporter: 'Grace',
        createdAt: '2026-10-20T09:00:00Z',
      ),
    ];
  final guard = FakeGuardRpc()
    ..results['count_message_reviews'] = 3
    ..results['list_message_reviews'] = [reviewJson()];
  return [
    ...reports.overrides,
    circleAiGuardRepositoryProvider.overrideWithValue(
      CircleAiGuardRepository(guard),
    ),
  ];
}

/// Answers the terms status calls: nothing on record yet.
Future<Object?> _termsRpc(String name, Map<String, dynamic> params) async {
  if (name == 'get_my_terms_status') {
    return {'accepted_terms_at': null, 'age_confirmed_at': null};
  }
  throw StateError('Supabase must be initialized first.');
}

Future<void> _openThread(
  WidgetTester tester,
  PhoneWorld world, {
  bool circle = false,
}) async {
  world.chats.messages = richMessages();
  if (circle) {
    await world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    return;
  }
  await world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

/// The long-press (or, on the desktop, right-click) menu of one of Bart's
/// messages.
Future<void> openReportMessageMenu(
  WidgetTester tester,
  PhoneWorld world, {
  bool circle = false,
  bool desktop = false,
}) async {
  await _openThread(tester, world, circle: circle);
  final message = find.textContaining('Forwarding', findRichText: true).first;
  if (desktop) {
    await tester.tap(message, buttons: 2);
  } else {
    await tester.longPress(message);
  }
  await settle(tester);
}

/// The Report sheet, opened from that menu.
Future<void> openReportMessageSheet(
  WidgetTester tester,
  PhoneWorld world, {
  bool circle = false,
  bool desktop = false,
}) async {
  await openReportMessageMenu(tester, world, circle: circle, desktop: desktop);
  await tester.tap(find.byKey(const ValueKey('message-report')));
  await settle(tester);
}

/// The admin console's Messages tab with one report opened.
Future<void> openAdminMessageReport(
  WidgetTester tester,
  PhoneWorld world,
) async {
  final backend = adminShowcaseBackend()
    ..reports = [
      ...adminShowcaseBackend().reports,
      adminReportJson(
        'r-msg',
        kind: 'message',
        reason: 'harassment',
        title: 'send me your password or else',
        createdAt: '2026-10-20T11:45:00Z',
      ),
    ];
  backend.details['r-msg'] = adminDetailJson('r-msg', kind: 'message');
  world.extraOverrides = backend.callOverrides;
  await world.open(tester, '/admin');
  await tester.tap(find.byKey(const ValueKey('admin-kind-message')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('admin-report-r-msg')));
  await settle(tester);
}

final reportsLegalA11yScreens = <A11yScreen>[
  A11yScreen('report-message-menu', (tester, world) async {
    await openReportMessageMenu(tester, world);
  }),
  A11yScreen('report-message-sheet', (tester, world) async {
    await openReportMessageSheet(tester, world);
  }),
  A11yScreen('report-message-sheet-circle', (tester, world) async {
    await openReportMessageSheet(tester, world, circle: true);
  }),
  A11yScreen('circle-review-reports', (tester, world) async {
    await pumpStandalone(
      tester,
      world,
      CircleReviewScreen(
        circleId: 'circle-1',
        now: () => DateTime.utc(2026, 10, 20, 12),
      ),
      extraOverrides: reviewQueueOverrides(),
    );
  }),
  A11yScreen('admin-report-message', openAdminMessageReport),
  A11yScreen('legal-terms', (tester, world) async {
    await pumpStandalone(
      tester,
      world,
      const LegalDocumentScreen(document: LegalDocument.terms),
    );
  }),
  A11yScreen('legal-privacy', (tester, world) async {
    await pumpStandalone(
      tester,
      world,
      const LegalDocumentScreen(document: LegalDocument.privacy),
    );
  }),
  A11yScreen('legal-guidelines', (tester, world) async {
    await pumpStandalone(
      tester,
      world,
      const LegalDocumentScreen(document: LegalDocument.guidelines),
    );
  }),
  A11yScreen('signup-terms', (tester, world) async {
    await pumpStandalone(tester, world, const AuthScreen());
    // The footer link sits under the phone's home indicator; press it
    // directly.
    tester
        .widget<AuthLink>(find.byKey(const ValueKey('auth-toggle-mode')))
        .onPressed!();
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('terms-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terms-checkbox')));
    await settle(tester);
  }),
  A11yScreen('terms-prompt', (tester, world) async {
    world.extraOverrides = [circleRpcProvider.overrideWithValue(_termsRpc)];
    await world.open(tester, '/home');
  }),
  A11yScreen('about', (tester, world) async {
    await pumpStandalone(tester, world, const AboutScreen(version: '0.1.0'));
  }),
  A11yScreen('settings-about-row', (tester, world) async {
    await world.open(tester, '/me');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-about')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen(
    'report-message-sheet-desktop',
    (tester, world) => openReportMessageSheet(tester, world, desktop: true),
    viewport: desktopViewport,
    desktop: true,
  ),
];
