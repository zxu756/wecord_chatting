import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/groups/group_invitations.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import '../../accessibility/a11y_screens.dart' show desktopViewport;
import '../../mobile/phone_test_support.dart';
import '../privacy/privacy2_fakes.dart';

Future<PhoneWorld> _open(
  WidgetTester tester, {
  FakeGroupInvitationsRepository? invitations,
  FakeSecurityAlertsRepository? alerts,
  PhoneViewport viewport = notchedPhone,
}) async {
  usePhoneViewport(tester, viewport);
  final world = PhoneWorld()
    ..extraOverrides = privacy2Overrides(
      invitations: invitations,
      alerts: alerts,
    );
  await world.open(tester, '/notifications');
  await settle(tester);
  return world;
}

/// Opens the filter chip [name] (the row scrolls sideways on a phone).
Future<void> _filter(WidgetTester tester, String name) async {
  final chip = find.byKey(ValueKey('inbox-filter-$name'));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

void main() {
  group('group invitations', () {
    testWidgets('show as a card in Friends, with Accept and Decline', (
      tester,
    ) async {
      await _open(tester);

      await _filter(tester, 'friends');

      expect(
        find.byKey(const ValueKey('inbox-group-invitation-invite-1')),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Bart the Bold invited you to join Weekend climbers',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Expires in 7 days'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-invitation-accept')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('group-invitation-decline')),
        findsOneWidget,
      );
    });

    testWidgets('the Friends chip counts requests and invitations', (
      tester,
    ) async {
      await _open(tester);
      // The phone world has one request waiting, and one invitation.
      expect(find.text('Friends 2'), findsOneWidget);
    });

    testWidgets('Accept joins the group and opens it', (tester) async {
      final invitations = FakeGroupInvitationsRepository();
      final world = await _open(tester, invitations: invitations);
      await _filter(tester, 'friends');

      await tester.tap(find.byKey(const ValueKey('group-invitation-accept')));
      await settle(tester);

      expect(invitations.answers, [('invite-1', true)]);
      expect(world.router.state.uri.path, '/chats/group-1');
    });

    testWidgets('Decline removes the card and stays on the page', (
      tester,
    ) async {
      final invitations = FakeGroupInvitationsRepository();
      final world = await _open(tester, invitations: invitations);
      await _filter(tester, 'friends');

      await tester.tap(find.byKey(const ValueKey('group-invitation-decline')));
      await settle(tester);

      expect(invitations.answers, [('invite-1', false)]);
      expect(
        find.byKey(const ValueKey('inbox-group-invitation-invite-1')),
        findsNothing,
      );
      expect(world.router.state.uri.path, '/notifications');
    });

    testWidgets('an invitation that expired says so and goes away', (
      tester,
    ) async {
      final invitations = FakeGroupInvitationsRepository()..fail = true;
      await _open(tester, invitations: invitations);
      await _filter(tester, 'friends');

      await tester.tap(find.byKey(const ValueKey('group-invitation-accept')));
      await settle(tester);

      expect(
        find.text(
          'This invitation is no longer available. Ask to be invited again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty Friends list still reads as empty', (tester) async {
      await _open(
        tester,
        invitations: FakeGroupInvitationsRepository(const []),
      );
      await _filter(tester, 'friends');
      expect(
        find.byKey(const ValueKey('inbox-group-invitations')),
        findsNothing,
      );
    });

    testWidgets('lay out on a desktop window', (tester) async {
      await _open(tester, viewport: desktopViewport);
      await _filter(tester, 'friends');
      expect(
        find.byKey(const ValueKey('inbox-group-invitation-invite-1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('security alerts', () {
    testWidgets('show first in All and in their own Security chip', (
      tester,
    ) async {
      await _open(tester);
      expect(
        find.byKey(const ValueKey('inbox-security-alert-1')),
        findsOneWidget,
      );

      await _filter(tester, 'security');
      expect(
        find.byKey(const ValueKey('inbox-security-alert-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inbox-group-invitation-invite-1')),
        findsNothing,
      );

      await _filter(tester, 'mentions');
      expect(
        find.byKey(const ValueKey('inbox-security-alert-1')),
        findsNothing,
      );
    });

    testWidgets('the Security chip counts the open alerts', (tester) async {
      await _open(tester);
      expect(find.text('Security 1'), findsOneWidget);
    });

    testWidgets('Not me ends the session that signed in', (tester) async {
      final alerts = FakeSecurityAlertsRepository();
      await _open(tester, alerts: alerts);
      await _filter(tester, 'security');

      await tester.tap(find.byKey(const ValueKey('security-it-was-me')));
      await settle(tester);

      expect(alerts.resolved.single.$1, 'alert-1');
      expect(find.text('You confirmed this sign-in'), findsOneWidget);
    });

    testWidgets('an empty Security list explains itself', (tester) async {
      await _open(tester, alerts: FakeSecurityAlertsRepository(const []));
      await _filter(tester, 'security');
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.text('Sign-ins to your account from a new device show up here.'),
        findsOneWidget,
      );
    });

    testWidgets('read in Chinese', (tester) async {
      addTearDown(() => AppStrings.isChinese = false);
      await _open(tester);
      // The app follows its language setting (English here); switch the
      // strings and rebuild the page.
      AppStrings.isChinese = true;
      await _filter(tester, 'all');
      expect(find.text('你的账号在新设备上登录'), findsOneWidget);
      expect(
        find.textContaining('邀请你加入Weekend climbers', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('不是我'), findsOneWidget);
      expect(find.text('是我本人'), findsOneWidget);
      expect(find.textContaining('安全'), findsOneWidget);
    });
  });

  test('invitations expire in whole days, then today', () {
    final now = DateTime.utc(2026, 10, 20, 12);
    expect(
      invitationExpiryLabel(now.add(const Duration(days: 7)), now: now),
      'Expires in 7 days',
    );
    expect(
      invitationExpiryLabel(
        now.add(const Duration(days: 1, hours: 2)),
        now: now,
      ),
      'Expires in 2 days',
    );
    expect(
      invitationExpiryLabel(now.add(const Duration(hours: 30)), now: now),
      'Expires in 2 days',
    );
    expect(
      invitationExpiryLabel(now.add(const Duration(hours: 24)), now: now),
      'Expires in 1 day',
    );
    expect(
      invitationExpiryLabel(now.add(const Duration(hours: 5)), now: now),
      'Expires today',
    );
  });

  test('a translated sentence keeps its own word order', () {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    final spans = spansFromTemplate('{name}邀请你加入{group}', {
      'name': const TextSpan(text: '小明', style: bold),
      'group': const TextSpan(text: '周末登山', style: bold),
    });
    expect(TextSpan(children: spans).toPlainText(), '小明邀请你加入周末登山');
    final english = spansFromTemplate('{name} invited you to join {group}', {
      'name': const TextSpan(text: 'Ada'),
      'group': const TextSpan(text: 'Climbers'),
    });
    expect(
      TextSpan(children: english).toPlainText(),
      'Ada invited you to join Climbers',
    );
    // An unknown placeholder is left as it is.
    expect(
      TextSpan(children: spansFromTemplate('Hi {who}', const {})).toPlainText(),
      'Hi {who}',
    );
  });

  test('people not in the group yet are the ones invited', () {
    expect(pendingInviteCount(['a', 'b', 'c'], ['a', 'x']), 2);
    expect(pendingInviteCount(['a'], ['a']), 0);
    expect(invitationsSentNotice(1), contains('1 person'));
    expect(invitationsSentNotice(3), contains('3 people'));
  });
}
