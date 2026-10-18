import 'package:wecord/features/circles/circle_rpc.dart';

/// Answers the database functions behind the member guide; unknown ones fail,
/// as an uninitialized Supabase client would.
class GuideRpc {
  GuideRpc();

  final handlers = <String, Object? Function(Map<String, dynamic> params)>{};
  final calls = <(String, Map<String, dynamic>)>[];

  CircleRpc get call => _call;

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    final handler = handlers[name];
    if (handler == null) {
      throw StateError('Unexpected $name');
    }
    return handler(params);
  }

  List<Map<String, dynamic>> paramsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];

  void answer(String name, Object? value) => handlers[name] = (_) => value;
}

Map<String, dynamic> guideOptionJson({
  String id = 'opt-chess',
  String label = 'Chess',
  String? emoji,
  bool selected = false,
  List<Map<String, dynamic>> roles = const [],
  List<Map<String, dynamic>> channels = const [],
}) => {
  'id': id,
  'label': label,
  'emoji': emoji,
  'selected': selected,
  'roles': roles,
  'channels': channels,
};

Map<String, dynamic> guidePromptJson({
  String id = 'prompt-1',
  String title = 'What do you play?',
  bool required = false,
  bool singleSelect = false,
  List<Map<String, dynamic>>? options,
}) => {
  'id': id,
  'title': title,
  'required': required,
  'single_select': singleSelect,
  'options':
      options ??
      [
        guideOptionJson(
          emoji: '♟',
          roles: [
            {'id': 'role-photo', 'name': 'Photographers', 'color': 0x3366FF},
          ],
          channels: [
            {'id': 'ch-games', 'name': 'games'},
          ],
        ),
        guideOptionJson(id: 'opt-go', label: 'Go'),
      ],
};

Map<String, dynamic> guideTaskJson({
  String id = 'task-1',
  String title = 'Read the rules',
  String action = 'read_rules',
  String? channelId,
  String? channelName,
  bool done = false,
}) => {
  'id': id,
  'title': title,
  'action': action,
  'channel_id': channelId,
  'channel_name': channelName,
  'done': done,
};

/// A get_circle_guide result.
Map<String, dynamic> guideJson({
  List<Map<String, dynamic>>? prompts,
  List<Map<String, dynamic>>? tasks,
  bool answered = false,
  bool dismissed = false,
  bool needsAnswers = false,
  bool newMember = true,
}) {
  final promptList = prompts ?? [guidePromptJson()];
  final taskList =
      tasks ??
      [
        guideTaskJson(done: true),
        guideTaskJson(
          id: 'task-2',
          title: 'Have a look around',
          action: 'visit_channel',
          channelId: 'ch-general',
          channelName: 'general',
        ),
        guideTaskJson(
          id: 'task-3',
          title: 'Add a profile picture',
          action: 'set_avatar',
        ),
      ];
  return {
    'enabled': promptList.isNotEmpty || taskList.isNotEmpty,
    'prompts': promptList,
    'tasks': taskList,
    'answered': answered,
    'dismissed': dismissed,
    'needs_answers': needsAnswers,
    'new_member': newMember,
  };
}

/// A get_circle_guide_config result.
Map<String, dynamic> guideConfigJson({
  List<Map<String, dynamic>>? prompts,
  List<Map<String, dynamic>>? tasks,
  String? greetingChannelId,
  String? greetingStickerId,
  List<String> assignable = const ['role-photo'],
}) => {
  'prompts':
      prompts ??
      [
        {
          'id': 'prompt-1',
          'title': 'What do you play?',
          'required': false,
          'single_select': false,
          'options': [
            {
              'id': 'opt-chess',
              'label': 'Chess',
              'emoji': '♟',
              'role_ids': ['role-photo'],
              'channel_ids': ['ch-general'],
            },
            {
              'id': 'opt-go',
              'label': 'Go',
              'emoji': null,
              'role_ids': <String>[],
              'channel_ids': <String>[],
            },
          ],
        },
      ],
  'tasks':
      tasks ??
      [
        {
          'id': 'task-1',
          'title': 'Read the rules',
          'action': 'read_rules',
          'channel_id': null,
        },
      ],
  'greeting_channel_id': greetingChannelId,
  'greeting_sticker_id': greetingStickerId,
  'assignable_role_ids': assignable,
};
