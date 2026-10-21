import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/member_honors/honors_screen.dart';

import '../../mobile/phone_test_support.dart';
import 'honor_fakes.dart';

Future<HonorsWorld> _open(
  WidgetTester tester, {
  HonorsRpc? rpc,
  PhoneWorld? world,
}) async {
  final honors = HonorsWorld(rpc: rpc, world: world)..install();
  await pumpStandalone(
    tester,
    honors.world,
    const MemberHonorsScreen(circleId: 'circle-1'),
  );
  await settle(tester);
  return honors;
}

void main() {
  testWidgets('a running circle shows my numbers, my honors and the board', (
    tester,
  ) async {
    usePhoneViewport(tester, smallPhone);
    await _open(tester);

    expect(find.text('Honors'), findsWidgets);
    expect(find.byKey(const ValueKey('honors-intro')), findsOneWidget);
    expect(find.text('12 days'), findsOneWidget);
    expect(find.text('31 days'), findsOneWidget);
    expect(find.text('3 of 7'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('honors-earned')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Full week'), findsWidgets);
    expect(find.text('7-day streak'), findsOneWidget);

    // The board lists names by level, never a count of days.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('honors-board')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const ValueKey('honors-board-user-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('honors-board-user-6')), findsOneWidget);
    expect(find.byKey(const ValueKey('honors-level-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('honors-level-1')), findsOneWidget);
    expect(find.textContaining('Week of'), findsWidgets);
  });

  testWidgets('a board under five names is not shown', (tester) async {
    usePhoneViewport(tester, smallPhone);
    await _open(tester, rpc: HonorsRpc(honors: honorsJson(published: false)));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('honors-board-hidden')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const ValueKey('honors-board')), findsNothing);
    expect(find.byKey(const ValueKey('honors-board-user-1')), findsNothing);
  });

  testWidgets('no honors yet says how to get the first', (tester) async {
    usePhoneViewport(tester, smallPhone);
    await _open(
      tester,
      rpc: HonorsRpc(honors: honorsJson(honors: const [], streak: 0)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('honors-none')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const ValueKey('honors-earned')), findsNothing);
  });

  testWidgets('a small circle and a circle with honors off say so', (
    tester,
  ) async {
    usePhoneViewport(tester, smallPhone);
    await _open(tester, rpc: HonorsRpc(honors: honorsJson(eligible: false)));
    expect(find.byKey(const ValueKey('honors-small')), findsOneWidget);
    expect(find.byKey(const ValueKey('honors-mine')), findsNothing);
    expect(find.byKey(const ValueKey('honors-participate')), findsNothing);
  });

  testWidgets('honors turned off show a note and no numbers', (tester) async {
    usePhoneViewport(tester, smallPhone);
    await _open(tester, rpc: HonorsRpc(honors: honorsJson(enabled: false)));
    expect(find.byKey(const ValueKey('honors-off')), findsOneWidget);
    expect(find.byKey(const ValueKey('honors-mine')), findsNothing);
    expect(find.byKey(const ValueKey('honors-board')), findsNothing);
  });

  testWidgets('staying out asks first, then hides my numbers', (tester) async {
    usePhoneViewport(tester, smallPhone);
    final honors = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('honors-participate')));
    await settle(tester);
    expect(find.text('Stay out of honors?'), findsOneWidget);
    // Cancelling changes nothing.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(honors.rpc.paramsOf('set_my_honors_participation'), isEmpty);

    await tester.tap(find.byKey(const ValueKey('honors-participate')));
    await settle(tester);
    await tester.tap(find.text('Stay out'));
    await settle(tester);
    expect(honors.rpc.paramsOf('set_my_honors_participation').single, {
      'target_circle_id': 'circle-1',
      'take_part': false,
    });
    expect(find.byKey(const ValueKey('honors-mine')), findsNothing);
    expect(find.byKey(const ValueKey('honors-participate')), findsOneWidget);

    // Coming back needs no question.
    await tester.tap(find.byKey(const ValueKey('honors-participate')));
    await settle(tester);
    expect(honors.rpc.paramsOf('set_my_honors_participation').last, {
      'target_circle_id': 'circle-1',
      'take_part': true,
    });
  });

  testWidgets('only moderators see the circle switch', (tester) async {
    usePhoneViewport(tester, smallPhone);
    await _open(tester);
    expect(find.byKey(const ValueKey('honors-circle-switch')), findsNothing);
  });

  testWidgets('a moderator turns honors off for the circle', (tester) async {
    usePhoneViewport(tester, smallPhone);
    final honors = await _open(
      tester,
      rpc: HonorsRpc(honors: honorsJson(canManage: true)),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('honors-circle-switch')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('honors-circle-switch')));
    await settle(tester);
    expect(find.text('Turn honors off for this circle?'), findsOneWidget);
    await tester.tap(find.text('Turn off'));
    await settle(tester);
    expect(honors.rpc.paramsOf('set_circle_honors_enabled').single, {
      'target_circle_id': 'circle-1',
      'honors_on': false,
    });
    expect(find.byKey(const ValueKey('honors-off')), findsOneWidget);

    // Turning them on again needs no question and keeps the switch there.
    await tester.tap(find.byKey(const ValueKey('honors-circle-switch')));
    await settle(tester);
    expect(
      honors.rpc.paramsOf('set_circle_honors_enabled').last['honors_on'],
      true,
    );
    expect(find.byKey(const ValueKey('honors-off')), findsNothing);
  });

  testWidgets('a failed change says so and keeps the page', (tester) async {
    usePhoneViewport(tester, smallPhone);
    final rpc = HonorsRpc();
    final honors = await _open(tester, rpc: rpc);
    rpc.failing.add('set_my_honors_participation');
    await tester.tap(find.byKey(const ValueKey('honors-participate')));
    await settle(tester);
    await tester.tap(find.text('Stay out'));
    await settle(tester);
    expect(find.text('Could not change that. Try again.'), findsOneWidget);
    expect(find.byKey(const ValueKey('honors-mine')), findsOneWidget);
    expect(honors.rpc.paramsOf('set_my_honors_participation'), hasLength(1));
  });

  testWidgets('a suspended circle has no honors page', (tester) async {
    usePhoneViewport(tester, smallPhone);
    await _open(tester, rpc: HonorsRpc()..honors = null);
    expect(find.text('Honors are not available.'), findsOneWidget);
  });

  testWidgets('a failed load can be tried again', (tester) async {
    usePhoneViewport(tester, smallPhone);
    final rpc = HonorsRpc()..failing.add('get_circle_honors');
    await _open(tester, rpc: rpc);
    expect(find.text('Could not load honors.'), findsOneWidget);
    rpc.failing.clear();
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.byKey(const ValueKey('honors-mine')), findsOneWidget);
  });
}
