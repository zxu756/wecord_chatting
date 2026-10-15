import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_bot_widgets.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/circle_tag_repository.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/message.dart';

import 'announcement_channels_test.dart' show RecordingRpc;

Map<String, dynamic> _botJson({bool hasToken = true}) => {
  'id': 'bot-1',
  'circle_id': 'circle-1',
  'user_id': 'bot-user',
  'name': 'Helper',
  'username': 'bot_abc',
  'has_token': hasToken,
  'is_member': true,
  'role_names': ['Helpers'],
  'command_count': 2,
  'created_at': '2026-10-16T08:00:00Z',
  'last_used_at': null,
};

const _ping = BotSlashCommand(
  name: 'ping',
  description: 'Replies with pong',
  botName: 'Helper',
);

CircleDetail _detail() {
  return CircleDetail.fromJson({
    'circle': {
      'id': 'circle-1',
      'name': 'Study Hall',
      'member_count': 1,
      'channel_count': 1,
      'current_user_role': 'owner',
    },
    'members': const [],
    'channels': const [],
    'posts': const [],
    'roles': [
      {
        'id': 'role-1',
        'name': 'Helpers',
        'position': 1,
        'permissions': 3,
        'is_default': false,
      },
      {
        'id': 'everyone',
        'name': '@everyone',
        'position': 0,
        'permissions': 3,
        'is_default': true,
      },
    ],
  });
}

void main() {
  test('bot commands are offered after built-ins and parsed on send', () {
    const context = SlashCommandContext(
      isCircleConversation: true,
      botCommands: [
        _ping,
        BotSlashCommand(name: 'shrug', description: 'x', botName: 'Other'),
      ],
    );
    expect(botSlashCommandCandidates('p', context).single.name, 'ping');
    // A built-in name always means the built-in.
    expect(botSlashCommandCandidates('shr', context), isEmpty);
    expect(parseBotSlashCommand('/shrug hi', context), isNull);

    final parsed = parseBotSlashCommand('/ping  now please ', context);
    expect(parsed?.$1.name, 'ping');
    expect(parsed?.$2, 'now please');
    expect(parseBotSlashCommand('/ping', context)?.$2, '');
    expect(parseBotSlashCommand('/pong', context), isNull);
    expect(parseBotSlashCommand('ping', context), isNull);
  });

  test('bot answers carry the command that asked for them', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'bot-user',
      'type': 'text',
      'body': 'pong',
      'created_at': '2026-10-16T10:00:00Z',
      'interaction': {
        'interaction_id': 'i1',
        'command': 'ping',
        'user_id': 'u1',
        'user_name': 'Ann',
      },
    });
    expect(message.interaction?.command, 'ping');
    expect(message.interaction?.userName, 'Ann');
    expect(message.copyWith(body: 'x').interaction?.command, 'ping');
  });

  test('the repository calls the bot functions', () async {
    final rpc = RecordingRpc({
      'list_circle_bots': (_) => [_botJson()],
      'bots': (_) => {..._botJson(), 'token': 'secret'},
      'regenerate_bot_token': (_) => {..._botJson(), 'token': 'secret-2'},
      'revoke_bot_token': (_) => _botJson(hasToken: false),
      'delete_circle_bot': (_) => null,
      'list_circle_bot_commands': (_) => [
        {
          'bot_id': 'bot-1',
          'bot_user_id': 'bot-user',
          'bot_name': 'Helper',
          'name': 'ping',
          'description': 'Replies with pong',
        },
      ],
      'invoke_bot_command': (_) => {
        'interaction_id': 'i1',
        'bot_name': 'Helper',
        'command': 'ping',
      },
    });
    final repository = CircleBotRepository(rpc.call, rpc.call);

    final bots = await repository.listBots('circle-1');
    final created = await repository.createBot(
      circleId: 'circle-1',
      name: ' Helper ',
      roleId: 'role-1',
    );
    final regenerated = await repository.regenerateToken('bot-1');
    await repository.revokeToken('bot-1');
    await repository.deleteBot('bot-1');
    final commands = await repository.listCommands('circle-1');
    final invocation = await repository.invoke(
      conversationId: 'conversation-1',
      command: 'ping',
      options: 'now',
    );

    expect(bots.single.roleNames, ['Helpers']);
    expect(created.token, 'secret');
    expect(regenerated.token, 'secret-2');
    expect(commands.single.botName, 'Helper');
    expect(invocation.botName, 'Helper');
    expect(rpc.calls[1].$1, 'bots');
    expect(rpc.calls[1].$2, {
      'circle_id': 'circle-1',
      'name': 'Helper',
      'role_id': 'role-1',
    });
    expect(rpc.calls.last.$2, {
      'target_conversation_id': 'conversation-1',
      'command_name': 'ping',
      'command_options': 'now',
    });
  });

  testWidgets('managers create a bot and see its token once', (tester) async {
    var bots = <Map<String, dynamic>>[];
    final rpc = RecordingRpc({
      'list_circle_bots': (_) => bots,
      'bots': (params) {
        bots = [_botJson()];
        return {..._botJson(), 'token': 'the-secret-token'};
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          circleRpcProvider.overrideWithValue(rpc.call),
          circleFunctionProvider.overrideWithValue(rpc.call),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CircleBotsSection(detail: _detail()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bot-create-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bot-name-field')),
      'Helper',
    );
    await tester.tap(find.byKey(const ValueKey('bot-role-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Helpers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bot-create-submit')));
    await tester.pumpAndSettle();

    final create = rpc.calls.firstWhere(
      (call) => call.$1 == 'bots',
    );
    expect(create.$2['role_id'], 'role-1');
    expect(find.text('Bot created'), findsOneWidget);
    expect(find.text('the-secret-token'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('the-secret-token'), findsNothing);
    expect(find.text('Helper'), findsOneWidget);
    expect(find.textContaining('2 commands'), findsOneWidget);
  });

  testWidgets('bots show a BOT badge next to their name', (tester) async {
    final rpc = RecordingRpc({
      'list_profile_badges': (_) => [
        {'user_id': 'bot-user', 'is_bot': true},
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
        child: const MaterialApp(
          home: Scaffold(body: ProfileNameBadges(userId: 'bot-user')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('BOT'), findsOneWidget);
    expect(
      ProfileBadges.fromJson({'user_id': 'x', 'is_bot': true}).isEmpty,
      isFalse,
    );
    expect(CircleRole, isNotNull);
  });
}
