import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/features/chats/selection/selection_forward_sheet.dart';
import 'package:wecord/features/chats/selection/selection_rules.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// What the selection bar and header need to know about the chat they sit
/// in; the chat screen builds it.
class SelectionEnvironment {
  const SelectionEnvironment({
    required this.conversationId,
    required this.conversationTitle,
    required this.currentUserId,
    required this.canModerate,
    required this.senderName,
    required this.onChanged,
  });

  final String conversationId;

  /// The chat's name: the title of a merged forward.
  final String conversationTitle;
  final String? currentUserId;

  /// Whether the current user may delete [message] as a moderator (it is
  /// someone else's).
  final bool Function(ChatMessage message) canModerate;

  /// Who wrote [message], for copied text.
  final String Function(ChatMessage message) senderName;

  /// The thread has to load again (after a delete).
  final VoidCallback onChanged;
}

/// What the bar does with the selected messages, one method per button.
/// Each leaves selection mode when it worked.
class SelectionActions {
  SelectionActions(this.context, this.ref, this.environment);

  final BuildContext context;
  final WidgetRef ref;
  final SelectionEnvironment environment;

  ChatSelectionController get _controller =>
      ref.read(chatSelectionProvider(environment.conversationId).notifier);

  List<ChatMessage> get _selected =>
      ref.read(chatSelectionProvider(environment.conversationId)).ordered;

  void _say(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> forward(SelectionForwardMode mode) async {
    final messages = _selected;
    if (messages.isEmpty) {
      return;
    }
    final sent = await showSelectionForwardSheet(
      context,
      messages: messages,
      mode: mode,
      conversationTitle: environment.conversationTitle,
    );
    if (sent == true) {
      _controller.cancel();
    }
  }

  Future<void> save() async {
    final messages = [
      for (final message in _selected)
        if (canSaveMessage(message)) message,
    ];
    if (messages.isEmpty) {
      return;
    }
    final repository = ref.read(savedMessagesRepositoryProvider);
    var saved = 0;
    try {
      for (final message in messages) {
        await repository.save(message.id);
        saved++;
      }
    } on Object {
      ref.invalidate(savedMessagesProvider);
      _say(tr('Could not update Saved. Try again.'));
      return;
    }
    ref.invalidate(savedMessagesProvider);
    _controller.cancel();
    _say(
      saved == 1
          ? tr('Saved for later')
          : tr('{count} messages saved', {'count': saved}),
    );
  }

  Future<void> copy() async {
    final text = copyTextOfSelection(_selected, nameOf: environment.senderName);
    if (text == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    _controller.cancel();
    _say(tr('Copied'));
  }

  Future<void> delete() async {
    final messages = _selected;
    if (messages.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          messages.length == 1
              ? tr('Delete message')
              : tr('Delete {count} messages', {'count': messages.length}),
        ),
        content: Text(
          messages.length == 1
              ? tr('Delete this message for everyone? This cannot be undone.')
              : tr(
                  'Delete these messages for everyone? This cannot be undone.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('selection-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final repository = ref.read(chatsRepositoryProvider);
    var failed = false;
    for (final message in messages) {
      try {
        await repository.recallMessage(messageId: message.id);
      } on Object {
        failed = true;
      }
    }
    environment.onChanged();
    if (failed) {
      _say(tr('Could not delete some messages. Try again.'));
      return;
    }
    _controller.cancel();
  }
}
