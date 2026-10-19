// Strings and small text helpers of the chat thread: the composer's hint,
// subtitles, thread titles and the quoted text of a reply.
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/message.dart';

/// The composer's placeholder: "Message #general" in a channel, "Message
/// @Ada" in a direct chat and "Message Weekend crew" in a group or thread;
/// plain "Message" while the name is unknown.
String composerHint(ConversationType? type, String title) {
  var name = title.trim();
  if (type == ConversationType.channel) {
    // Channel routes pass "# general".
    name = name.replaceFirst(RegExp(r'^#\s*'), '');
  }
  if (name.isEmpty || name == tr('Conversation')) {
    return tr('Message');
  }
  return switch (type) {
    ConversationType.channel => tr('Message #{name}', {'name': name}),
    ConversationType.direct => tr('Message @{name}', {'name': name}),
    _ => tr('Message {name}', {'name': name}),
  };
}

/// "in #channel" (or "in Group") under a thread's title.
String threadSubtitle(ConversationSummary? summary) {
  final parentTitle = summary?.parentTitle?.trim();
  if (parentTitle == null || parentTitle.isEmpty) {
    return tr('Thread');
  }
  final archived = summary?.threadArchivedAt != null;
  final args = {'parent': parentTitle};
  return switch ((summary?.circleId != null, archived)) {
    (true, true) => tr('in #{parent} · Archived', args),
    (true, false) => tr('in #{parent}', args),
    (false, true) => tr('in {parent} · Archived', args),
    (false, false) => tr('in {parent}', args),
  };
}

String suggestedTitleFor(ChatMessage message) {
  return switch (message.type) {
    MessageType.text => suggestedThreadTitle(
      plainTextFromMarkdown(message.body),
    ),
    MessageType.image => tr('Image'),
    MessageType.voice => tr('Voice message'),
    MessageType.file =>
      message.fileAttachment?.isVideo == true ? tr('Video') : tr('File'),
    MessageType.system => tr('Thread'),
    MessageType.poll => suggestedThreadTitle(message.body),
    MessageType.sticker => tr('Sticker'),
  };
}

/// How long ago a thread was last active: "just now", "5m ago", "3h ago",
/// then the date.
String formatThreadActivity(DateTime value, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final difference = current.difference(value.toUtc());
  if (difference.inMinutes < 1) {
    return tr('just now');
  }
  if (difference.inHours < 1) {
    return tr('{minutes}m ago', {'minutes': difference.inMinutes});
  }
  if (difference.inDays < 1) {
    return tr('{hours}h ago', {'hours': difference.inHours});
  }
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}

/// A slowmode wait as `45s`, `2:05` or `1:00:00`.
String formatSlowmodeCountdown(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$rest';
  }
  return '$minutes:$rest';
}

ReplyPreview replyPreviewForMessage(ChatMessage message, {ReplyQuote? quote}) {
  return ReplyPreview(
    messageId: message.id,
    senderName: 'Message',
    body: replyPreviewBody(message),
    type: message.type,
    quote: quote,
  );
}

/// The quoted text of a reply to [message]. What is sent stays English, as
/// every reader sees it; the composer shows it [localized].
String replyPreviewBody(ChatMessage message, {bool localized = false}) {
  String label(String english) => localized ? tr(english) : english;
  if (message.recalledAt != null) {
    return label('Message');
  }
  return switch (message.type) {
    MessageType.text =>
      message.body.trim().isEmpty
          ? label('Message')
          : plainTextFromMarkdown(message.body.trim()),
    MessageType.system =>
      message.body.trim().isEmpty ? label('Message') : message.body.trim(),
    MessageType.image => label('Image'),
    MessageType.file => label('File'),
    MessageType.voice => label('Voice message'),
    MessageType.poll => pollPreviewText(message.body),
    MessageType.sticker => stickerPreviewText(message.body),
  };
}
