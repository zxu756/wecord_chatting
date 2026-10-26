// A pretend database for the developer page, the bot search and the bots of a
// group: the same shapes the Postgres functions return, kept in memory so a
// test can change something and see it come back.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/circles/circle_rpc.dart';

Map<String, dynamic> developerBotJson({
  String id = 'bot-1',
  String name = 'Helper',
  String circleName = 'Hike Club',
  bool hasToken = true,
  String? description,
  bool allowDirect = false,
  bool allowGroups = false,
  Map<String, dynamic>? events,
  int callsLastDay = 0,
}) {
  return {
    'id': id,
    'circle_id': 'circle-1',
    'user_id': 'user-$id',
    'name': name,
    'username': 'bot_$id',
    'has_token': hasToken,
    'is_member': true,
    'role_names': <String>[],
    'command_count': 2,
    'created_at': '2026-10-20T08:00:00Z',
    'circle_name': circleName,
    'description': description,
    'allow_direct': allowDirect,
    'allow_groups': allowGroups,
    'events': events ?? {'url': null, 'events': <String>[], 'enabled': false},
    'callback': {'url': null, 'enabled': false},
    'calls_last_day': callsLastDay,
  };
}

Map<String, dynamic> eventsJson({
  String url = 'https://bots.example.com/events',
  List<String> events = const ['message.created', 'message.mentioned'],
  bool enabled = true,
  int dropped = 0,
}) {
  return {
    'url': url,
    'events': events,
    'enabled': enabled,
    'consecutive_failures': enabled ? 0 : 20,
    'dropped_count': dropped,
    'last_success_at': enabled ? '2026-10-28T09:00:00Z' : null,
    'last_error': enabled ? null : 'timeout',
  };
}

Map<String, dynamic> openBotJson({
  String userId = 'bot-user-1',
  String name = 'Trail Guide',
  String? description = 'Answers questions about hikes and weather.',
  bool allowDirect = true,
  bool allowGroups = true,
}) {
  return {
    'user_id': userId,
    'name': name,
    'username': 'bot_${userId.replaceAll('-', '_')}',
    'avatar_url': null,
    'description': description,
    'allow_direct': allowDirect,
    'allow_groups': allowGroups,
  };
}

/// The calls the pretend database answers, with what was asked of it.
class FakeDeveloperBackend {
  FakeDeveloperBackend({
    this.access = true,
    List<Map<String, dynamic>>? bots,
    List<Map<String, dynamic>>? deliveries,
    List<Map<String, dynamic>>? apiCalls,
    List<Map<String, dynamic>>? openBots,
    List<Map<String, dynamic>>? groupBots,
  }) : bots = bots ?? [developerBotJson()],
       deliveries = deliveries ?? [],
       apiCalls = apiCalls ?? [],
       openBots = openBots ?? [openBotJson()],
       groupBots = groupBots ?? [];

  bool access;
  final List<Map<String, dynamic>> bots;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> apiCalls;
  final List<Map<String, dynamic>> openBots;
  final List<Map<String, dynamic>> groupBots;

  /// Every call, in order: name and arguments.
  final calls = <(String, Map<String, dynamic>)>[];

  /// A function that should fail, by name.
  final failing = <String>{};

  List<Map<String, dynamic>> callsOf(String name) => [
    for (final (called, params) in calls)
      if (called == name) params,
  ];

  Map<String, dynamic> _bot(String id) =>
      bots.firstWhere((bot) => bot['id'] == id);

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    if (failing.contains(name)) {
      throw StateError('$name failed');
    }
    switch (name) {
      case 'my_developer_access':
        return access;
      case 'list_my_developer_bots':
        return bots;
      case 'get_bot_event_subscription':
        return _bot(params['target_bot_id'] as String)['events'];
      case 'set_bot_event_subscription':
        final bot = _bot(params['target_bot_id'] as String);
        final isNew = (bot['events'] as Map)['url'] == null;
        bot['events'] = eventsJson(
          url: params['event_url'] as String,
          events: List<String>.from(params['event_names'] as List),
        );
        return {
          ...(bot['events'] as Map<String, dynamic>),
          if (isNew) 'secret': 'sec_first_0123456789',
        };
      case 'rotate_bot_event_secret':
        return {
          ...(_bot(params['target_bot_id'] as String)['events']
              as Map<String, dynamic>),
          'secret': 'sec_second_9876543210',
        };
      case 'clear_bot_event_subscription':
        _bot(params['target_bot_id'] as String)['events'] = {
          'url': null,
          'events': <String>[],
          'enabled': false,
        };
        return null;
      case 'send_bot_test_event':
        return null;
      case 'list_bot_event_deliveries':
        return deliveries;
      case 'list_bot_api_calls':
        return apiCalls;
      case 'set_bot_availability':
        final bot = _bot(params['target_bot_id'] as String);
        final text = (params['bot_description'] as String).trim();
        bot['description'] = text.isEmpty ? null : text;
        bot['allow_direct'] = params['direct_chats'];
        bot['allow_groups'] = params['group_chats'];
        return null;
      case 'regenerate_bot_token':
        return {
          ..._bot(params['target_bot_id'] as String),
          'token': 'wcb_new_token_value',
        };
      case 'revoke_bot_token':
        _bot(params['target_bot_id'] as String)['has_token'] = false;
        return null;
      case 'get_bot_callback':
        return {'url': null, 'enabled': false};
      case 'search_open_bots':
        final needle = (params['search_text'] as String).toLowerCase();
        return [
          for (final bot in openBots)
            if ((bot['name'] as String).toLowerCase().contains(needle)) bot,
        ];
      case 'list_group_bots':
        return groupBots;
      case 'add_bot_to_group':
        final bot = openBots.firstWhere(
          (bot) => bot['user_id'] == params['target_bot_user_id'],
        );
        groupBots.add(bot);
        return null;
      case 'remove_bot_from_group':
        groupBots.removeWhere(
          (bot) => bot['user_id'] == params['target_bot_user_id'],
        );
        return null;
    }
    throw StateError('Unexpected $name');
  }

  Override get override => circleRpcProvider.overrideWithValue(call);
}
