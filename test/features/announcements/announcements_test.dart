import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/announcements/announcement_card.dart';
import 'package:wecord/features/announcements/announcement_models.dart';
import 'package:wecord/features/announcements/announcements_providers.dart';
import 'package:wecord/features/announcements/announcements_repository.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import 'announcement_fakes.dart';

Widget _card(FakeAnnouncementsRepository repository, Announcement notice) {
  return ProviderScope(
    overrides: [announcementsRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            // The list is what the card refreshes after it writes.
            final notices =
                ref.watch(announcementsProvider).value ??
                const <Announcement>[];
            return ListView(
              children: [
                for (final item in notices)
                  AnnouncementCard(announcement: item),
              ],
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the notice', () {
    test('is shown in the language of the app, else in the other one', () {
      final both = notice('n1');
      expect(both.title(chinese: false), 'Maintenance tonight');
      expect(both.title(chinese: true), '今晚维护');
      expect(both.body(chinese: true), '22:00 暂停十分钟。');
      final onlyEnglish = notice('n2', titleZh: '', bodyZh: '  ');
      expect(onlyEnglish.title(chinese: true), 'Maintenance tonight');
      expect(
        onlyEnglish.body(chinese: true),
        'We pause at 22:00 for ten minutes.',
      );
      final onlyChinese = notice('n3', titleEn: '', bodyEn: '');
      expect(onlyChinese.title(chinese: false), '今晚维护');
    });

    test('is read from the database function\'s JSON', () {
      final parsed = Announcement.fromJson({
        'id': 'n1',
        'kind': 'feedback_reply',
        'title_en': 'Reply to your feedback',
        'title_zh': '对你反馈的回复',
        'body_en': 'Fixed.',
        'body_zh': 'Fixed.',
        'published_at': '2026-10-20T09:00:00Z',
        'read': true,
      });
      expect(parsed.kind, AnnouncementKind.feedbackReply);
      expect(parsed.read, isTrue);
      expect(parsed.publishedAt, DateTime.utc(2026, 10, 20, 9));
      expect(
        AnnouncementKind.parse('something else'),
        AnnouncementKind.announcement,
      );
    });
  });

  group('the card', () {
    testWidgets('says who it is from and shows the title and the text', (
      tester,
    ) async {
      final repository = FakeAnnouncementsRepository([notice('n1')]);
      await tester.pumpWidget(_card(repository, notice('n1')));
      await tester.pumpAndSettle();
      expect(find.text('WeCord team'), findsOneWidget);
      expect(find.text('Official'), findsOneWidget);
      expect(find.text('Maintenance tonight'), findsOneWidget);
      expect(find.textContaining('We pause at 22:00'), findsOneWidget);
    });

    testWidgets('is in Chinese for a Chinese app', (tester) async {
      AppStrings.isChinese = true;
      final repository = FakeAnnouncementsRepository([notice('n1')]);
      await tester.pumpWidget(_card(repository, notice('n1')));
      await tester.pumpAndSettle();
      expect(find.text('WeCord 团队'), findsOneWidget);
      expect(find.text('今晚维护'), findsOneWidget);
      expect(find.text('Maintenance tonight'), findsNothing);
    });

    testWidgets('opening it marks it read, once', (tester) async {
      final repository = FakeAnnouncementsRepository([notice('n1')]);
      await tester.pumpWidget(_card(repository, notice('n1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inbox-announcement-n1')));
      await tester.pumpAndSettle();
      expect(repository.reads, ['n1']);
      // Closing and opening it again does not write again.
      await tester.tap(find.byKey(const ValueKey('inbox-announcement-n1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inbox-announcement-n1')));
      await tester.pumpAndSettle();
      expect(repository.reads, ['n1']);
    });

    testWidgets('the cross takes it off the list', (tester) async {
      final repository = FakeAnnouncementsRepository([
        notice('n1'),
        notice('n2', titleEn: 'Second'),
      ]);
      await tester.pumpWidget(_card(repository, notice('n1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('inbox-announcement-dismiss-n1')),
      );
      await tester.pumpAndSettle();
      expect(repository.dismissals, ['n1']);
      expect(find.text('Maintenance tonight'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('a failed write says so and keeps the card', (tester) async {
      final repository = FakeAnnouncementsRepository([notice('n1')])
        ..writeError = StateError('offline');
      await tester.pumpWidget(_card(repository, notice('n1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('inbox-announcement-dismiss-n1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
      expect(find.text('Maintenance tonight'), findsOneWidget);
    });
  });

  group('the list', () {
    test('counts what is unread', () async {
      final repository = FakeAnnouncementsRepository([
        notice('n1'),
        notice('n2', read: true),
        notice('n3'),
      ]);
      final container = ProviderContainer(
        overrides: [
          announcementsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(announcementsUnreadProvider, (_, _) {});
      await container.read(announcementsProvider.future);
      expect(container.read(announcementsUnreadProvider), 2);
    });

    test('a failing lookup is an empty list, not an error', () async {
      final repository = FakeAnnouncementsRepository()
        ..listError = StateError('function does not exist');
      final container = ProviderContainer(
        overrides: [
          announcementsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(announcementsProvider.future), isEmpty);
      expect(container.read(announcementsUnreadProvider), 0);
    });
  });

  group('in Notifications', () {
    testWidgets('the Official chip counts the unread and lists the cards', (
      tester,
    ) async {
      final repository = FakeAnnouncementsRepository([
        notice('n1'),
        notice('n2', titleEn: 'Terms changed', read: true),
        notice(
          'n3',
          kind: AnnouncementKind.feedbackReply,
          titleEn: 'Reply to your feedback',
          bodyEn: 'Thanks, fixed in 1.4.1.',
        ),
      ]);
      final world = PhoneWorld()
        ..extraOverrides = [
          announcementsRepositoryProvider.overrideWithValue(repository),
        ];
      await world.open(tester, '/notifications');
      await settle(tester);

      // The cards are on top of All.
      expect(find.text('Maintenance tonight'), findsOneWidget);
      expect(find.text('Reply to your feedback'), findsOneWidget);

      final chip = find.byKey(const ValueKey('inbox-filter-official'));
      await tester.ensureVisible(chip);
      await settle(tester);
      expect(find.text('Official 2'), findsOneWidget);
      await tester.tap(chip);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('inbox-announcement-n1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inbox-announcement-n2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inbox-announcement-n3')),
        findsOneWidget,
      );
      // Nothing else is on this tab.
      expect(find.byKey(const ValueKey('inbox-friend-requests')), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InboxScreen)),
      );
      // (The phone world has other things waiting: the notices add 2.)
      final withNotices = container.read(inboxBadgeCountProvider);
      await tester.tap(
        find.byKey(const ValueKey('inbox-announcement-dismiss-n1')),
      );
      await settle(tester);
      expect(repository.dismissals, ['n1']);
      expect(container.read(inboxBadgeCountProvider), withNotices - 1);
      await world.close(tester);
    });

    testWidgets('shows its own empty page', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld()
        ..extraOverrides = [
          announcementsRepositoryProvider.overrideWithValue(
            FakeAnnouncementsRepository(),
          ),
        ];
      await world.open(tester, '/notifications');
      await settle(tester);
      final chip = find.byKey(const ValueKey('inbox-filter-official'));
      await tester.ensureVisible(chip);
      await settle(tester);
      await tester.tap(chip);
      await settle(tester);
      expect(
        find.text(
          'Notices from the WeCord team, and its answers to your feedback, '
          'show up here.',
        ),
        findsOneWidget,
      );
      await world.close(tester);
    });
  });
}
