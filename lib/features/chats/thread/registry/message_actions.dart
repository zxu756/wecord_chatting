// Extension point 1 of the chat page: the message action menu.
//
// The long-press menu on phones and the right-click / hover "More" menu on
// desktop both list what [MessageActionRegistry.actionsFor] returns. A feature
// adds an entry by writing a [MessageActionContribution] in its own file and
// listing it in `message_actions_registrations.dart`; nothing in the bubble or
// the menu needs to change. See "Chat page extension points" in
// docs/design/wecord-design-language.md.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId;
import 'package:wecord/shared/models/message.dart';

/// What a [MessageActionContribution] can look at when the menu opens: the
/// message, who is looking, and the page's handlers for it.
class MessageActionContext {
  const MessageActionContext({
    required this.context,
    required this.message,
    required this.isCurrentUser,
    required this.canCompose,
    required this.canPin,
    required this.canStartThread,
    required this.canModerate,
    required this.isSaved,
    required this.circleId,
    required this.previewUrl,
    required this.onReply,
    required this.onEdit,
    required this.onForward,
    required this.onDelete,
    required this.onPreviewImage,
    required this.onTogglePin,
    required this.onRemoveEmbed,
    this.onOpenThread,
    this.onRemind,
    this.onToggleSaved,
    this.onPublish,
  });

  /// A context inside the message, for providers and navigation.
  final BuildContext context;
  final ChatMessage message;

  /// The message is the current user's own.
  final bool isCurrentUser;

  /// The composer is available, so replying and editing are offered.
  final bool canCompose;
  final bool canPin;

  /// Threads can start from messages in this conversation.
  final bool canStartThread;

  /// The current user moderates the conversation (or made the webhook that
  /// posted the message): "Delete message" on someone else's message.
  final bool canModerate;

  /// The current user saved the message ("Save for later").
  final bool isSaved;

  /// The circle of a channel or its thread; null elsewhere.
  final String? circleId;

  /// The link whose preview card shows under the message, if any.
  final String? previewUrl;

  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final ValueChanged<ChatMessage> onForward;
  final Future<void> Function(ChatMessage message) onDelete;
  final Future<void> Function(ImageAttachment attachment) onPreviewImage;
  final Future<void> Function(ChatMessage message) onTogglePin;
  final Future<void> Function(ChatMessage message) onRemoveEmbed;

  /// Opens (or starts) the message's thread; null where threads are off.
  final Future<void> Function(ChatMessage message)? onOpenThread;

  /// Sets a reminder about the message; null where it cannot have one.
  final Future<void> Function(ChatMessage message)? onRemind;

  /// Saves the message or takes it out of Saved; null where it cannot be
  /// saved.
  final Future<void> Function(ChatMessage message)? onToggleSaved;

  /// Publishes an announcement; null unless the current user may.
  final Future<void> Function(ChatMessage message)? onPublish;

  /// The message was deleted for everyone.
  bool get isRecalled => message.recalledAt != null;

  /// Still being sent (or part of an album that is): there is no stored
  /// message to reply to, react to or delete yet.
  bool get isPending =>
      isPendingMessageId(message.id) ||
      (message.album?.any((item) => isPendingMessageId(item.id)) ?? false);

  /// The app's providers, for a contribution that needs to read one.
  ProviderContainer get container =>
      ProviderScope.containerOf(context, listen: false);
}

/// One feature's entries in the message menu.
class MessageActionContribution {
  const MessageActionContribution({
    required this.id,
    required this.order,
    required this.build,
  });

  /// Unique and stable, e.g. `reply` or `translate`.
  final String id;

  /// Where the entries sit among the others, ascending. The built-in actions
  /// use 100, 200, ... in the order the menu has always had, so pick a number
  /// in between (350 lands between Forward and Translate).
  final int order;

  /// The entries to show for this message; empty when the feature does not
  /// apply to it.
  final Iterable<MessageAction> Function(MessageActionContext ctx) build;
}

/// The message menu's entries, collected from every contribution in `order`.
class MessageActionRegistry {
  MessageActionRegistry(Iterable<MessageActionContribution> contributions)
    : _contributions = _sorted(contributions);

  final List<MessageActionContribution> _contributions;

  /// What can be done with [ctx]'s message, in menu order.
  List<MessageAction> actionsFor(MessageActionContext ctx) {
    return [
      for (final contribution in _contributions) ...contribution.build(ctx),
    ];
  }

  /// The ids in menu order (for tests).
  List<String> get ids => [for (final c in _contributions) c.id];

  static List<MessageActionContribution> _sorted(
    Iterable<MessageActionContribution> contributions,
  ) {
    final list = contributions.toList();
    assert(
      list.map((c) => c.id).toSet().length == list.length,
      'Two message action contributions share an id',
    );
    // List.sort is not stable; the position breaks ties.
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byOrder = a.$2.order.compareTo(b.$2.order);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [for (final (_, contribution) in indexed) contribution];
  }
}
