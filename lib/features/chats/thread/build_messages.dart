part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ThreadMessagesBuild on _ChatThreadScreenState {
  /// The message list with its loading, error and empty states and the
  /// jump pills.
  Widget _buildMessagesArea(
    BuildContext context,
    _ThreadFacts f,
    _ThreadLayoutFacts l, {
    required double topInset,
    required double bottomInset,
  }) {
    final _ThreadFacts(
      :thread,
      :savedIds,
      :pendingEntries,
      :currentUserId,
      :isNoteToSelf,
      :title,
      :isThread,
      :canStartThreads,
      :groupDetail,
      :canSend,
      :canPinMessages,
      :canModeratePolls,
      :canDeleteAsModerator,
      :canPublish,
      :pollActions,
      :c,
      :desktop,
      :cards,
    ) = f;
    final messagesArea = thread.when(
      loading: () => Center(
        child: CircularProgressIndicator(strokeWidth: 2.5, color: c.muted),
      ),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            errorText(error),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.dangerText),
          ),
        ),
      ),
      data: (data) {
        _captureNewMessageDivider(
          data,
          _layoutFor(
            data,
            pending: pendingEntries,
            currentUserId: currentUserId,
          ).fullOldestToNewest,
          currentUserId,
        );
        // Again when the divider moved: grouping breaks at it.
        final layout = _layoutFor(
          data,
          pending: pendingEntries,
          currentUserId: currentUserId,
        );
        final messages = data.messages;
        final fullOldestToNewest = layout.fullOldestToNewest;
        final messagesById = layout.messagesById;
        _trackUnseenMessages(
          fullOldestToNewest,
          currentUserId,
          detached: data.hasNewer,
        );
        if (!data.hasNewer) {
          _markReadAfterLoad(fullOldestToNewest);
        }
        _reconcileActiveMessageState(messagesById);
        _afterThreadData(data);
        _schedulePendingJump();
        final display = layout.display;
        _displayEntries = display;
        if (display.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
            child: Center(
              child: Text(
                messages.isEmpty
                    ? tr('No messages yet')
                    : tr('No matching messages'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
          );
        }

        final searching = _messageSearchQuery.trim().isNotEmpty;
        final followUpIds = layout.followUpIds;
        final dayStartIds = layout.dayStartIds;
        final openingPostId = layout.openingPostId;
        final latestOutgoingReadState = layout.latestOutgoingReadState;
        final showSenders = canStartThreads || isThread;
        // Messages without an embedded sender (still sending) fall
        // back to the current user's own profile.
        final ownProfile = ref.watch(currentProfileProvider).value;
        final membersById = {
          for (final member in groupDetail?.members ?? const <GroupMember>[])
            member.profile.id: member,
        };
        _announceIncoming(
          fullOldestToNewest,
          currentUserId,
          detached: data.hasNewer,
          nameOf: (message) => senderFor(
            message,
            membersById,
            fallbackProfile: message.isSentBy(currentUserId)
                ? ownProfile
                : null,
          ).name,
        );
        final sidePadding = cards ? 0.0 : (desktop ? 40.0 : 14.0);
        // Touch screens swipe a message sideways to reply.
        final touch = usesTouchInput(context);
        _galleryFiles = () => [
          for (final message in fullOldestToNewest)
            ?PreviewFile.fromMessage(
              message,
              senderName: senderFor(
                message,
                membersById,
                fallbackProfile: message.isSentBy(currentUserId)
                    ? ownProfile
                    : null,
              ).name,
            ),
        ];

        Widget buildMessageItem(int index) {
          final message = display[index];
          final pendingEntry = layout.pendingEntryFor(message);
          final Widget bubble;
          if (message.type == MessageType.system) {
            bubble = _SystemMessageLine(
              message: message,
              onOpenPinnedMessage: _scrollToMessage,
            );
          } else if (message.id == openingPostId) {
            bubble = _MessageBubble(
              message: message,
              messagesById: messagesById,
              isCurrentUser: message.isSentBy(currentUserId),
              sender: senderFor(message, membersById),
              isOpeningPost: true,
              postTitle: title,
              replyCount: layout.openingPostReplyCount,
              isFollowUp: false,
              hasFollowUp: false,
              showReadReceipt: false,
              desktop: desktop,
              cards: cards,
              canCompose: canSend,
              onReply: _startReply,
              onEdit: _startEdit,
              onForward: _showForwardSheet,
              onDelete: _deleteMessage,
              canModerate: canDeleteAsModerator(message),
              circleId: _circleId,
              onPreviewImage: _previewImage,
              onToggleReaction: _toggleReaction,
              onShowReactors: _showReactors,
              canPin: canPinMessages,
              onTogglePin: _togglePin,
              onRemoveEmbed: _removeEmbed,
              canStartThread: false,
              pollActions: pollActions,
              onRemind: _remindAbout,
              isSaved: savedIds.contains(message.id),
              onToggleSaved: _toggleSaved,
            );
          } else {
            final isCurrentUser = message.isSentBy(currentUserId);
            final newerMessage = index + 1 < display.length
                ? display[index + 1]
                : null;
            bubble = _MessageBubble(
              message: message,
              messagesById: messagesById,
              isCurrentUser: isCurrentUser,
              sender: senderFor(
                message,
                membersById,
                fallbackProfile: isCurrentUser ? ownProfile : null,
              ),
              // Direct chats name the other person in the title.
              showSenderName: showSenders && !isCurrentUser,
              isFollowUp: followUpIds.contains(message.id),
              hasFollowUp:
                  newerMessage != null && followUpIds.contains(newerMessage.id),
              showReadReceipt:
                  pendingEntry == null &&
                  !isNoteToSelf &&
                  messageEndsAt(
                    message,
                    latestOutgoingReadState.latestOutgoingMessageId,
                  ) &&
                  latestOutgoingReadState.isRead,
              groupReadCount:
                  pendingEntry == null &&
                      !isNoteToSelf &&
                      messageEndsAt(
                        message,
                        latestOutgoingReadState.latestOutgoingMessageId,
                      )
                  ? latestOutgoingReadState.groupReadCount
                  : 0,
              mentionsMe: _mentionsUser(message, currentUserId),
              desktop: desktop,
              cards: cards,
              canCompose: canSend && pendingEntry == null,
              onReply: _startReply,
              onEdit: _startEdit,
              onForward: _showForwardSheet,
              onDelete: _deleteMessage,
              canModerate: canDeleteAsModerator(message),
              circleId: _circleId,
              onPreviewImage: _previewImage,
              onToggleReaction: _toggleReaction,
              onShowReactors: _showReactors,
              canPin: canPinMessages && pendingEntry == null,
              onTogglePin: _togglePin,
              onRemoveEmbed: _removeEmbed,
              canStartThread:
                  canStartThreads && canSend && pendingEntry == null,
              onRemind: _remindAbout,
              isSaved: savedIds.contains(message.id),
              onToggleSaved: _toggleSaved,
              onOpenThread: _openOrCreateThread,
              pollActions: pollActions,
              onPublish: canPublish(message) && pendingEntry == null
                  ? _publishMessage
                  : null,
            );
          }
          final swipeable =
              touch &&
                  canSend &&
                  pendingEntry == null &&
                  message.type != MessageType.system &&
                  message.id != openingPostId &&
                  message.recalledAt == null
              ? SwipeToReply(
                  key: ValueKey('swipe-reply-${message.id}'),
                  // Bubbles swipe away from their side; channel cards
                  // all sit on the left and swipe right.
                  towardsEnd: cards || !message.isSentBy(currentUserId),
                  onReply: () => _startReply(message),
                  child: bubble,
                )
              : bubble;
          final framed = pendingEntry == null
              ? swipeable
              : PendingMessageFrame(
                  entry: pendingEntry,
                  alignEnd: !cards,
                  onRetry: () => _retryPending(pendingEntry),
                  onDiscard: () => _discardPending(pendingEntry),
                  reason: sendFailureReason(
                    pendingEntry.error,
                    timedOutUntil: widget.timedOutUntil,
                  ),
                  onEditResend: pendingEntry.media == null
                      ? null
                      : () => unawaited(
                          ref
                              .read(outboxProvider.notifier)
                              .editAndResendMedia(pendingEntry),
                        ),
                  child: bubble,
                );
          final highlightedRow = AnimatedContainer(
            duration: WeCordMotion.durationOf(
              context,
              const Duration(milliseconds: 300),
            ),
            decoration: BoxDecoration(
              color: message.id == _highlightedMessageId
                  ? c.accent.withValues(alpha: 0.12)
                  : c.accent.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(cards ? 0 : WeCordRadii.md),
            ),
            child: framed,
          );
          final highlighted = MessageSelectionRow(
            conversationId: widget.conversationId,
            message: message,
            label: () => messageSpokenSummary(
              message,
              senderName: message.isSentBy(currentUserId)
                  ? tr('You')
                  : senderFor(message, membersById).name,
            ),
            entries: () => _displayEntries,
            child: highlightedRow,
          );
          final showDay =
              dayStartIds.contains(message.id) && message.id != openingPostId;
          final showNew = message.id == _newMessageDividerId;
          return KeyedSubtree(
            key: _keyForMessage(message.id),
            child: showDay || showNew
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showDay) ChatDaySeparator(time: message.createdAt),
                      if (showNew)
                        ChatNewMessagesDivider(
                          inset: cards ? (desktop ? 24 : 14) : 0,
                        ),
                      highlighted,
                    ],
                  )
                : highlighted,
          );
        }

        Widget messageAt(int index) {
          final message = display[index];
          final pendingEntry = layout.pendingEntryFor(message);
          // Everything the item shows that may change. While it stays
          // the same, the item built last time is used again, so a
          // build of the screen (typing, the composer, a new message)
          // does not rebuild the messages already on screen.
          final sender = message.type == MessageType.system
              ? null
              : senderFor(
                  message,
                  membersById,
                  fallbackProfile: message.isSentBy(currentUserId)
                      ? ownProfile
                      : null,
                );
          final newer = index + 1 < display.length ? display[index + 1] : null;
          final signature = (
            message,
            messagesById[message.replyToMessageId],
            pendingEntry,
            followUpIds.contains(message.id),
            newer != null && followUpIds.contains(newer.id),
            messageEndsAt(
                  message,
                  latestOutgoingReadState.latestOutgoingMessageId,
                ) &&
                latestOutgoingReadState.isRead,
            messageEndsAt(
                  message,
                  latestOutgoingReadState.latestOutgoingMessageId,
                )
                ? latestOutgoingReadState.groupReadCount
                : 0,
            (sender?.name, sender?.avatarUrl, sender?.roleColor),
            (desktop, cards, showSenders, canSend, canStartThreads, touch),
            (
              canPinMessages,
              canModeratePolls,
              canDeleteAsModerator(message),
              canPublish(message),
            ),
            _circleId,
            savedIds.contains(message.id),
            message.id == _highlightedMessageId,
            dayStartIds.contains(message.id),
            message.id == _newMessageDividerId,
            message.id == openingPostId
                ? (title, layout.openingPostReplyCount)
                : null,
          );
          final cached = _itemCache[message.id];
          if (cached != null && cached.$1 == signature) {
            return cached.$2;
          }
          final item = buildMessageItem(index);
          _itemCache[message.id] = (signature, item);
          return item;
        }

        final list = LayoutBuilder(
          builder: (context, listConstraints) => MessageListView(
            key: const ValueKey('chat-message-list'),
            controller: _scrollController,
            forum: widget.forumPost,
            itemCount: display.length,
            anchorIndex: _anchorIndexFor(display, data),
            indexOfMessage: (id) => layout.displayIndex[id],
            messageIdOfKey: (key) => _messageIdsByKey[key],
            itemBuilder: messageAt,
            viewportHeight: listConstraints.maxHeight,
            sidePadding: sidePadding,
            topPadding: topInset + (desktop ? 18 : 10),
            bottomPadding: bottomInset + 14,
            loadingOlder: data.isLoadingOlder,
            loadingNewer: data.isLoadingNewer,
            onScrollEnd: _handleScrollEnd,
          ),
        );
        final showJumpToLatest =
            (!_isAtBottom && _unseenMessageCount > 0) ||
            (data.hasNewer && !widget.forumPost && !searching);
        final newRepliesId = _newMessageDividerId;
        final showJumpToNewReplies =
            widget.forumPost &&
            !showJumpToLatest &&
            !_isAtBottom &&
            !_newRepliesDismissed &&
            newRepliesId != null &&
            newRepliesId != openingPostId &&
            !searching;
        if (widget.forumPost) {
          // Whether the post fits on screen is only known after
          // layout.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _handleScroll();
            }
          });
        }
        return Stack(
          children: [
            Positioned.fill(
              child: FilePreviewScope(
                conversationId: widget.conversationId,
                files: _galleryFiles,
                child: list,
              ),
            ),
            if (showJumpToNewReplies)
              Positioned(
                right: 16,
                bottom: bottomInset + 10,
                child: _JumpPill(
                  key: const ValueKey('forum-jump-to-new-replies'),
                  tooltip: tr('Jump to new replies'),
                  label: tr('Jump to new replies'),
                  onPressed: () {
                    setState(() => _newRepliesDismissed = true);
                    unawaited(_scrollToMessage(newRepliesId));
                  },
                ),
              ),
            if (showJumpToLatest)
              Positioned(
                right: 16,
                bottom: bottomInset + 10,
                child: _JumpPill(
                  tooltip: tr('Jump to latest'),
                  label: _unseenMessageCount == 0
                      ? tr('Jump to latest')
                      : _unseenMessageCount == 1
                      ? tr('1 new message')
                      : tr('{count} new messages', {
                          'count': _unseenMessageCount,
                        }),
                  onPressed: _jumpToLatest,
                ),
              ),
          ],
        );
      },
    );

    return messagesArea;
  }
}
