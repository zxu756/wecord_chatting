// Feature flags and the minimum version (K4), official notices (K6) and
// Feedback and help (K7), for the accessibility guard (guidelines_test.dart)
// and the accessibility screenshot tool: the admin console's Flags, Notices
// and Feedback tabs with their dialogs and a piece of feedback, the Official
// card and filter in Notifications, the Feedback and help page with a
// screenshot, the "Please update" page and the What's new popup.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';
import 'package:wecord/features/announcements/whats_new_content.dart';
import 'package:wecord/features/announcements/whats_new_host.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show ChatImageUpload;
import 'package:wecord/features/feature_flags/feature_flags_models.dart';
import 'package:wecord/features/feature_flags/feature_flags_providers.dart';
import 'package:wecord/features/feature_flags/feature_flags_repository.dart';
import 'package:wecord/features/feedback/feedback_repository.dart';
import 'package:wecord/features/feedback/feedback_screen.dart';

import '../features/admin/admin_ops_fakes.dart';
import '../features/announcements/announcement_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

/// A small PNG, stretched by the preview.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAEElEQVR4nGMIqDgBRwzEcQCC0hkBcFCiJwAAAABJRU5ErkJggg==',
);

class _Ok implements FeedbackRepository {
  @override
  Future<void> submit({
    required String message,
    required String platform,
    required String version,
    Uint8List? screenshot,
  }) async {}
}

class _FlagsRepository implements FeatureFlagsRepository {
  const _FlagsRepository(this.snapshot);

  final FeatureFlagSnapshot snapshot;

  @override
  Future<FeatureFlagSnapshot> fetch({
    required String platform,
    required String version,
  }) async => snapshot;
}

/// A backend with a few flags, notices and pieces of feedback.
FakeOpsBackend opsShowcaseBackend({String role = 'owner'}) {
  final backend = FakeOpsBackend(role: role)
    ..minVersions = {'web': '1.2.0', 'ios': '1.3.0'}
    ..flags = [
      flagJson(
        'new_chat_header',
        description: 'The new header of a chat',
        percent: 25,
        allow: ['ada', 'bob'],
        minVersion: '1.3.0',
      ),
      flagJson(
        'voice_rooms',
        description: 'Voice rooms in groups',
        percent: 100,
      ),
      flagJson('old_search', enabled: false, percent: 0),
    ]
    ..notices = [
      noticeJson('n1', push: true, pushDone: true),
      noticeJson(
        'n2',
        titleEn: 'New terms of service',
        titleZh: '新的服务条款',
        bodyEn: 'We changed the terms. Read them in Settings, About WeCord.',
        read: 40,
        dismissed: 5,
        publishedAt: '2026-10-18T09:00:00Z',
      ),
      noticeJson(
        'n3',
        titleEn: 'Typo, sorry',
        retractedAt: '2026-10-17T09:30:00Z',
        publishedAt: '2026-10-17T09:00:00Z',
      ),
    ]
    ..feedback = [
      feedbackJson('f1', screenshot: true),
      feedbackJson(
        'f2',
        username: 'bob',
        message:
            'Could the font be bigger in the chat list? I read it '
            'without glasses and cannot.',
        platform: 'ios',
        version: '1.3.2',
        createdAt: '2026-10-19T09:00:00Z',
      ),
    ];
  backend.details['f1'] = feedbackDetailJson(
    'f1',
    screenshotPath: 'user-ada/shot.jpg',
    replies: [
      {
        'id': 'r1',
        'body': 'Thanks, we can reproduce it. Looking into it.',
        'published_at': '2026-10-20T09:30:00Z',
        'retracted_at': null,
      },
    ],
  );
  return backend;
}

Future<void> _openConsoleTab(
  WidgetTester tester,
  PhoneWorld world,
  String tab, {
  String role = 'owner',
}) async {
  world.extraOverrides = opsShowcaseBackend(role: role).callOverrides;
  await world.open(tester, '/admin');
  final chip = find.byKey(ValueKey('admin-tab-$tab'));
  // (The tabs scroll sideways on a phone.)
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

FakeAnnouncementsRepository _announcements() => FakeAnnouncementsRepository([
  notice('n1'),
  notice(
    'n2',
    titleEn: 'New terms of service',
    titleZh: '新的服务条款',
    bodyEn: 'We changed the terms. Read them in Settings, About WeCord.',
    read: true,
    publishedAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  notice(
    'n3',
    kind: AnnouncementKind.feedbackReply,
    titleEn: 'Reply to your feedback',
    titleZh: '对你反馈的回复',
    bodyEn: 'Thanks, fixed in 1.4.1.',
    bodyZh: 'Thanks, fixed in 1.4.1.',
  ),
]);

Future<void> _openFeedbackPage(WidgetTester tester, PhoneWorld world) async {
  world.imagePicker.nextImage = ChatImageUpload(
    bytes: _png,
    fileName: 'screen.png',
    mimeType: 'image/png',
  );
  world.extraOverrides = [
    feedbackScreenshotPreparerProvider.overrideWithValue(
      (bytes, name) async => Uint8List.fromList(bytes),
    ),
  ];
  await world.open(tester, '/me');
  final row = find.byKey(const ValueKey('settings-feedback'));
  await tester.scrollUntilVisible(
    row,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
  await tester.tap(row);
  await settle(tester);
}

final adminOpsA11yScreens = <A11yScreen>[
  A11yScreen('admin-flags', (tester, world) async {
    await _openConsoleTab(tester, world, 'flags');
  }),
  A11yScreen('admin-flags-edit', (tester, world) async {
    await _openConsoleTab(tester, world, 'flags');
    final flag = find.byKey(const ValueKey('admin-flag-new_chat_header'));
    await tester.scrollUntilVisible(
      flag,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('admin-flags-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(flag);
    await settle(tester);
  }),
  A11yScreen('admin-flags-minimum', (tester, world) async {
    await _openConsoleTab(tester, world, 'flags');
    await tester.tap(find.byKey(const ValueKey('admin-minver-web')));
    await settle(tester);
  }),
  A11yScreen('admin-flags-moderator', (tester, world) async {
    await _openConsoleTab(tester, world, 'flags', role: 'moderator');
  }),
  A11yScreen('admin-notices', (tester, world) async {
    await _openConsoleTab(tester, world, 'notices');
  }),
  A11yScreen('admin-notices-compose', (tester, world) async {
    await _openConsoleTab(tester, world, 'notices');
    await tester.tap(find.byKey(const ValueKey('admin-notice-new')));
    await settle(tester);
  }),
  A11yScreen('admin-feedback', (tester, world) async {
    await _openConsoleTab(tester, world, 'feedback', role: 'support');
  }),
  A11yScreen('admin-feedback-detail', (tester, world) async {
    await _openConsoleTab(tester, world, 'feedback', role: 'support');
    await tester.tap(find.byKey(const ValueKey('admin-feedback-item-f1')));
    await settle(tester);
  }),
  A11yScreen('inbox-official', (tester, world) async {
    world.extraOverrides = [
      announcementsRepositoryProvider.overrideWithValue(_announcements()),
    ];
    await world.open(tester, '/notifications');
  }),
  A11yScreen('inbox-official-filter', (tester, world) async {
    world.extraOverrides = [
      announcementsRepositoryProvider.overrideWithValue(_announcements()),
    ];
    await world.open(tester, '/notifications');
    final chip = find.byKey(const ValueKey('inbox-filter-official'));
    await tester.ensureVisible(chip);
    await settle(tester);
    await tester.tap(chip);
    await settle(tester);
  }),
  A11yScreen('settings-feedback-row', (tester, world) async {
    world.extraOverrides = const [];
    await world.open(tester, '/me');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-feedback')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
  }),
  A11yScreen('feedback-page', _openFeedbackPage),
  A11yScreen('feedback-page-screenshot', (tester, world) async {
    await _openFeedbackPage(tester, world);
    await tester.enterText(
      find.byKey(FeedbackScreen.messageKey),
      'The send button is hidden behind the keyboard on my phone.',
    );
    await tester.tap(find.byKey(FeedbackScreen.addScreenshotKey));
    await settle(tester);
  }),
  A11yScreen('feedback-page-sent', (tester, world) async {
    world.extraOverrides = [
      feedbackRepositoryProvider.overrideWithValue(_Ok()),
    ];
    await world.open(tester, '/me');
    final row = find.byKey(const ValueKey('settings-feedback'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(row);
    await settle(tester);
    await tester.enterText(find.byKey(FeedbackScreen.messageKey), 'It works!');
    await tester.pump();
    await tester.tap(find.byKey(FeedbackScreen.sendKey));
    await settle(tester);
  }),
  A11yScreen('update-required', (tester, world) async {
    world.extraOverrides = [
      appVersionProvider.overrideWithValue('1.0.0'),
      featureFlagsRepositoryProvider.overrideWithValue(
        const _FlagsRepository(FeatureFlagSnapshot(minVersion: '2.0.0')),
      ),
    ];
    await world.open(tester, '/notifications');
  }),
  A11yScreen('whats-new', (tester, world) async {
    WhatsNewHost.checkedThisRun = false;
    world.extraOverrides = [
      appVersionProvider.overrideWithValue('2.0.0'),
      whatsNewStoreProvider.overrideWithValue(InMemoryWhatsNewStore('1.0.0')),
      whatsNewEntriesProvider.overrideWithValue(const [
        WhatsNewEntry(
          version: '2.0.0',
          title: WhatsNewText('What is new in WeCord', 'WeCord 有什么新功能'),
          items: [
            WhatsNewText(
              'Auto-translate: read a chat in your own language.',
              '自动翻译：用你自己的语言阅读聊天。',
            ),
            WhatsNewText(
              'Your own stickers, from any picture.',
              '自己的表情，任何图片都能做。',
            ),
            WhatsNewText('Feedback and help in Settings.', '设置里新增反馈与帮助。'),
          ],
        ),
      ]),
    ];
    await world.open(tester, '/notifications');
    await settle(tester);
  }),
  A11yScreen(
    'desktop-admin-flags',
    (tester, world) async {
      await _openConsoleTab(tester, world, 'flags');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-admin-notices',
    (tester, world) async {
      await _openConsoleTab(tester, world, 'notices');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-admin-feedback-detail',
    (tester, world) async {
      await _openConsoleTab(tester, world, 'feedback', role: 'support');
      await tester.tap(find.byKey(const ValueKey('admin-feedback-item-f1')));
      await settle(tester);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-inbox-official',
    (tester, world) async {
      world.extraOverrides = [
        announcementsRepositoryProvider.overrideWithValue(_announcements()),
      ];
      await world.open(tester, '/notifications');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
