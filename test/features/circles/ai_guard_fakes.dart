import 'package:wecord/features/circles/circle_automod_repository.dart'
    show RpcDataSource;
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/profile.dart';

class FakeGuardRpc implements RpcDataSource {
  final calls = <({String name, Map<String, dynamic> params})>[];
  final results = <String, Object?>{};

  /// Functions that fail.
  final failing = <String>{};

  List<Map<String, dynamic>> guardCalls(String name) => [
    for (final call in calls)
      if (call.name == name) call.params,
  ];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add((name: functionName, params: params));
    if (failing.contains(functionName)) {
      throw Exception('boom');
    }
    if (functionName == 'set_circle_ai_guard') {
      // The server answers with what was saved.
      return {
        'enabled': params['guard_enabled'],
        'new_rule': params['guard_new_rule'],
        'joined_days': params['guard_joined_days'],
        'message_count': params['guard_message_count'],
        'action': params['guard_action'],
        'circle_ai_enabled':
            (results['get_circle_ai_guard']! as Map)['circle_ai_enabled'],
      };
    }
    return results[functionName];
  }
}

Map<String, dynamic> guardJson({
  bool enabled = false,
  String rule = 'joined_days',
  int days = 3,
  int count = 10,
  String action = 'hold',
  bool circleAi = true,
}) => {
  'enabled': enabled,
  'new_rule': rule,
  'joined_days': days,
  'message_count': count,
  'action': action,
  'circle_ai_enabled': circleAi,
};

Map<String, dynamic> reviewJson({
  String id = 'message-1',
  String state = 'held',
  String verdict = 'spam',
  String? reason = 'Sells pills',
  String body = 'Cheap pills at pills.example',
}) => {
  'message_id': id,
  'conversation_id': 'conversation-1',
  'channel_id': 'channel-1',
  'channel_name': 'general',
  'sender_id': 'user-9',
  'sender_name': 'Newt',
  'sender_avatar_url': null,
  'body': body,
  'state': state,
  'verdict': verdict,
  'reason': reason,
  'sent_at': DateTime.utc(2026, 5, 18, 4, 0).toIso8601String(),
  'checked_at': DateTime.utc(2026, 5, 18, 4, 0, 2).toIso8601String(),
};

CircleDetail detail({int permissions = CirclePermission.all}) {
  final owner = Profile(
    id: 'user-1',
    username: 'ada',
    displayName: 'Ada',
    bio: '',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  return CircleDetail(
    circle: CircleSummary(
      id: 'circle-1',
      name: 'Book Club',
      memberCount: 1,
      channelCount: 1,
      currentUserRole: 'member',
      currentUserPermissions: permissions,
    ),
    members: [CircleMember(profile: owner, role: 'member')],
    channels: const [],
    posts: const [],
    roles: const [],
  );
}
