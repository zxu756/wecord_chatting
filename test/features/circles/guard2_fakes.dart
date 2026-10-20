// Fakes for the AI guard 2.0 tests and screenshots.

/// A fake `CircleRpc` for the AI guard 2.0 functions.
class FakeGuard2Rpc {
  final calls = <({String name, Map<String, dynamic> params})>[];
  final results = <String, Object?>{};
  final failing = <String>{};

  List<Map<String, dynamic>> callsTo(String name) => [
    for (final call in calls)
      if (call.name == name) call.params,
  ];

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add((name: name, params: params));
    if (failing.contains(name)) {
      throw Exception('boom');
    }
    if (name == 'set_circle_ai_guard_scope') {
      return {
        'check_polls': params['scope_polls'],
        'check_items': params['scope_items'],
        'check_images': params['scope_images'],
        'vision_available':
            (results['get_circle_ai_guard_scope']! as Map)['vision_available'],
      };
    }
    return results[name];
  }
}

Map<String, dynamic> scopeJson({
  bool polls = true,
  bool items = true,
  bool images = false,
  bool vision = false,
}) => {
  'check_polls': polls,
  'check_items': items,
  'check_images': images,
  'vision_available': vision,
};

Map<String, dynamic> itemJson({
  String id = 'item-1',
  String type = 'note',
  String title = 'Win a free prize',
  String detail = '',
  String verdict = 'scam',
  String reason = 'Fake prize',
  String? reasonZh,
}) => {
  'id': id,
  'item_type': type,
  'item_id': 'note-1',
  'conversation_id': 'conversation-1',
  'channel_id': 'channel-1',
  'channel_name': 'general',
  'actor_id': 'user-9',
  'actor_name': 'Newt',
  'actor_avatar_url': null,
  'title': title,
  'detail': detail,
  'verdict': verdict,
  'reason': reason,
  'reason_zh': reasonZh,
  'flagged_at': DateTime.utc(2026, 10, 20, 4).toIso8601String(),
};
