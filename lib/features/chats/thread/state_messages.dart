part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// What the message menu and its cards do to a message.
extension _ThreadMessageActionsState on _ChatThreadScreenState {
  Future<void> _votePoll(ChatMessage message, List<String> optionIds) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .votePoll(messageId: message.id, optionIds: optionIds);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not record your vote. Try again.'));
      rethrow;
    }
  }

  Future<void> _addPollOption(ChatMessage message, String text) async {
    try {
      await ref.read(pollsRepositoryProvider).addOption(message.id, text);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not add that answer. Try again.'));
      rethrow;
    }
  }

  Future<void> _endPoll(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('End poll')),
        content: Text(tr('End this poll now? Nobody can vote after it ends.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('poll-end-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('End poll')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(chatsRepositoryProvider).endPoll(messageId: message.id);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not end the poll. Try again.'));
    }
  }

  void _showPollVoters(ChatMessage message) {
    showWeCordSheet<void>(
      context,
      title: tr('Votes'),
      builder: (context, _) => PollVotersSheet(message: message),
    );
  }

  /// "Remind me": picks a time, then the message comes back in
  /// Notifications (and as a notification and push) then.
  Future<void> _remindAbout(ChatMessage message) async {
    final preview = laterPreview(
      conversationId: message.conversationId,
      body: message.body,
      type: message.type,
    );
    final when = await showWhenSheet(
      context,
      title: tr('Remind me'),
      subtitle: preview,
      picks: remindPicks,
    );
    if (when == null || !mounted) {
      return;
    }
    try {
      await ref.read(remindersRepositoryProvider).set(message.id, when);
    } catch (_) {
      _showSnackBar(tr('Could not set the reminder. Try again.'));
      return;
    }
    ref.invalidate(remindersProvider);
    if (!mounted) {
      return;
    }
    _showSnackBar(
      tr('Reminder set for {time}', {
        'time': describeWhen(
          MaterialLocalizations.of(context),
          when.toLocal(),
          DateTime.now(),
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
      }),
    );
  }

  /// "Save for later" / "Remove from Saved".
  Future<void> _toggleSaved(ChatMessage message) async {
    final repository = ref.read(savedMessagesRepositoryProvider);
    final existing = (ref.read(savedMessagesProvider).value ?? const [])
        .where((saved) => saved.messageId == message.id)
        .firstOrNull;
    try {
      if (existing != null) {
        await repository.remove(existing.id);
      } else {
        await repository.save(message.id);
      }
    } catch (_) {
      _showSnackBar(tr('Could not update Saved. Try again.'));
      return;
    }
    ref.invalidate(savedMessagesProvider);
    _showSnackBar(
      existing != null ? tr('Removed from Saved') : tr('Saved for later'),
    );
  }

  Future<void> _openScheduledMessages() {
    return showScheduledMessagesSheet(
      context,
      conversationId: widget.conversationId,
      onSent: _refreshThread,
    );
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.id;
    // Someone else's message (as a moderator, or a webhook's creator) is
    // deleted only after confirming.
    if (!message.isSentBy(currentUserId)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(tr('Delete message')),
          content: Text(
            tr('Delete this message for everyone? This cannot be undone.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              key: const ValueKey('message-delete-confirm'),
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
      if (confirmed != true || !mounted) {
        return;
      }
    }
    try {
      // An album goes as a whole.
      for (final item in message.album ?? [message]) {
        if (!isPendingMessageId(item.id)) {
          await ref
              .read(chatsRepositoryProvider)
              .recallMessage(messageId: item.id);
        }
      }
      _refreshThread(messageId: message.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not delete message. Try again.');
        });
      }
    }
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    if (message.recalledAt != null) {
      return;
    }
    try {
      await ref
          .read(chatsRepositoryProvider)
          .toggleMessageReaction(messageId: message.id, emoji: emoji);
      _refreshThread(messageId: message.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not update reaction. Try again.');
        });
      }
    }
  }

  Future<void> _togglePin(ChatMessage message) async {
    if (message.recalledAt != null || message.type == MessageType.system) {
      return;
    }
    final repository = ref.read(chatsRepositoryProvider);
    try {
      if (message.isPinned) {
        await repository.unpinMessage(messageId: message.id);
      } else {
        await repository.pinMessage(messageId: message.id);
      }
      _refreshThread(messageId: message.id);
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    } on PinnedMessageLimitException {
      _showSnackBar(
        tr('This conversation already has {count} pinned messages.', {
          'count': maxPinnedMessagesPerConversation,
        }),
      );
    } catch (_) {
      _showSnackBar(
        message.isPinned
            ? tr('Could not unpin message. Try again.')
            : tr('Could not pin message. Try again.'),
      );
    }
  }

  Future<void> _publishMessage(ChatMessage message) async {
    try {
      final delivered = await ref
          .read(announcementRepositoryProvider)
          .publish(message.id);
      _refreshThread(messageId: message.id);
      _showSnackBar(switch (delivered) {
        0 => tr('Published. No channels follow this one yet.'),
        1 => tr('Published to 1 channel.'),
        _ => tr('Published to {count} channels.', {'count': delivered}),
      });
    } catch (_) {
      _showSnackBar(tr('Could not publish the message. Try again.'));
    }
  }

  Future<void> _removeEmbed(ChatMessage message) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .setMessageSuppressEmbeds(messageId: message.id, suppress: true);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not remove the link preview. Try again.'));
    }
  }

  void _openThread(ThreadTarget target) {
    final onOpenThread = widget.onOpenThread;
    if (onOpenThread != null) {
      onOpenThread(target);
      return;
    }
    context.push(
      '${ChatsScreen.path}/${target.conversationId}',
      extra: ChatThreadRouteExtra(
        title: target.title,
        type: ConversationType.thread,
      ),
    );
  }

  /// Opens [message]'s thread, or asks for a title and starts one.
  Future<void> _openOrCreateThread(ChatMessage message) async {
    final existing = message.threadSummary;
    if (existing != null) {
      _openThread(
        ThreadTarget(
          conversationId: existing.conversationId,
          title: existing.title,
          threadId: existing.threadId,
        ),
      );
      return;
    }
    final title = await showDialog<String>(
      context: context,
      builder: (context) =>
          _ThreadTitleDialog(initialTitle: suggestedTitleFor(message)),
    );
    if (title == null || !mounted) {
      return;
    }
    try {
      final thread = await ref
          .read(chatsRepositoryProvider)
          .createThread(
            parentConversationId: widget.conversationId,
            rootMessageId: message.id,
            title: title,
          );
      _refreshThread(messageId: message.id);
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      _openThread(
        ThreadTarget(
          conversationId: thread.conversationId,
          title: thread.title,
          threadId: thread.id,
        ),
      );
    } catch (_) {
      _showSnackBar(tr('Could not create thread. Try again.'));
    }
  }

  Future<void> _unpinFromList(String messageId) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .unpinMessage(messageId: messageId);
      _refreshThread(messageId: messageId);
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    } catch (_) {
      _showSnackBar(tr('Could not unpin message. Try again.'));
    }
  }

  Future<void> _showPinnedMessages(bool canManagePins) async {
    ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    final messageId = await showWeCordSheet<String>(
      context,
      title: tr('Pinned messages'),
      builder: (context, _) {
        return PinnedMessagesSheet(
          conversationId: widget.conversationId,
          canManagePins: canManagePins,
          onUnpin: _unpinFromList,
        );
      },
    );
    if (messageId != null && mounted) {
      await _scrollToMessage(messageId);
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _showReactors(ChatMessage message, MessageReaction reaction) {
    showWeCordSheet<void>(
      context,
      title: tr('Reacted with {emoji}', {
        'emoji': reactionLabel(reaction, ref.read(usableEmojisByIdProvider)),
      }),
      builder: (context, _) {
        return MessageReactorsSheet(
          messageId: message.id,
          emoji: reaction.emoji,
        );
      },
    );
  }

  void _showForwardSheet(ChatMessage message) {
    if (message.recalledAt != null) {
      return;
    }
    showWeCordSheet<void>(
      context,
      title: tr('Forward to'),
      builder: (context, _) => MessageForwardSheet(message: message),
    );
  }
}
