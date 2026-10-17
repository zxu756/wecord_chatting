import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId;
import 'package:wecord/shared/models/message.dart';

/// How many messages can be selected at once: a merged forward holds that
/// many.
const maxSelectedMessages = maxMergedForwardMessages;

/// The messages one list entry stands for: an album is one entry in the
/// list and all its pictures when selected.
List<ChatMessage> selectionUnitsOf(ChatMessage message) =>
    message.album ?? [message];

/// Whether [message] can be ticked: not a system line, not deleted and not
/// still being sent.
bool isSelectable(ChatMessage message) {
  if (message.type == MessageType.system || message.recalledAt != null) {
    return false;
  }
  return !selectionUnitsOf(message).any((unit) => isPendingMessageId(unit.id));
}

/// The state of multi-select in one chat.
class ChatSelectionState {
  const ChatSelectionState({
    this.active = false,
    this.messages = const {},
    this.anchorId,
  });

  /// Whether the chat is in selection mode.
  final bool active;

  /// The selected messages by id, in the order they were ticked.
  final Map<String, ChatMessage> messages;

  /// The message ticked last, where a Shift-click range starts.
  final String? anchorId;

  int get count => messages.length;

  bool isSelected(String id) => messages.containsKey(id);

  /// Whether every message [entry] stands for is selected.
  bool isEntrySelected(ChatMessage entry) {
    return selectionUnitsOf(
      entry,
    ).every((unit) => messages.containsKey(unit.id));
  }

  /// The selected messages, oldest first.
  List<ChatMessage> get ordered {
    final list = messages.values.toList();
    list.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return list;
  }
}

/// Multi-select of one chat: long-press or right-click a message and
/// choose Select, tick more, then act on all of them from the bar.
final chatSelectionProvider = NotifierProvider.autoDispose
    .family<ChatSelectionController, ChatSelectionState, String>(
      ChatSelectionController.new,
    );

class ChatSelectionController extends Notifier<ChatSelectionState> {
  ChatSelectionController(this.conversationId);

  final String conversationId;

  @override
  ChatSelectionState build() => const ChatSelectionState();

  /// Enters selection mode with [message] ticked.
  void begin(ChatMessage message) {
    state = const ChatSelectionState(active: true);
    toggle(message);
  }

  /// Ticks or unticks the message (or the whole album) of a list entry.
  /// Returns false when it could not be ticked because [maxSelectedMessages]
  /// are selected already.
  bool toggle(ChatMessage entry) {
    if (!isSelectable(entry)) {
      return true;
    }
    final units = selectionUnitsOf(entry);
    final next = Map<String, ChatMessage>.of(state.messages);
    if (state.isEntrySelected(entry)) {
      for (final unit in units) {
        next.remove(unit.id);
      }
    } else {
      final room = maxSelectedMessages - next.length;
      final missing = units.where((unit) => !next.containsKey(unit.id));
      if (missing.length > room) {
        return false;
      }
      for (final unit in missing) {
        next[unit.id] = unit;
      }
    }
    state = ChatSelectionState(
      active: true,
      messages: next,
      anchorId: entry.id,
    );
    return true;
  }

  /// Ticks [entries] (the list entries from the anchor to the one that was
  /// Shift-clicked), as far as there is room. Returns false when some were
  /// left out for lack of room.
  bool selectAll(Iterable<ChatMessage> entries, {String? anchorId}) {
    final next = Map<String, ChatMessage>.of(state.messages);
    var complete = true;
    for (final entry in entries) {
      if (!isSelectable(entry)) {
        continue;
      }
      final units = selectionUnitsOf(entry);
      final missing = units.where((unit) => !next.containsKey(unit.id));
      if (missing.length > maxSelectedMessages - next.length) {
        complete = false;
        continue;
      }
      for (final unit in missing) {
        next[unit.id] = unit;
      }
    }
    state = ChatSelectionState(
      active: true,
      messages: next,
      anchorId: anchorId ?? state.anchorId,
    );
    return complete;
  }

  /// Leaves selection mode.
  void cancel() {
    if (state.active || state.messages.isNotEmpty) {
      state = const ChatSelectionState();
    }
  }
}
