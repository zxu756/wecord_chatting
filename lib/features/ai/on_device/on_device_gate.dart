import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/ai_models.dart';

/// The rules the `ai` function enforces before it reads a chat, kept for the
/// on-device model too, so choosing the device cannot get round them:
///
/// * the person's own AI switch (Settings → AI);
/// * the circle's or group's AI switch and advanced chat privacy (G6), which
///   is the database's `conversation_ai_allowed`, the same question the
///   function asks;
/// * chats the person locked (G2), and the threads of one.
///
/// Throws the same exceptions the function's errors turn into. A rule that
/// cannot be checked (offline) counts as not allowed: private chats are never
/// read on a guess.
abstract interface class OnDeviceAiGate {
  /// Throws when AI may not read or process text of [conversationId] (null for
  /// text that belongs to no chat, such as a draft or a picture's text).
  Future<void> check({String? conversationId});
}

/// The gate on the app's state and the Supabase client.
class AppOnDeviceAiGate implements OnDeviceAiGate {
  AppOnDeviceAiGate({
    required this.aiEnabled,
    required this.lockedChatIds,
    required this.conversationAllowed,
    required this.threadParent,
  });

  /// The person's own switch.
  final bool Function() aiEnabled;

  /// The chats the person locked.
  final Set<String> Function() lockedChatIds;

  /// The database's answer for [conversationId]: false when the circle,
  /// group or advanced chat privacy keeps AI out.
  final Future<bool> Function(String conversationId) conversationAllowed;

  /// The chat a thread belongs to, null for a chat that is not a thread.
  final Future<String?> Function(String conversationId) threadParent;

  @override
  Future<void> check({String? conversationId}) async {
    if (!aiEnabled()) {
      throw const AiTurnedOffException();
    }
    if (conversationId == null) {
      return;
    }
    final locked = lockedChatIds();
    if (locked.isNotEmpty) {
      if (locked.contains(conversationId)) {
        throw const AiChatLockedException();
      }
      final String? parent;
      try {
        parent = await threadParent(conversationId);
      } on Object {
        throw const AiFailedException();
      }
      if (parent != null && locked.contains(parent)) {
        throw const AiChatLockedException();
      }
    }
    final bool allowed;
    try {
      allowed = await conversationAllowed(conversationId);
    } on Object {
      throw const AiFailedException();
    }
    if (!allowed) {
      throw const AiDisabledInCircleException();
    }
  }
}

/// [AppOnDeviceAiGate]'s two database questions on [client].
Future<bool> supabaseConversationAllowed(
  SupabaseClient client,
  String conversationId,
) async {
  final answer = await client.rpc(
    'conversation_ai_allowed',
    params: {'target_conversation_id': conversationId},
  );
  // The function answers false only when AI is kept out.
  return answer != false;
}

Future<String?> supabaseThreadParent(
  SupabaseClient client,
  String conversationId,
) async {
  final row = await client
      .from('conversation_threads')
      .select('parent_conversation_id')
      .eq('conversation_id', conversationId)
      .maybeSingle();
  return row?['parent_conversation_id'] as String?;
}
