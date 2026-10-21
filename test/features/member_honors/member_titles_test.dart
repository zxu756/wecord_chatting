import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_tag_repository.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/member_honors/honor_repository.dart';
import 'package:wecord/features/member_honors/honor_widgets.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/models/circle.dart';

import '../../mobile/phone_test_support.dart';
import 'honor_fakes.dart';

Future<HonorsRpc> _pumpList(
  WidgetTester tester, {
  required CircleDetail detail,
  List<Map<String, dynamic>>? flair,
}) async {
  usePhoneViewport(tester, notchedPhone);
  final rpc = HonorsRpc(flair: flair ?? sampleFlair());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...rpc.overrides,
        presenceStatusesProvider.overrideWith((ref) => Stream.value({})),
        circleMemberAvatarsProvider(
          detail.circle.id,
        ).overrideWith((ref) async => {}),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CircleMemberList(
            detail: detail,
            onlineUserIds: {
              for (final member in detail.members) member.profile.id,
            },
            onChangeNickname: (_) {},
            width: null,
            compact: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return rpc;
}

CircleMember _member(CircleDetail detail, String id) =>
    detail.members.firstWhere((member) => member.profile.id == id);

void main() {
  group('who may give a title', () {
    test('the owner may, to anyone and to themselves', () {
      final detail = circleDetail();
      for (final member in detail.members) {
        expect(detail.canSetTitle(member), isTrue, reason: member.displayName);
      }
    });

    test(
      'a member without the permission may not, not even for themselves',
      () {
        final detail = circleDetailWith(
          channelId: 'ch-general',
          permissions: 3,
        );
        for (final member in detail.members) {
          expect(
            detail.canSetTitle(member),
            isFalse,
            reason: member.displayName,
          );
        }
      },
    );
  });

  group('next to a name', () {
    testWidgets('the member list shows titles and honors', (tester) async {
      await _pumpList(tester, detail: circleDetail());
      expect(find.text('Founder'), findsOneWidget);
      expect(find.text('Trail boss'), findsOneWidget);
      expect(find.text('Photo editor'), findsOneWidget);
      // Honors are icons with a tooltip, never a number of days.
      expect(find.byKey(const ValueKey('honor-badge-user-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('honor-badge-user-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('honor-badge-user-4')), findsNothing);
      expect(find.byIcon(Icons.local_fire_department), findsNWidgets(2));
      expect(find.byIcon(Icons.emoji_events), findsNWidgets(2));
      expect(find.textContaining('30'), findsNothing);
    });

    testWidgets('a title is read out as a title', (tester) async {
      await _pumpList(tester, detail: circleDetail());
      bool labelled(String label) => find
          .byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label,
          )
          .evaluate()
          .isNotEmpty;
      expect(labelled('Title: Founder'), isTrue);
      // The honor of user-2 is read out in words, with no number of days.
      expect(labelled('30-day streak'), isTrue);
      expect(labelled('7-day streak, Regular last week'), isTrue);
    });

    testWidgets('a name outside a circle shows no title', (tester) async {
      final rpc = HonorsRpc(flair: sampleFlair());
      await tester.pumpWidget(
        ProviderScope(
          overrides: rpc.overrides,
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  Text('Ada'),
                  ProfileNameBadges(userId: 'user-1'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MemberTitleChip), findsNothing);
      expect(rpc.paramsOf('list_circle_member_flair'), isEmpty);
    });

    testWidgets('in a circle the title comes before the circle tag', (
      tester,
    ) async {
      final rpc = HonorsRpc(flair: sampleFlair());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...rpc.overrides,
            profileBadgesProvider('user-1').overrideWith(
              (ref) async => const ProfileBadges(
                tag: CircleTag(text: 'GG', badge: CircleTagBadge.bolt),
                tagCircleName: 'Gamers',
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  ProfileNameBadges(userId: 'user-1', circleId: 'circle-1'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = tester.getTopLeft(find.text('Founder')).dx;
      final tag = tester.getTopLeft(find.text('GG')).dx;
      expect(title, lessThan(tag));
      // One call serves every name of the circle.
      expect(rpc.paramsOf('list_circle_member_flair'), hasLength(1));
    });

    testWidgets('a failing list shows plain names', (tester) async {
      final rpc = HonorsRpc(flair: sampleFlair())
        ..failing.add('list_circle_member_flair');
      await tester.pumpWidget(
        ProviderScope(
          overrides: rpc.overrides,
          child: const MaterialApp(
            home: Scaffold(
              body: ProfileNameBadges(userId: 'user-1', circleId: 'circle-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MemberTitleChip), findsNothing);
    });
  });

  group('giving a title', () {
    testWidgets('the owner sets one from the member menu', (tester) async {
      final rpc = await _pumpList(tester, detail: circleDetail());
      await tester.longPress(find.text('Grace Brewster Murray Hopper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set title'));
      await tester.pumpAndSettle();

      expect(
        find.text('Shown next to Grace Brewster Murray Hopper in this circle.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '  Scout ');
      await tester.tap(find.byKey(const ValueKey('title-save')));
      await tester.pumpAndSettle();

      expect(rpc.paramsOf('set_circle_member_title').single, {
        'target_circle_id': 'circle-1',
        'target_user_id': 'user-3',
        'member_title': 'Scout',
      });
      expect(find.text('Title saved.'), findsOneWidget);
      // The list asked again and shows it.
      expect(find.text('Scout'), findsOneWidget);
    });

    testWidgets('an existing title is shown, and can be removed', (
      tester,
    ) async {
      final rpc = await _pumpList(tester, detail: circleDetail());
      await tester.longPress(find.text('Linus'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set title'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Photo editor',
      );
      await tester.tap(find.byKey(const ValueKey('title-remove')));
      await tester.pumpAndSettle();
      expect(
        rpc.paramsOf('set_circle_member_title').single['member_title'],
        isNull,
      );
      expect(find.text('Title removed.'), findsOneWidget);
      expect(find.text('Photo editor'), findsNothing);
    });

    testWidgets('a title with angle brackets is not sent', (tester) async {
      final rpc = await _pumpList(tester, detail: circleDetail());
      await tester.longPress(find.text('Grace Brewster Murray Hopper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set title'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '<b>hi');
      await tester.tap(find.byKey(const ValueKey('title-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('This title uses characters that are not allowed.'),
        findsOneWidget,
      );
      expect(rpc.paramsOf('set_circle_member_title'), isEmpty);
    });

    testWidgets('a refused change says so', (tester) async {
      final rpc = await _pumpList(tester, detail: circleDetail());
      rpc.failing.add('set_circle_member_title');
      await tester.longPress(find.text('Grace Brewster Murray Hopper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set title'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Scout');
      await tester.tap(find.byKey(const ValueKey('title-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not change the title. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a member cannot give titles but can take their own off', (
      tester,
    ) async {
      final detail = circleDetailWith(channelId: 'ch-general', permissions: 3);
      final me = _member(detail, 'user-1');
      final rpc = await _pumpList(
        tester,
        detail: detail,
        flair: [
          {'user_id': me.profile.id, 'title': 'Guest'},
        ],
      );
      // Not for others.
      await tester.longPress(find.text('Grace Brewster Murray Hopper'));
      await tester.pumpAndSettle();
      expect(find.text('Set title'), findsNothing);
      expect(find.text('Remove my title'), findsNothing);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      // Their own can go.
      await tester.longPress(find.text(me.displayName));
      await tester.pumpAndSettle();
      expect(find.text('Set title'), findsNothing);
      await tester.tap(find.text('Remove my title'));
      await tester.pumpAndSettle();
      expect(rpc.paramsOf('set_circle_member_title').single, {
        'target_circle_id': 'circle-1',
        'target_user_id': 'user-1',
        'member_title': null,
      });
      expect(find.text('Guest'), findsNothing);
    });
  });
}
