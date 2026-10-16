import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/shared/models/conversation.dart';

/// A message to scroll to (and briefly highlight) once its conversation
/// is open: set before opening the conversation; the chat thread takes it.
class MessageJump {
  const MessageJump({required this.conversationId, required this.messageId});

  final String conversationId;
  final String messageId;
}

final pendingMessageJumpProvider = StateProvider<MessageJump?>((ref) => null);

/// Opens [conversation] where it lives, scrolled to [messageId].
void openConversationAtMessage(
  BuildContext context,
  WidgetRef ref, {
  required ConversationSummary conversation,
  required String messageId,
}) {
  ref.read(pendingMessageJumpProvider.notifier).state = MessageJump(
    conversationId: conversation.id,
    messageId: messageId,
  );
  openConversation(context, conversation);
}

/// The jump waiting for [conversationId], taken (cleared) so it happens
/// once; null when there is none.
String? takePendingMessageJump(WidgetRef ref, String conversationId) {
  final jump = ref.read(pendingMessageJumpProvider);
  if (jump == null || jump.conversationId != conversationId) {
    return null;
  }
  ref.read(pendingMessageJumpProvider.notifier).state = null;
  return jump.messageId;
}
