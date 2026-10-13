import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_workspace.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/home_sidebar.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';

import '../../mobile/phone_test_support.dart';

void main() {
  void useWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  String location(PhoneWorld world) =>
      world.router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('home keeps the rail and sidebar beside friends and DMs', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = PhoneWorld();
    await world.open(tester, '/home');

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(CircleRail), findsOneWidget);
    expect(find.byType(HomeSidebar), findsOneWidget);
    expect(find.byType(ContactsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('home-inbox')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-panel')), findsOneWidget);
    expect(find.text(me.displayName), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('home-dm-dm-1')));
    await settle(tester);
    expect(location(world), '/chats/dm-1');
    expect(find.byType(HomeSidebar), findsOneWidget);
    expect(
      tester.widget<ChatThreadScreen>(find.byType(ChatThreadScreen)).onBack,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('home-inbox')));
    await settle(tester);
    expect(location(world), '/notifications');
    expect(find.byType(InboxScreen), findsOneWidget);

    // A channel mention opens the channel inside its circle.
    await tester.tap(find.byKey(const ValueKey('inbox-item-inbox-mention')));
    await settle(tester);
    expect(location(world), '/circles/circle-1?c=conv-general');
    expect(find.byType(HomeSidebar), findsNothing);
    expect(find.byType(CircleWorkspace), findsOneWidget);
    expect(find.byKey(const ValueKey('user-panel')), findsOneWidget);

    // The rail's Home item goes back.
    await tester.tap(find.byKey(const ValueKey('circle-rail-home')));
    await settle(tester);
    expect(location(world), '/home');

    // Settings from the user panel.
    await tester.tap(find.byTooltip('User settings'));
    await settle(tester);
    expect(location(world), '/me');
    expect(find.byType(CircleRail), findsOneWidget);

    await world.close(tester);
  });

  testWidgets('the rail shows unread direct messages on Home', (tester) async {
    useWideScreen(tester);
    final world = PhoneWorld();
    await world.open(tester, '/home');

    final unread = world.chats.conversations
        .where((c) => c.isDirectMessage && !c.isMuted)
        .fold<int>(0, (sum, c) => sum + c.unreadCount);
    expect(unread, greaterThan(0));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('circle-rail-home')),
        matching: find.text(unread > 99 ? '99+' : '$unread'),
      ),
      findsOneWidget,
    );

    await world.close(tester);
  });
}
