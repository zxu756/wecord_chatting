import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';

/// The kinds of event a bot can subscribe to, in the order they are listed.
/// The names are what the bot receives (`event`), so they stay in English.
const botEventKinds = <String>[
  'message.created',
  'message.mentioned',
  'message.updated',
  'message.deleted',
  'reaction.added',
  'member.joined',
  'member.left',
  'interaction.created',
];

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// Where a bot's events are sent (an event subscription), as its managers see
/// it. The secret is only there right after it was made.
class BotEventSubscription {
  const BotEventSubscription({
    this.url,
    this.events = const [],
    this.enabled = false,
    this.consecutiveFailures = 0,
    this.lastStatus,
    this.lastError,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.droppedCount = 0,
    this.secret,
  });

  factory BotEventSubscription.fromJson(Map<String, dynamic> json) {
    return BotEventSubscription(
      url: json['url'] as String?,
      events: [
        for (final name in json['events'] as List<dynamic>? ?? const [])
          name as String,
      ],
      enabled: json['enabled'] == true,
      consecutiveFailures: (json['consecutive_failures'] as num?)?.toInt() ?? 0,
      lastStatus: (json['last_status'] as num?)?.toInt(),
      lastError: json['last_error'] as String?,
      lastSuccessAt: _time(json['last_success_at']),
      lastFailureAt: _time(json['last_failure_at']),
      droppedCount: (json['dropped_count'] as num?)?.toInt() ?? 0,
      secret: json['secret'] as String?,
    );
  }

  /// The address events are sent to; null when the bot has no subscription.
  final String? url;
  final List<String> events;

  /// False when it was paused after too many failures or because the person
  /// who set it no longer manages the circle.
  final bool enabled;
  final int consecutiveFailures;
  final int? lastStatus;
  final String? lastError;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  /// Events that were not queued because the bot was too busy.
  final int droppedCount;

  /// Shown once, when the subscription is first made or its secret is reset.
  final String? secret;

  bool get isSet => url != null;
}

/// A bot as the developer page shows it.
class DeveloperBot {
  const DeveloperBot({
    required this.bot,
    required this.circleName,
    this.description,
    this.allowDirect = false,
    this.allowGroups = false,
    this.events = const BotEventSubscription(),
    this.callback = const BotCallback(),
    this.callsLastDay = 0,
    this.lastCallAt,
  });

  factory DeveloperBot.fromJson(Map<String, dynamic> json) {
    return DeveloperBot(
      bot: CircleBot.fromJson(json),
      circleName: json['circle_name'] as String? ?? '',
      description: json['description'] as String?,
      allowDirect: json['allow_direct'] == true,
      allowGroups: json['allow_groups'] == true,
      events: switch (json['events']) {
        final Map<dynamic, dynamic> map => BotEventSubscription.fromJson(
          Map<String, dynamic>.from(map),
        ),
        _ => const BotEventSubscription(),
      },
      callback: switch (json['callback']) {
        final Map<dynamic, dynamic> map => BotCallback.fromJson(
          Map<String, dynamic>.from(map),
        ),
        _ => const BotCallback(),
      },
      callsLastDay: (json['calls_last_day'] as num?)?.toInt() ?? 0,
      lastCallAt: _time(json['last_call_at']),
    );
  }

  final CircleBot bot;
  final String circleName;
  final String? description;

  /// People may start a direct chat with the bot.
  final bool allowDirect;

  /// A group's owner may add the bot to the group.
  final bool allowGroups;
  final BotEventSubscription events;
  final BotCallback callback;
  final int callsLastDay;
  final DateTime? lastCallAt;

  String get id => bot.id;
  String get name => bot.name;

  bool get isOpen => allowDirect || allowGroups;
}

/// What happened to one event sent to a bot's address. Never what was in it.
class BotEventDelivery {
  const BotEventDelivery({
    required this.id,
    required this.event,
    required this.state,
    required this.attempts,
    required this.createdAt,
    this.status,
    this.error,
    this.deliveredAt,
  });

  factory BotEventDelivery.fromJson(Map<String, dynamic> json) {
    return BotEventDelivery(
      id: json['id'] as String,
      event: json['event'] as String? ?? '',
      state: json['state'] as String? ?? 'queued',
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      status: (json['status'] as num?)?.toInt(),
      error: json['error'] as String?,
      createdAt: _time(json['created_at']) ?? DateTime.now().toUtc(),
      deliveredAt: _time(json['delivered_at']),
    );
  }

  final String id;
  final String event;

  /// queued, sending, delivered, failed or dropped.
  final String state;
  final int attempts;
  final int? status;
  final String? error;
  final DateTime createdAt;
  final DateTime? deliveredAt;

  bool get isDelivered => state == 'delivered';
  bool get isWaiting => state == 'queued' || state == 'sending';
}

/// One call a bot made to the bot API: the method, the endpoint as a template
/// and the HTTP status.
class BotApiCall {
  const BotApiCall({
    required this.at,
    required this.method,
    required this.route,
    required this.status,
  });

  factory BotApiCall.fromJson(Map<String, dynamic> json) {
    return BotApiCall(
      at: _time(json['at']) ?? DateTime.now().toUtc(),
      method: json['method'] as String? ?? '',
      route: json['route'] as String? ?? '',
      status: (json['status'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime at;
  final String method;
  final String route;
  final int status;

  bool get succeeded => status >= 200 && status < 400;
}

/// A bot that is open to people outside its circle (found by search), or one
/// that is in a group.
class OpenBot {
  const OpenBot({
    required this.userId,
    required this.name,
    this.username = '',
    this.avatarUrl,
    this.description,
    this.allowDirect = false,
    this.allowGroups = false,
  });

  factory OpenBot.fromJson(Map<String, dynamic> json) {
    return OpenBot(
      userId: json['user_id'] as String,
      name: json['name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      description: json['description'] as String?,
      allowDirect: json['allow_direct'] == true,
      allowGroups: json['allow_groups'] == true,
    );
  }

  final String userId;
  final String name;
  final String username;
  final String? avatarUrl;
  final String? description;
  final bool allowDirect;
  final bool allowGroups;
}

final developerRepositoryProvider = Provider<DeveloperRepository>((ref) {
  return DeveloperRepository(ref.watch(circleRpcProvider));
});

/// Whether the person manages a circle, so the developer page is theirs.
/// False when it cannot be told (the entry stays hidden).
final developerAccessProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(developerRepositoryProvider).hasAccess();
  } on Object {
    return false;
  }
});

/// The bots of every circle the person manages.
final developerBotsProvider = FutureProvider.autoDispose<List<DeveloperBot>>((
  ref,
) {
  return ref.watch(developerRepositoryProvider).listBots();
});

/// The latest events sent to a bot's address, and how each went.
final botDeliveriesProvider = FutureProvider.autoDispose
    .family<List<BotEventDelivery>, String>((ref, botId) {
      return ref.watch(developerRepositoryProvider).listDeliveries(botId);
    });

/// The latest calls a bot made to the bot API.
final botApiCallsProvider = FutureProvider.autoDispose
    .family<List<BotApiCall>, String>((ref, botId) {
      return ref.watch(developerRepositoryProvider).listCalls(botId);
    });

/// The bots in a group chat.
final groupBotsProvider = FutureProvider.autoDispose
    .family<List<OpenBot>, String>((ref, chatId) {
      return ref.watch(developerRepositoryProvider).listGroupBots(chatId);
    });

class DeveloperRepository {
  const DeveloperRepository(this._rpc);

  final CircleRpc _rpc;

  Future<bool> hasAccess() async {
    return await _rpc('my_developer_access', const {}) == true;
  }

  Future<List<DeveloperBot>> listBots() async {
    final rows = await _rpc('list_my_developer_bots', const {});
    return rpcRows(rows).map(DeveloperBot.fromJson).toList();
  }

  Future<BotEventSubscription> getSubscription(String botId) async {
    return BotEventSubscription.fromJson(
      rpcObject(
        await _rpc('get_bot_event_subscription', {'target_bot_id': botId}),
      ),
    );
  }

  /// Sets the address and the kinds of event. The first time, the result
  /// carries the secret that signs the events; saving a paused subscription
  /// turns it on again.
  Future<BotEventSubscription> setSubscription(
    String botId, {
    required String url,
    required List<String> events,
  }) async {
    return BotEventSubscription.fromJson(
      rpcObject(
        await _rpc('set_bot_event_subscription', {
          'target_bot_id': botId,
          'event_url': url.trim(),
          'event_names': events,
        }),
      ),
    );
  }

  /// Makes a new secret; the old one stops working.
  Future<BotEventSubscription> rotateSecret(String botId) async {
    return BotEventSubscription.fromJson(
      rpcObject(
        await _rpc('rotate_bot_event_secret', {'target_bot_id': botId}),
      ),
    );
  }

  /// Forgets the subscription; what waited is dropped.
  Future<void> clearSubscription(String botId) async {
    await _rpc('clear_bot_event_subscription', {'target_bot_id': botId});
  }

  /// Queues a test event for the bot's address.
  Future<void> sendTestEvent(String botId) async {
    await _rpc('send_bot_test_event', {'target_bot_id': botId});
  }

  Future<List<BotEventDelivery>> listDeliveries(String botId) async {
    final rows = await _rpc('list_bot_event_deliveries', {
      'target_bot_id': botId,
      'max_count': 30,
    });
    return rpcRows(rows).map(BotEventDelivery.fromJson).toList();
  }

  Future<List<BotApiCall>> listCalls(String botId) async {
    final rows = await _rpc('list_bot_api_calls', {
      'target_bot_id': botId,
      'max_count': 30,
    });
    return rpcRows(rows).map(BotApiCall.fromJson).toList();
  }

  /// Who may use the bot outside its circle, and what it says about itself.
  Future<void> setAvailability(
    String botId, {
    required String description,
    required bool direct,
    required bool groups,
  }) async {
    await _rpc('set_bot_availability', {
      'target_bot_id': botId,
      'bot_description': description.trim(),
      'direct_chats': direct,
      'group_chats': groups,
    });
  }

  /// Bots that are open to the person, found by name or username.
  Future<List<OpenBot>> searchBots(String text) async {
    final rows = await _rpc('search_open_bots', {'search_text': text.trim()});
    return rpcRows(rows).map(OpenBot.fromJson).toList();
  }

  Future<List<OpenBot>> listGroupBots(String chatId) async {
    final rows = await _rpc('list_group_bots', {
      'target_conversation_id': chatId,
    });
    return rpcRows(rows).map(OpenBot.fromJson).toList();
  }

  Future<void> addBotToGroup(String chatId, String botUserId) async {
    await _rpc('add_bot_to_group', {
      'target_conversation_id': chatId,
      'target_bot_user_id': botUserId,
    });
  }

  Future<void> removeBotFromGroup(String chatId, String botUserId) async {
    await _rpc('remove_bot_from_group', {
      'target_conversation_id': chatId,
      'target_bot_user_id': botUserId,
    });
  }
}
