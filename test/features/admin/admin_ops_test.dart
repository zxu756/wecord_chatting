import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/admin/admin_console_screen.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'admin_ops_fakes.dart';

Future<void> _open(
  WidgetTester tester,
  FakeOpsBackend backend, {
  String tab = 'flags',
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: backend.overrides,
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: AdminConsoleScreen(now: () => DateTime.utc(2026, 10, 20, 10)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('admin-tab-$tab')));
  await tester.pumpAndSettle();
}

void main() {
  group('the console tabs', () {
    testWidgets('five tabs, reports first, and each one opens', (tester) async {
      final backend = FakeOpsBackend();
      await _open(tester, backend, tab: 'audit');
      for (final tab in ['reports', 'audit', 'flags', 'notices', 'feedback']) {
        expect(find.byKey(ValueKey('admin-tab-$tab')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('admin-tab-notices')));
      await tester.pumpAndSettle();
      expect(find.text('No notices yet.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin-tab-feedback')));
      await tester.pumpAndSettle();
      expect(find.text('No open feedback.'), findsOneWidget);
    });
  });

  group('flags', () {
    testWidgets('the owner sees the minimum versions and the flags', (
      tester,
    ) async {
      final backend = FakeOpsBackend()
        ..minVersions = {'web': '1.2.0'}
        ..flags = [
          flagJson(
            'new_chat',
            description: 'The new chat header',
            percent: 25,
            allow: ['ada'],
            minVersion: '1.3.0',
          ),
          flagJson('old_thing', enabled: false),
        ];
      await _open(tester, backend);
      expect(find.text('Minimum version'), findsOneWidget);
      expect(find.text('1.2.0'), findsOneWidget);
      expect(find.text('No minimum'), findsWidgets);
      expect(find.text('new_chat'), findsOneWidget);
      expect(find.text('The new chat header'), findsOneWidget);
      expect(find.text('25% of people'), findsOneWidget);
      expect(find.text('Allow list: 1'), findsOneWidget);
      expect(find.text('Needs 1.3.0'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-flag-new')), findsOneWidget);
    });

    testWidgets('a moderator reads but cannot change anything', (tester) async {
      final backend = FakeOpsBackend(role: 'moderator')
        ..flags = [flagJson('new_chat')];
      await _open(tester, backend);
      expect(find.text('new_chat'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-flag-new')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('admin-flag-new_chat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-flag-save')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('admin-minver-web')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('admin-minver-save')), findsNothing);
    });

    testWidgets('a new flag is saved with the usernames split', (tester) async {
      final backend = FakeOpsBackend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-flag-new')));
      await tester.pumpAndSettle();
      // Nothing can be saved without a key.
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('admin-flag-save')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-flag-key')),
        'new_chat',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-flag-percent')),
        '40',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-flag-allow')),
        '@ada, bob  cy',
      );
      await tester.tap(find.byKey(const ValueKey('admin-flag-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-flag-save')));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_set_feature_flag'), [
        {
          'flag_key': 'new_chat',
          'flag_description': '',
          'flag_enabled': true,
          'flag_rollout_percent': 40,
          'allow_usernames': ['ada', 'bob', 'cy'],
          'flag_min_version': '',
        },
      ]);
    });

    testWidgets('a percentage over 100 cannot be saved', (tester) async {
      final backend = FakeOpsBackend()..flags = [flagJson('new_chat')];
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-flag-new_chat')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('admin-flag-percent')),
        '101',
      );
      await tester.pumpAndSettle();
      expect(find.text('A number from 0 to 100.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin-flag-save')));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_set_feature_flag'), isEmpty);
    });

    testWidgets('deleting a flag asks first', (tester) async {
      final backend = FakeOpsBackend()..flags = [flagJson('new_chat')];
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-flag-new_chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-flag-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this flag?'), findsOneWidget);
      expect(backend.calls('admin_delete_feature_flag'), isEmpty);
      await tester.tap(find.text('Delete flag'));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_delete_feature_flag'), [
        {'flag_key': 'new_chat'},
      ]);
    });

    testWidgets('a minimum version is confirmed before it locks people out', (
      tester,
    ) async {
      final backend = FakeOpsBackend();
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-minver-web')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('admin-minver-field')),
        'soon',
      );
      await tester.pumpAndSettle();
      expect(find.text('The version looks like 1.2.3.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('admin-minver-field')),
        '1.4.0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-minver-save')));
      await tester.pumpAndSettle();
      expect(find.text('Lock out older versions?'), findsOneWidget);
      expect(backend.calls('admin_set_min_version'), isEmpty);
      await tester.tap(find.text('Set minimum'));
      await tester.pumpAndSettle();
      expect(backend.calls('admin_set_min_version'), [
        {'client_platform': 'web', 'minimum': '1.4.0'},
      ]);
      // The list is read again.
      expect(find.text('1.4.0'), findsOneWidget);
    });

    testWidgets('taking a minimum away needs no second question', (
      tester,
    ) async {
      final backend = FakeOpsBackend()..minVersions = {'ios': '2.0.0'};
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-minver-ios')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('admin-minver-field')),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-minver-save')));
      await tester.pumpAndSettle();
      expect(find.text('Lock out older versions?'), findsNothing);
      expect(backend.calls('admin_set_min_version'), [
        {'client_platform': 'ios', 'minimum': ''},
      ]);
    });

    testWidgets('the server\'s refusal is shown', (tester) async {
      final backend = FakeOpsBackend();
      backend.failures['admin_set_feature_flag'] = PostgrestException(
        message: 'Some of those usernames do not exist',
        code: '22023',
      );
      await _open(tester, backend);
      await tester.tap(find.byKey(const ValueKey('admin-flag-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('admin-flag-key')),
        'new_chat',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-flag-save')));
      await tester.pumpAndSettle();
      expect(find.text('Some of those usernames do not exist'), findsOneWidget);
    });
  });

  group('notices', () {
    testWidgets('lists the notices with how many read them', (tester) async {
      final backend = FakeOpsBackend()
        ..notices = [
          noticeJson('n1', push: true, pushDone: true),
          noticeJson(
            'n2',
            titleEn: 'Old news',
            retractedAt: '2026-10-19T09:00:00Z',
          ),
        ];
      await _open(tester, backend, tab: 'notices');
      expect(find.text('Maintenance tonight'), findsOneWidget);
      expect(find.text('Push sent'), findsOneWidget);
      expect(find.text('Taken back'), findsOneWidget);
      expect(find.textContaining('read by 12'), findsWidgets);
      // Only the notice that is still up can be taken back.
      expect(
        find.byKey(const ValueKey('admin-notice-retract-n1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('admin-notice-retract-n2')),
        findsNothing,
      );
    });

    testWidgets('a moderator publishes in both languages with one push', (
      tester,
    ) async {
      final backend = FakeOpsBackend(role: 'moderator');
      await _open(tester, backend, tab: 'notices');
      await tester.tap(find.byKey(const ValueKey('admin-notice-new')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WeCordButton>(
              find.byKey(const ValueKey('admin-notice-publish')),
            )
            .onPressed,
        isNull,
        reason: 'a notice needs a title',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-notice-title-en')),
        'New terms',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-notice-body-en')),
        'We changed the terms.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-notice-title-zh')),
        '新的条款',
      );
      await tester.enterText(
        find.byKey(const ValueKey('admin-notice-body-zh')),
        '我们更新了条款。',
      );
      await tester.tap(find.byKey(const ValueKey('admin-notice-push')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-notice-publish')));
      await tester.pumpAndSettle();
      expect(find.text('Publish to everybody?'), findsOneWidget);
      expect(backend.calls('admin_publish_announcement'), isEmpty);
      await tester.tap(find.text('Publish').last);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_publish_announcement'), [
        {
          'title_en': 'New terms',
          'title_zh': '新的条款',
          'body_en': 'We changed the terms.',
          'body_zh': '我们更新了条款。',
          'send_push': true,
        },
      ]);
    });

    testWidgets('support staff only read', (tester) async {
      final backend = FakeOpsBackend(role: 'support')
        ..notices = [noticeJson('n1')];
      await _open(tester, backend, tab: 'notices');
      expect(find.text('Maintenance tonight'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin-notice-new')), findsNothing);
      expect(
        find.byKey(const ValueKey('admin-notice-retract-n1')),
        findsNothing,
      );
    });

    testWidgets('a second push in a day is refused and says why', (
      tester,
    ) async {
      final backend = FakeOpsBackend();
      backend.failures['admin_publish_announcement'] = PostgrestException(
        message: 'A push was already sent in the last 24 hours',
        code: '53400',
      );
      await _open(tester, backend, tab: 'notices');
      await tester.tap(find.byKey(const ValueKey('admin-notice-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('admin-notice-title-en')),
        'More news',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-notice-publish')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish').last);
      await tester.pumpAndSettle();
      expect(
        find.text('A push was already sent in the last 24 hours'),
        findsOneWidget,
      );
    });

    testWidgets('taking a notice back asks first', (tester) async {
      final backend = FakeOpsBackend()..notices = [noticeJson('n1')];
      await _open(tester, backend, tab: 'notices');
      await tester.tap(find.byKey(const ValueKey('admin-notice-retract-n1')));
      await tester.pumpAndSettle();
      expect(find.text('Take this notice back?'), findsOneWidget);
      expect(backend.calls('admin_retract_announcement'), isEmpty);
      await tester.tap(find.text('Take back').last);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_retract_announcement'), [
        {'target_announcement_id': 'n1'},
      ]);
    });
  });

  group('feedback', () {
    testWidgets('lists the open feedback; the filters change the list', (
      tester,
    ) async {
      final backend = FakeOpsBackend(role: 'support')
        ..feedback = [
          feedbackJson('f1', screenshot: true),
          feedbackJson(
            'f2',
            username: 'bob',
            message: 'Dark mode please',
            status: 'closed',
            repliedAt: '2026-10-20T09:30:00Z',
          ),
        ];
      await _open(tester, backend, tab: 'feedback');
      expect(find.text('The send button is hidden'), findsOneWidget);
      expect(find.text('Dark mode please'), findsNothing);
      expect(find.text('Screenshot'), findsOneWidget);
      expect(find.textContaining('@ada · web 1.4.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('admin-feedback-closed')));
      await tester.pumpAndSettle();
      expect(find.text('Dark mode please'), findsOneWidget);
      expect(find.text('Answered'), findsOneWidget);
      expect(
        backend.calls('admin_list_feedback').last['status_filter'],
        'closed',
      );
    });

    testWidgets('a reply goes to the person and closes the feedback', (
      tester,
    ) async {
      final backend = FakeOpsBackend(role: 'support')
        ..feedback = [feedbackJson('f1', screenshot: true)];
      backend.details['f1'] = feedbackDetailJson(
        'f1',
        screenshotPath: 'user-ada/shot.jpg',
        replies: [
          {
            'id': 'r0',
            'body': 'Looking into it.',
            'published_at': '2026-10-20T09:10:00Z',
            'retracted_at': null,
          },
        ],
      );
      await _open(tester, backend, tab: 'feedback');
      await tester.tap(find.byKey(const ValueKey('admin-feedback-item-f1')));
      await tester.pumpAndSettle();
      expect(find.text('The send button is hidden'), findsOneWidget);
      expect(find.text('Looking into it.'), findsOneWidget);
      // The screenshot link is asked for, for the path stored with it.
      expect(backend.signedPaths, ['user-ada/shot.jpg']);

      // Nothing to send until something is written.
      final send = find.byKey(const ValueKey('admin-feedback-send'));
      await tester.ensureVisible(send);
      await tester.pumpAndSettle();
      expect(tester.widget<WeCordButton>(send).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('admin-feedback-reply')),
        'Thanks, fixed in 1.4.1.',
      );
      await tester.pumpAndSettle();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_reply_feedback'), [
        {
          'target_feedback_id': 'f1',
          'reply_text': 'Thanks, fixed in 1.4.1.',
          'close_after': true,
        },
      ]);
    });

    testWidgets('a reply can leave the feedback open', (tester) async {
      final backend = FakeOpsBackend(role: 'support')
        ..feedback = [feedbackJson('f1')];
      backend.details['f1'] = feedbackDetailJson('f1');
      await _open(tester, backend, tab: 'feedback');
      await tester.tap(find.byKey(const ValueKey('admin-feedback-item-f1')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('admin-feedback-close-after'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.enterText(
        find.byKey(const ValueKey('admin-feedback-reply')),
        'Can you tell me more?',
      );
      await tester.pumpAndSettle();
      final send = find.byKey(const ValueKey('admin-feedback-send'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        backend.calls('admin_reply_feedback').single['close_after'],
        false,
      );
    });

    testWidgets('feedback can be closed without a reply and opened again', (
      tester,
    ) async {
      final backend = FakeOpsBackend()..feedback = [feedbackJson('f1')];
      backend.details['f1'] = feedbackDetailJson('f1');
      await _open(tester, backend, tab: 'feedback');
      await tester.tap(find.byKey(const ValueKey('admin-feedback-item-f1')));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('admin-feedback-toggle'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Close without replying'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(backend.calls('admin_close_feedback'), [
        {'target_feedback_id': 'f1', 'closed': true},
      ]);
    });
  });
}
