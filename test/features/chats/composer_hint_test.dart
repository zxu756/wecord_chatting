import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';

void main() {
  group('composerHint', () {
    test('names the channel, person or group', () {
      expect(
        composerHint(ConversationType.channel, '# general'),
        'Message #general',
      );
      expect(
        composerHint(ConversationType.channel, 'general'),
        'Message #general',
      );
      expect(composerHint(ConversationType.direct, 'Ada'), 'Message @Ada');
      expect(
        composerHint(ConversationType.group, 'Weekend crew'),
        'Message Weekend crew',
      );
      expect(composerHint(ConversationType.direct, '  '), 'Message');
      expect(composerHint(null, 'Conversation'), 'Message');
    });

    test('is translated with the name in place', () {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(
        composerHint(ConversationType.channel, '# general'),
        '发消息到 #general',
      );
      expect(composerHint(ConversationType.direct, 'Ada'), '发消息给 @Ada');
      expect(composerHint(ConversationType.group, '周末'), '发消息到 周末');
    });
  });

  String hintOf(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-composer-field')),
    );
    expect(field.decoration?.hintMaxLines, 1);
    return field.decoration!.hintText!;
  }

  phoneTestWidgets('the composer names where the message goes', (
    tester,
    viewport,
  ) async {
    final world = PhoneWorld();
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/dm-1',
      extra: ChatThreadRouteExtra(
        title: bart.displayName,
        type: ConversationType.direct,
      ),
    );
    expect(hintOf(tester), 'Message @${bart.displayName}');
  }, viewports: const [notchedPhone]);

  phoneTestWidgets('channel composer', (tester, viewport) async {
    final world = PhoneWorld();
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
    expect(hintOf(tester), 'Message #general');
  }, viewports: const [notchedPhone]);

  phoneTestWidgets('group composer', (tester, viewport) async {
    final world = PhoneWorld();
    world.chats.messages = richMessages();
    await world.open(
      tester,
      '${ChatsScreen.path}/group-1',
      extra: ChatThreadRouteExtra(
        title: groupDetail.title,
        type: ConversationType.group,
      ),
    );
    expect(hintOf(tester), 'Message ${groupDetail.title}');
  }, viewports: const [notchedPhone]);
}
