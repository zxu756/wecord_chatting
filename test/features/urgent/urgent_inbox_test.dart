import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../mobile/phone_test_support.dart';
import 'urgent_fakes.dart';

Future<PhoneWorld> _open(
  WidgetTester tester,
  FakeUrgentRepository repository,
) async {
  usePhoneViewport(tester, notchedPhone);
  final world = PhoneWorld()..extraOverrides = [urgentOverride(repository)];
  await world.open(tester, '/notifications');
  await settle(tester);
  return world;
}

Future<void> _filter(WidgetTester tester, String name) async {
  final chip = find.byKey(ValueKey('inbox-filter-$name'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

const _announcement = PendingAnnouncementAck(
  conversationId: 'c9',
  title: 'Study group',
  announcement: 'Hand in the forms by Friday',
  askedByName: 'Ada',
);

void main() {
  tearDown(() => AppStrings.isChinese = false);

  testWidgets('an urgent message waiting is a card, under All and To confirm', (
    tester,
  ) async {
    await _open(tester, FakeUrgentRepository(waiting: [pendingUrgent('m1')]));

    expect(find.byKey(const ValueKey('urgent-card-m1')), findsOneWidget);
    expect(find.text('Ada marked a message urgent'), findsOneWidget);
    expect(find.text('The meeting moved to 3 pm'), findsOneWidget);

    await _filter(tester, 'confirm');
    expect(find.byKey(const ValueKey('urgent-card-m1')), findsOneWidget);
    await _filter(tester, 'mentions');
    expect(find.byKey(const ValueKey('urgent-card-m1')), findsNothing);
  });

  testWidgets('"Got it" on the card confirms it', (tester) async {
    final repository = FakeUrgentRepository(waiting: [pendingUrgent('m1')]);
    await _open(tester, repository);
    await tester.tap(find.byKey(const ValueKey('urgent-card-confirm-m1')));
    await settle(tester);
    expect(repository.acknowledged, ['m1']);
    expect(find.byKey(const ValueKey('urgent-card-m1')), findsNothing);
  });

  testWidgets('an announcement to confirm is a card, and Confirm answers it', (
    tester,
  ) async {
    final repository = FakeUrgentRepository(announcements: [_announcement]);
    await _open(tester, repository);

    expect(
      find.byKey(const ValueKey('announcement-ack-card-c9')),
      findsOneWidget,
    );
    expect(
      find.text('Study group needs you to confirm its announcement'),
      findsOneWidget,
    );
    expect(find.text('Hand in the forms by Friday'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('announcement-ack-confirm-c9')));
    await settle(tester);
    expect(repository.announcementAcks, ['c9']);
    expect(
      find.byKey(const ValueKey('announcement-ack-card-c9')),
      findsNothing,
    );
  });

  testWidgets('with nothing to confirm there is a plain empty page', (
    tester,
  ) async {
    await _open(tester, FakeUrgentRepository());
    await _filter(tester, 'confirm');
    expect(find.byKey(const ValueKey('urgent-card-m1')), findsNothing);
    expect(
      find.text(
        'Urgent messages and announcements that ask you to confirm show up here.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the cards read in Chinese', (tester) async {
    await _open(
      tester,
      FakeUrgentRepository(
        waiting: [pendingUrgent('m1')],
        announcements: [_announcement],
      ),
    );
    AppStrings.isChinese = true;
    await _filter(tester, 'all');
    expect(find.text('Ada 加急了一条消息'), findsOneWidget);
    expect(find.text('Study group 的群公告需要你确认'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
  });
}
