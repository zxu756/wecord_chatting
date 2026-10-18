import 'package:wecord/features/circles/circle_rpc.dart';

/// Answers the database functions behind join requests; unknown ones fail,
/// as an uninitialized Supabase client would.
class JoinRpc {
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

  /// The parameters of every call to [name].
  List<Map<String, dynamic>> paramsOf(String name) => [
    for (final call in calls)
      if (call.$1 == name) call.$2,
  ];

  /// Makes [name] return [value].
  void answer(String name, Object? value) => handlers[name] = (_) => value;
}

Map<String, dynamic> questionJson({
  String id = 'q1',
  String kind = 'text',
  String prompt = 'Why do you want to join?',
  List<String> options = const [],
  bool required = true,
}) => {
  'id': id,
  'kind': kind,
  'prompt': prompt,
  'options': options,
  'required': required,
};

/// A get_circle_join_state result.
Map<String, dynamic> joinStateJson({
  String circleId = 'circle-9',
  String mode = 'apply',
  bool closed = false,
  bool isMember = false,
  bool skipReview = false,
  List<Map<String, dynamic>>? questions,
  Map<String, dynamic>? request,
  String? retryAt,
}) => {
  'circle_id': circleId,
  'join_mode': mode,
  'closed': closed,
  'is_member': isMember,
  'skip_review': skipReview,
  'questions':
      questions ??
      [
        questionJson(),
        questionJson(
          id: 'q2',
          kind: 'choice',
          prompt: 'How did you find us?',
          options: const ['A friend', 'Search', 'Social media'],
          required: false,
        ),
      ],
  'request': request,
  'retry_at': retryAt,
};

Map<String, dynamic> requestInfoJson({
  String id = 'req-1',
  String status = 'pending',
  String? note,
  bool invited = false,
  String? decidedAt,
}) => {
  'id': id,
  'status': status,
  'created_at': '2026-10-22T08:00:00Z',
  'decided_at': decidedAt,
  'note': note,
  'invited': invited,
};

/// A row of list_join_requests.
Map<String, dynamic> pendingRequestJson({
  String id = 'req-1',
  String name = 'Nia Novak',
  String username = 'nia',
  String? invitedBy,
  List<Map<String, String>>? answers,
}) => {
  'id': id,
  'user_id': 'user-$id',
  'display_name': name,
  'username': username,
  'avatar_url': null,
  'account_created_at': '2026-10-10T08:00:00Z',
  'created_at': '2026-10-22T09:30:00Z',
  'answers':
      answers ??
      [
        {
          'question_id': 'q1',
          'prompt': 'Why do you want to join?',
          'kind': 'text',
          'answer': 'I paint pixel art and want critique.',
        },
        {
          'question_id': 'q2',
          'prompt': 'How did you find us?',
          'kind': 'choice',
          'answer': 'A friend',
        },
      ],
  'invited_by_name': invitedBy,
};

/// A row of list_my_join_requests.
Map<String, dynamic> myRequestJson({
  String id = 'req-1',
  String status = 'pending',
  String circleName = 'Pixel Painters',
  String? note,
  bool isMember = false,
}) => {
  'id': id,
  'circle_id': 'circle-9',
  'circle_name': circleName,
  'circle_avatar_url': null,
  'status': status,
  'note': note,
  'created_at': '2026-10-22T08:00:00Z',
  'decided_at': status == 'pending' ? null : '2026-10-22T09:00:00Z',
  'invited': false,
  'is_member': isMember,
};
