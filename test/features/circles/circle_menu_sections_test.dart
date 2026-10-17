import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

/// The circle menu is grouped: Everyday, Manage, Moderation & safety, then
/// leaving; a section nobody here can use is not shown. Same on the phone
/// sheet and on wide screens.
void main() {
  const everyday = [
    'Invite friends',
    'Notification settings',
    'Emoji & stickers',
    'Change my nickname',
    'Change circle avatar',
  ];
  const manage = [
    'Create channel',
    'Create category',
    'Circle settings',
    'Onboarding',
  ];
  const safety = [
    'Roles',
    'Bans',
    'AutoMod',
    'AI guard',
    'Review',
    'Audit log',
  ];

  Future<PhoneWorld> openMenu(
    WidgetTester tester, {
    required bool wide,
    int? memberPermissions,
  }) async {
    usePhoneViewport(tester, wide ? _desktop : notchedPhone);
    final world = PhoneWorld();
    if (memberPermissions != null) {
      final detail = circleDetail();
      world.circles.detail = circleDetailWith(
        channelId: detail.channels.first.id,
        permissions: memberPermissions,
      );
    }
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    return world;
  }

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text).last).dy;

  for (final wide in [false, true]) {
    final where = wide ? 'wide' : 'phone';

    testWidgets('owners see every section in order on $where', (tester) async {
      debugDefaultTargetPlatformOverride = wide ? TargetPlatform.macOS : null;
      try {
        await openMenu(tester, wide: wide);

        // The phone sheet scrolls; look the rows up without scrolling.
        final headers = ['Everyday', 'Manage', 'Moderation & safety'];
        for (final header in headers) {
          expect(find.text(header), findsOneWidget, reason: header);
        }
        final sheetRows = [...everyday, ...manage, ...safety];
        if (wide) {
          for (final label in sheetRows) {
            expect(find.text(label), findsOneWidget, reason: label);
          }
          // Headers and rows read top to bottom in that order.
          final ordered = [
            'Everyday',
            ...everyday,
            'Manage',
            ...manage,
            'Moderation & safety',
            ...safety,
          ];
          final positions = [for (final text in ordered) top(tester, text)];
          expect([...positions]..sort(), positions);
        } else {
          expect(find.text('Everyday'), findsOneWidget);
          expect(find.text('Invite friends'), findsOneWidget);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('members only see the sections they can use on $where', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = wide ? TargetPlatform.macOS : null;
      try {
        await openMenu(tester, wide: wide, memberPermissions: 1 | 2);

        expect(find.text('Everyday'), findsOneWidget);
        expect(find.text('Notification settings'), findsOneWidget);
        // Nothing to manage or moderate: no empty headers either.
        expect(find.text('Manage'), findsNothing);
        expect(find.text('Moderation & safety'), findsNothing);
        for (final label in [...manage, ...safety]) {
          expect(find.text(label), findsNothing, reason: label);
        }
        // Leaving is still there, below everything else.
        expect(find.text('Leave circle'), findsOneWidget);
        expect(
          top(tester, 'Leave circle'),
          greaterThan(top(tester, 'Notification settings')),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('every row of the phone sheet has an icon of its own', (
    tester,
  ) async {
    await openMenu(tester, wide: false);
    final icons = <IconData>[];
    final scrollable = find.byType(Scrollable).last;
    for (var step = 0; step < 12; step++) {
      for (final tile in tester.widgetList<SettingsIconTile>(
        find.byType(SettingsIconTile),
      )) {
        if (!icons.contains(tile.icon)) {
          icons.add(tile.icon);
        }
      }
      await tester.drag(scrollable, const Offset(0, -300));
      await tester.pump();
    }
    // Every row of an owner's menu (the 15 rows) is distinct.
    expect(icons.length, greaterThanOrEqualTo(15));
    expect(icons.toSet().length, icons.length);
  });
}
