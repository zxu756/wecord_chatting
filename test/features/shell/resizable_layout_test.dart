import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_profile_panel.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/layout/panel_layout.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

/// Runs [body] in the whole app on a 1440x900 desktop.
void desktopTest(
  String description,
  Future<void> Function(WidgetTester tester, PhoneWorld world) body,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      usePhoneViewport(tester, _desktop);
      addTearDown(tester.view.reset);
      final world = PhoneWorld();
      await body(tester, world);
      await world.close(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _openDirect(WidgetTester tester, PhoneWorld world) {
  return world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await settle(tester);
}

double _widthOf(WidgetTester tester, Finder finder) =>
    tester.getSize(finder).width;

void main() {
  desktopTest('the sidebar width is shared, followed by the user panel and '
      'saved', (tester, world) async {
    await _openDirect(tester, world);
    expect(_widthOf(tester, find.byType(HomeSidebar)), 292);
    expect(
      _widthOf(tester, find.byKey(const ValueKey('user-panel'))),
      WeCordSizes.railDesktop + 292 - 20,
    );

    await tester.drag(
      find.byKey(const ValueKey('resize-sidebar')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(_widthOf(tester, find.byType(HomeSidebar)), 352);
    expect(
      _widthOf(tester, find.byKey(const ValueKey('user-panel'))),
      WeCordSizes.railDesktop + 352 - 20,
    );
    expect(world.panelLayoutStore.layout?.sidebarWidth, 352);

    // A circle's channels use the same width.
    world.router.go('/circles/circle-1');
    await settle(tester);
    expect(_widthOf(tester, find.byType(CircleChannelSidebar)), 352);
    expect(
      _widthOf(tester, find.byKey(const ValueKey('user-panel'))),
      WeCordSizes.railDesktop + 352 - 20,
    );
  });

  desktopTest('saved widths come back on launch', (tester, world) async {
    world.panelLayoutStore.layout = const PanelLayout(
      sidebarWidth: 330,
      profileWidth: 360,
    );
    await _openDirect(tester, world);
    expect(_widthOf(tester, find.byType(HomeSidebar)), 330);
    expect(_widthOf(tester, find.byType(ChatProfilePanel)), 360);
  });

  desktopTest('the member list closes when dragged shut and the header '
      'opens it again', (tester, world) async {
    await world.open(tester, '/circles/circle-1');
    expect(find.byType(CircleMemberList), findsOneWidget);
    expect(_widthOf(tester, find.byType(CircleMemberList)), 248);

    await tester.drag(
      find.byKey(const ValueKey('resize-members')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircleMemberList), findsNothing);
    expect(world.panelLayoutStore.layout?.membersCollapsed, isTrue);

    await tester.tap(find.byTooltip('Show member list'));
    await settle(tester);
    expect(find.byType(CircleMemberList), findsOneWidget);
    expect(_widthOf(tester, find.byType(CircleMemberList)), 248);
    expect(world.panelLayoutStore.layout?.membersCollapsed, isFalse);
  });

  desktopTest('right panels close first when the window narrows and come '
      'back when there is room', (tester, world) async {
    await _openDirect(tester, world);
    expect(find.byType(ChatProfilePanel), findsOneWidget);

    // 1000 − 72 − 292 leaves 636: not enough for 300 + 420.
    await _resize(tester, const Size(1000, 800));
    expect(find.byType(ChatProfilePanel), findsNothing);
    expect(find.byTooltip('Show profile'), findsOneWidget);
    expect(_widthOf(tester, find.byType(HomeSidebar)), 292);
    // Not the user's choice: nothing saved.
    expect(world.panelLayoutStore.layout, isNull);

    await _resize(tester, const Size(1440, 900));
    expect(find.byType(ChatProfilePanel), findsOneWidget);

    // Asked for while there isn't room, it shows at its minimum.
    await _resize(tester, const Size(1000, 800));
    await tester.tap(find.byTooltip('Show profile'));
    await settle(tester);
    expect(
      _widthOf(tester, find.byType(ChatProfilePanel)),
      WeCordSizes.profilePanelMin,
    );

    // Closed by the user, it stays closed with room to spare.
    await tester.tap(find.byTooltip('Hide profile'));
    await settle(tester);
    await _resize(tester, const Size(1440, 900));
    expect(find.byType(ChatProfilePanel), findsNothing);
    expect(world.panelLayoutStore.layout?.profileCollapsed, isTrue);
  });

  desktopTest('then the sidebar shrinks to keep the content at 420', (
    tester,
    world,
  ) async {
    world.panelLayoutStore.layout = const PanelLayout(sidebarWidth: 420);
    await world.open(tester, '/circles/circle-1');
    expect(_widthOf(tester, find.byType(CircleChannelSidebar)), 420);

    await _resize(tester, const Size(900, 800));
    expect(find.byType(CircleMemberList), findsNothing);
    // 900 − 72 − 420 content.
    expect(_widthOf(tester, find.byType(CircleChannelSidebar)), 408);
    expect(
      _widthOf(tester, find.byKey(const ValueKey('user-panel'))),
      WeCordSizes.railDesktop + 408 - 20,
    );
  });

  testWidgets('phones have no dividers', (tester) async {
    usePhoneViewport(tester, phoneViewports.first);
    addTearDown(tester.view.reset);
    final world = PhoneWorld();
    await world.open(tester, '/circles/circle-1');
    expect(find.byType(ResizableDivider), findsNothing);
    await world.close(tester);
  });

  group('density', () {
    Future<Map<WeCordDensity, ({double dm, double channel, double member})>>
    measure(WidgetTester tester) async {
      final heights =
          <WeCordDensity, ({double dm, double channel, double member})>{};
      for (final density in WeCordDensity.values) {
        final world = PhoneWorld();
        await world.densityStore.save(density);
        await _openDirect(tester, world);
        final dm = tester
            .getSize(find.byKey(const ValueKey('home-dm-dm-1')))
            .height;
        world.router.go('/circles/circle-1');
        await settle(tester);
        final channel = tester
            .getSize(find.widgetWithText(CircleChannelRow, 'announcements'))
            .height;
        final member = tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('M5'),
                    matching: find.byType(WeCordPressable),
                  )
                  .first,
            )
            .height;
        heights[density] = (dm: dm, channel: channel, member: member);
        await world.close(tester);
      }
      return heights;
    }

    desktopTest('scales list rows with a mouse', (tester, _) async {
      final heights = await measure(tester);
      final comfortable = heights[WeCordDensity.comfortable]!;
      final standard = heights[WeCordDensity.standard]!;
      final compact = heights[WeCordDensity.compact]!;
      expect(compact.dm, lessThan(standard.dm));
      expect(standard.dm, lessThan(comfortable.dm));
      expect(compact.channel, lessThan(standard.channel));
      expect(standard.channel, lessThan(comfortable.channel));
      expect(compact.member, lessThan(standard.member));
      expect(standard.member, lessThan(comfortable.member));
    });

    testWidgets('keeps 44 px rows on touch screens', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        // A tablet: the wide layout, but fingers.
        usePhoneViewport(
          tester,
          const PhoneViewport(
            name: 'tablet',
            size: Size(1366, 1024),
            devicePixelRatio: 1,
          ),
        );
        addTearDown(tester.view.reset);
        final heights = await measure(tester);
        final compact = heights[WeCordDensity.compact]!;
        expect(compact.dm, greaterThanOrEqualTo(44));
        expect(compact.channel, greaterThanOrEqualTo(44));
        expect(compact.member, greaterThanOrEqualTo(44));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    desktopTest('is picked in Settings → Appearance and saved', (
      tester,
      world,
    ) async {
      await world.open(tester, SettingsScreen.path);
      await tester.tap(find.text('Appearance').first);
      await settle(tester);
      expect(find.text('Density'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('density-compact')));
      await settle(tester);
      expect(await world.densityStore.load(), WeCordDensity.compact);
      final segmented = tester.widget<WeCordSegmented<WeCordDensity>>(
        find.byKey(const ValueKey('density')),
      );
      expect(segmented.selected, WeCordDensity.compact);
    });
  });
}
