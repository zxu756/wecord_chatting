import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// A bot account of a circle, as its managers see it.
class CircleBot {
  const CircleBot({
    required this.id,
    required this.circleId,
    required this.userId,
    required this.name,
    required this.createdAt,
    this.username = '',
    this.hasToken = true,
    this.isMember = true,
    this.roleNames = const [],
    this.commandCount = 0,
    this.creatorName,
    this.lastUsedAt,
  });

  factory CircleBot.fromJson(Map<String, dynamic> json) {
    return CircleBot(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      username: json['username'] as String? ?? '',
      hasToken: json['has_token'] != false,
      isMember: json['is_member'] != false,
      roleNames: [
        for (final name in json['role_names'] as List<dynamic>? ?? const [])
          name as String,
      ],
      commandCount: (json['command_count'] as num?)?.toInt() ?? 0,
      creatorName: json['creator_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      lastUsedAt: switch (json['last_used_at']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
    );
  }

  static const maxNameLength = 32;

  final String id;
  final String circleId;

  /// The bot's profile, which sends its messages.
  final String userId;
  final String name;
  final String username;

  /// False once its token was revoked (until a new one is made).
  final bool hasToken;

  /// False when a moderator removed it from the circle.
  final bool isMember;
  final List<String> roleNames;
  final int commandCount;
  final String? creatorName;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// A bot with its token, which is shown only once.
class CircleBotSecret {
  const CircleBotSecret({required this.bot, required this.token});

  factory CircleBotSecret.fromJson(Map<String, dynamic> json) {
    return CircleBotSecret(
      bot: CircleBot.fromJson(json),
      token: json['token'] as String,
    );
  }

  final CircleBot bot;
  final String token;
}

/// What happened when a member used a bot's command.
class BotCommandInvocation {
  const BotCommandInvocation({required this.botName, required this.command});

  final String botName;
  final String command;
}

final circleBotRepositoryProvider = Provider<CircleBotRepository>((ref) {
  return CircleBotRepository(
    ref.watch(circleRpcProvider),
    ref.watch(circleFunctionProvider),
  );
});

/// A circle's bots, for its managers.
final circleBotsProvider = FutureProvider.autoDispose
    .family<List<CircleBot>, String>((ref, circleId) {
      return ref.watch(circleBotRepositoryProvider).listBots(circleId);
    });

/// The commands of a circle's bots, offered in its channels' composers;
/// empty when they cannot be loaded.
final circleBotCommandsProvider = FutureProvider.autoDispose
    .family<List<BotSlashCommand>, String>((ref, circleId) async {
      try {
        return await ref
            .watch(circleBotRepositoryProvider)
            .listCommands(circleId);
      } catch (_) {
        return const [];
      }
    });

class CircleBotRepository {
  const CircleBotRepository(this._rpc, this._function);

  final CircleRpc _rpc;
  final CircleFunction _function;

  Future<List<CircleBot>> listBots(String circleId) async {
    final rows = await _rpc('list_circle_bots', {'target_circle_id': circleId});
    return rpcRows(rows).map(CircleBot.fromJson).toList();
  }

  /// Creates a bot in the circle, with [roleId] when given; the returned
  /// token is never shown again. The `bots` Edge Function makes the bot's
  /// login, then create_circle_bot checks the caller's permissions.
  Future<CircleBotSecret> createBot({
    required String circleId,
    required String name,
    String? roleId,
  }) async {
    final result = await _function('bots', {
      'circle_id': circleId,
      'name': name.trim(),
      'role_id': roleId,
    });
    return CircleBotSecret.fromJson(rpcObject(result));
  }

  /// Replaces the bot's token; the old one stops working.
  Future<CircleBotSecret> regenerateToken(String botId) async {
    final result = await _rpc('regenerate_bot_token', {'target_bot_id': botId});
    return CircleBotSecret.fromJson(rpcObject(result));
  }

  /// Turns the bot's token off until a new one is made.
  Future<void> revokeToken(String botId) async {
    await _rpc('revoke_bot_token', {'target_bot_id': botId});
  }

  /// Removes the bot from the circle and deletes its login; its messages
  /// stay. The `bots` Edge Function runs delete_circle_bot as the caller,
  /// then deletes the login with the service role.
  Future<void> deleteBot(String botId) async {
    await _function('bots', {'action': 'delete', 'bot_id': botId});
  }

  Future<List<BotSlashCommand>> listCommands(String circleId) async {
    final rows = await _rpc('list_circle_bot_commands', {
      'target_circle_id': circleId,
    });
    return rpcRows(rows).map(BotSlashCommand.fromJson).toList();
  }

  /// Sends the bot an interaction for [command] in a channel.
  Future<BotCommandInvocation> invoke({
    required String conversationId,
    required String command,
    String options = '',
  }) async {
    final result = rpcObject(
      await _rpc('invoke_bot_command', {
        'target_conversation_id': conversationId,
        'command_name': command,
        'command_options': options,
      }),
    );
    return BotCommandInvocation(
      botName: result['bot_name'] as String? ?? '',
      command: result['command'] as String? ?? command,
    );
  }
}
