import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/member_honors/honor_widgets.dart';
import 'package:wecord/features/member_honors/honors_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';
import 'honor_fakes.dart';

void main() {
  tearDown(() => AppStrings.isChinese = false);

  testWidgets('the circle menu has an Honors entry that opens the page', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final world = HonorsWorld()..install();
    await world.world.open(tester, '/circles/circle-1');
    await tester.tap(find.byTooltip('Circle menu'));
    await settle(tester);
    final entry = find.text('Honors');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await settle(tester);
    expect(find.byKey(const ValueKey('honors-intro')), findsOneWidget);
    expect(world.rpc.paramsOf('get_circle_honors'), isNotEmpty);
  });

  testWidgets('a link to the honors page opens it', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final world = HonorsWorld()..install();
    await world.world.open(tester, '/circles/circle-1/honors');
    expect(find.byKey(const ValueKey('honors-mine')), findsOneWidget);
  });

  testWidgets('the page reads in Chinese', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    AppStrings.isChinese = true;
    final world = HonorsWorld(
      rpc: HonorsRpc(honors: honorsJson(canManage: true)),
    )..install();
    await pumpStandalone(
      tester,
      world.world,
      const MemberHonorsScreen(circleId: 'circle-1'),
    );
    expect(find.text('荣誉'), findsWidgets);
    expect(find.text('参与荣誉'), findsOneWidget);
    expect(find.text('12 天'), findsOneWidget);
    expect(find.text('3 / 7'), findsOneWidget);
  });

  testWidgets('a message in a circle channel shows its sender\'s title', (
    tester,
  ) async {
    usePhoneViewport(tester, notchedPhone);
    final world = HonorsWorld(rpc: HonorsRpc(flair: sampleFlair()))..install();
    world.world.chats.messages = richMessages();
    await world.world.open(
      tester,
      '/circles/circle-1/channels/conv-general',
      extra: const ChatThreadRouteExtra(
        title: '# general',
        type: ConversationType.channel,
        circleId: 'circle-1',
      ),
    );
    expect(find.byType(MemberTitleChip), findsWidgets);
    expect(world.rpc.paramsOf('list_circle_member_flair'), isNotEmpty);
  });

  testWidgets('a message in a private chat asks for no titles', (tester) async {
    usePhoneViewport(tester, notchedPhone);
    final world = HonorsWorld(rpc: HonorsRpc(flair: sampleFlair()))..install();
    world.world.chats.messages = richMessages();
    await world.world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: const ChatThreadRouteExtra(
        title: 'Bart',
        type: ConversationType.direct,
      ),
    );
    expect(find.byType(MemberTitleChip), findsNothing);
    expect(world.rpc.paramsOf('list_circle_member_flair'), isEmpty);
  });
}
