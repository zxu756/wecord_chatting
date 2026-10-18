import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/message.dart';

/// Answers the report calls and records them. Anything without an answer
/// fails, like an offline server.
class FakeReportRpc {
  final calls = <(String, Map<String, dynamic>)>[];
  final results = <String, Object?>{};

  /// A function that fails with this error.
  final failing = <String, Object>{};

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    final error = failing[name];
    if (error != null) {
      throw error;
    }
    if (!results.containsKey(name)) {
      throw StateError('Supabase must be initialized first.');
    }
    return results[name];
  }

  List<Override> get overrides => [circleRpcProvider.overrideWithValue(call)];

  Iterable<Map<String, dynamic>> callsOf(String name) => [
    for (final (called, params) in calls)
      if (called == name) params,
  ];
}

PostgrestException postgrestError(String code, [String message = 'no']) =>
    PostgrestException(message: message, code: code);

/// A message by someone else, as the menu sees it.
ChatMessage otherMessage({
  String id = 'm1',
  MessageType type = MessageType.text,
  String body = 'buy my pills',
  DateTime? recalledAt,
}) => ChatMessage(
  id: id,
  conversationId: 'c1',
  senderId: 'user-eve',
  type: type,
  body: body,
  createdAt: DateTime.utc(2026, 10, 20, 10),
  recalledAt: recalledAt,
);

/// A report as list_circle_message_reports returns it.
Map<String, dynamic> circleReportJson({
  String id = 'report-1',
  String reason = 'spam',
  String details = '',
  String body = 'Win cheap pills at pills.example',
  String reporter = 'Dee',
  String reported = 'Eve',
  int repeat = 1,
  bool available = true,
  bool withContext = true,
  Map<String, dynamic>? attachment,
  String createdAt = '2026-10-20T11:30:00Z',
}) => {
  'id': id,
  'status': 'open',
  'reason': reason,
  'details': details,
  'created_at': createdAt,
  'handled_at': null,
  'resolution': null,
  'message_id': 'message-$id',
  'message_available': available,
  'reporter': {'id': 'user-dee', 'name': reporter},
  'reported_user': {'id': 'user-eve', 'name': reported, 'avatar_url': null},
  'snapshot': {
    'kind': 'message',
    'body': body,
    'attachment': attachment,
    'channel_name': 'general',
    'sender_display_name': reported,
    'created_at': '2026-10-20T11:00:00Z',
  },
  'context': withContext
      ? [
          {
            'id': 'x1',
            'sender_name': 'Ada',
            'body': 'anyone selling anything?',
            'created_at': '2026-10-20T10:59:00Z',
            'position': 'before',
          },
          {
            'id': 'x2',
            'sender_name': 'Bart',
            'body': 'please stop',
            'created_at': '2026-10-20T11:01:00Z',
            'position': 'after',
          },
        ]
      : null,
  'repeat_count': repeat,
};
