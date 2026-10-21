// Member titles and honors (C7), for the accessibility guard
// (guidelines_test.dart) and the screenshot tools: the Honors page (running,
// small, off, board not yet shown, for a moderator, the question before
// staying out), the member list with titles and honors, the menu and the
// dialog that give a title, a circle channel with titles on the names, the
// circle menu, and the desktop circle with its member list, at large text,
// narrow and with Care mode on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/member_honors/honors_screen.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../features/member_honors/honor_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

Future<HonorsWorld> _honors(
  WidgetTester tester,
  PhoneWorld world, {
  HonorsRpc? rpc,
}) async {
  final honors = HonorsWorld(world: world, rpc: rpc)..install();
  await pumpStandalone(
    tester,
    world,
    const MemberHonorsScreen(circleId: 'circle-1'),
  );
  await settle(tester);
  return honors;
}

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await settle(tester);
}

/// The members of the sample circle as the member list shows them, with
/// titles and honors next to some names.
Future<HonorsWorld> _members(
  WidgetTester tester,
  PhoneWorld world, {
  HonorsRpc? rpc,
}) async {
  final honors = HonorsWorld(
    world: world,
    rpc: rpc ?? HonorsRpc(flair: sampleFlair()),
  )..install();
  final detail = world.circles.detail;
  world.extraOverrides = [
    ...world.extraOverrides,
    circleMemberAvatarsProvider(
      detail.circle.id,
    ).overrideWith((ref) async => {}),
  ];
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: SafeArea(
        child: CircleMemberList(
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
  );
  await settle(tester);
  return honors;
}

Future<void> _titleDialog(WidgetTester tester, PhoneWorld world) async {
  await _members(tester, world);
  await tester.longPress(find.text('Grace Brewster Murray Hopper'));
  await settle(tester);
  await tester.tap(find.text(tr('Set title')));
  await settle(tester);
  await tester.enterText(find.byType(TextField), 'Scout');
  await tester.pump();
}

Future<void> _channel(WidgetTester tester, PhoneWorld world) async {
  HonorsWorld(
    world: world,
    rpc: HonorsRpc(flair: sampleFlair()),
  ).install();
  world.chats.messages = richMessages();
  await world.open(
    tester,
    '/circles/circle-1/channels/conv-general',
    extra: const ChatThreadRouteExtra(
      title: '# general',
      type: ConversationType.channel,
      circleId: 'circle-1',
    ),
  );
}

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

final memberHonorsA11yScreens = <A11yScreen>[
  A11yScreen('honors-page', (tester, world) async {
    await _honors(tester, world);
  }),
  A11yScreen('honors-page-large-text', (tester, world) async {
    await _honors(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('honors-page-care-mode', (tester, world) async {
    _care(world);
    await _honors(tester, world);
  }),
  A11yScreen('honors-page-narrow', (tester, world) async {
    await _honors(tester, world);
  }, viewport: smallPhone),
  A11yScreen('honors-board', (tester, world) async {
    await _honors(tester, world);
    await _scrollTo(tester, 'honors-board');
  }),
  A11yScreen('honors-board-large-text', (tester, world) async {
    await _honors(tester, world);
    await _scrollTo(tester, 'honors-board');
  }, viewport: notchedPhoneLargeText),
  A11yScreen('honors-board-hidden', (tester, world) async {
    await _honors(
      tester,
      world,
      rpc: HonorsRpc(honors: honorsJson(published: false)),
    );
    await _scrollTo(tester, 'honors-board-hidden');
  }),
  A11yScreen('honors-none-yet', (tester, world) async {
    await _honors(
      tester,
      world,
      rpc: HonorsRpc(honors: honorsJson(honors: const [], streak: 0)),
    );
    await _scrollTo(tester, 'honors-none');
  }),
  A11yScreen('honors-moderator', (tester, world) async {
    await _honors(
      tester,
      world,
      rpc: HonorsRpc(honors: honorsJson(canManage: true)),
    );
    await _scrollTo(tester, 'honors-circle-switch');
  }),
  A11yScreen('honors-small-circle', (tester, world) async {
    await _honors(
      tester,
      world,
      rpc: HonorsRpc(honors: honorsJson(eligible: false)),
    );
  }),
  A11yScreen('honors-off', (tester, world) async {
    await _honors(
      tester,
      world,
      rpc: HonorsRpc(honors: honorsJson(enabled: false, canManage: true)),
    );
  }),
  A11yScreen('honors-stay-out', (tester, world) async {
    await _honors(tester, world);
    await tester.tap(find.byKey(const ValueKey('honors-participate')));
    await settle(tester);
  }),
  A11yScreen('member-titles', (tester, world) async {
    await _members(tester, world);
  }),
  A11yScreen('member-titles-large-text', (tester, world) async {
    await _members(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('member-titles-care-mode', (tester, world) async {
    _care(world);
    await _members(tester, world);
  }),
  A11yScreen('member-titles-narrow', (tester, world) async {
    await _members(tester, world);
  }, viewport: smallPhone),
  A11yScreen('member-title-menu', (tester, world) async {
    await _members(tester, world);
    await tester.longPress(find.text('Grace Brewster Murray Hopper'));
    await settle(tester);
  }),
  A11yScreen('member-title-dialog', _titleDialog),
  A11yScreen(
    'member-title-dialog-large-text',
    _titleDialog,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('channel-with-titles', _channel),
  A11yScreen(
    'channel-with-titles-large-text',
    _channel,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('circle-menu-honors', (tester, world) async {
    HonorsWorld(world: world).install();
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip(tr('Circle menu')));
    await settle(tester);
  }),
  A11yScreen(
    'desktop-honors',
    (tester, world) async {
      await _honors(
        tester,
        world,
        rpc: HonorsRpc(honors: honorsJson(canManage: true)),
      );
    },
    viewport: desktopViewport,
    desktop: true,
  ),
  A11yScreen(
    'desktop-circle-titles',
    (tester, world) async {
      HonorsWorld(
        world: world,
        rpc: HonorsRpc(flair: sampleFlair()),
      ).install();
      await world.open(tester, '/circles/circle-1');
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
