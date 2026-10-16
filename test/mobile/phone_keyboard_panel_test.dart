import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_sidebar.dart';

import 'phone_test_support.dart';

/// The floating user panel keeps out of the way of the keyboard: while it
/// is up the panel hides and the list ends just above the keyboard, so no
/// channel or conversation row is covered.
void main() {
  final userPanel = find.byKey(const ValueKey('phone-user-panel'));

  phoneTestWidgets('circle channel list with the keyboard up', (
    tester,
    viewport,
  ) async {
    final world = PhoneWorld();
    await world.open(tester, '/circles/circle-1');
    expect(userPanel, findsOneWidget);

    await showKeyboard(tester, viewport);
    expect(userPanel, findsNothing);
    final list = tester.getRect(find.byType(CircleChannelSidebar));
    expect(list.bottom, lessThanOrEqualTo(visibleArea(tester).bottom + 0.5));
    // The last channel can be scrolled fully into view above the keyboard.
    final last = find.byKey(const ValueKey('circle-channel-row-ch-photos'));
    await scrollIntoView(
      tester,
      last,
      scrollable: find
          .descendant(
            of: find.byType(CircleChannelSidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(last);
    await settle(tester);
    expectFullyVisible(tester, last);

    await hideKeyboard(tester, viewport);
    expect(userPanel, findsOneWidget);
  });

  phoneTestWidgets('home with the keyboard up', (tester, viewport) async {
    final world = PhoneWorld();
    await world.open(tester, ChatsScreen.path);
    expect(userPanel, findsOneWidget);
    await showKeyboard(tester, viewport);
    expect(userPanel, findsNothing);
    await hideKeyboard(tester, viewport);
    expect(userPanel, findsOneWidget);
  });
}
