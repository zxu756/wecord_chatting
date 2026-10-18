part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// The message list: layout, scrolling, read position.
extension _ThreadListState on _ChatThreadScreenState {
  /// Scrolls to a message search opened this conversation at, once the
  /// messages are there.
  void _schedulePendingJump() {
    if (_isJumpScheduled) {
      return;
    }
    final jump = ref.read(pendingMessageJumpProvider);
    if (jump == null || jump.conversationId != widget.conversationId) {
      return;
    }
    _isJumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isJumpScheduled = false;
      if (!mounted) {
        return;
      }
      final messageId = takePendingMessageJump(ref, widget.conversationId);
      if (messageId != null) {
        unawaited(_scrollToMessage(messageId));
      }
    });
  }

  /// Remembers where the reader left off before the thread marks itself read,
  /// so the NEW divider stays put for as long as the thread stays open. When
  /// the last read message is older than the loaded pages, the divider is
  /// placed once scrolling loads it.
  void _captureNewMessageDivider(
    ChatThreadData data,
    List<ChatMessage> oldestToNewest,
    String? currentUserId,
  ) {
    if (!_hasCapturedReadPosition) {
      // The offline copy has no read markers; wait for the server's.
      if (data.isFromCache && data.readMarkers.isEmpty) {
        return;
      }
      _hasCapturedReadPosition = true;
      _dividerPending = true;
      _initialReadMarker = data.readMarkers
          .where((marker) => marker.userId == currentUserId)
          .firstOrNull;
    }
    if (!_dividerPending) {
      return;
    }
    final marker = _initialReadMarker;
    if (currentUserId == null || marker == null) {
      _dividerPending = false;
      _newMessageDividerId = null;
      return;
    }
    final lastReadId = marker.lastReadMessageId;
    final lastReadLoaded =
        lastReadId != null &&
        oldestToNewest.any((message) => message.id == lastReadId);
    if (!lastReadLoaded && data.hasOlder) {
      // Further back than the loaded pages.
      return;
    }
    _dividerPending = false;
    _newMessageDividerId = firstUnreadMessageId(
      messages: oldestToNewest,
      readMarkers: [marker],
      currentUserId: currentUserId,
    );
  }

  /// [messages] without the disappearing ones whose time has come, which
  /// the server deletes a little later. The same list when none is due.
  List<ChatMessage> _withoutExpired(List<ChatMessage> messages) {
    final now = DateTime.now().toUtc();
    DateTime? next;
    var anyExpired = false;
    for (final message in messages) {
      final at = message.expiresAt;
      if (at == null) {
        continue;
      }
      if (at.isAfter(now)) {
        if (next == null || at.isBefore(next)) {
          next = at;
        }
      } else {
        anyExpired = true;
      }
    }
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (next != null) {
      // Looks again when the next message is due (at least every hour).
      final wait = next.difference(now) + const Duration(milliseconds: 250);
      _expiryTimer = Timer(
        wait > const Duration(hours: 1) ? const Duration(hours: 1) : wait,
        () {
          if (mounted) {
            setState(() {});
          }
        },
      );
    }
    if (!anyExpired) {
      return messages;
    }
    if (identical(_expirySource, messages) && _expiryResult != null) {
      return _expiryResult!;
    }
    _expirySource = messages;
    return _expiryResult = [
      for (final message in messages)
        if (message.expiresAt == null || message.expiresAt!.isAfter(now))
          message,
    ];
  }

  /// Reads the timer again when someone changes it (their notice arrives).
  void _refreshDisappearingOnNotice(List<ChatMessage>? messages) {
    if (messages == null) {
      return;
    }
    String? latest;
    DateTime? latestAt;
    for (final message in messages) {
      if (message.disappearingNoticeSeconds != null &&
          (latestAt == null || message.createdAt.isAfter(latestAt))) {
        latest = message.id;
        latestAt = message.createdAt;
      }
    }
    if (latest == _lastDisappearingNoticeId) {
      return;
    }
    final first = _lastDisappearingNoticeId == null;
    _lastDisappearingNoticeId = latest;
    if (first && latest == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(disappearingSecondsProvider(widget.conversationId));
      }
    });
  }

  /// The layout of the loaded messages: sorted, searched, grouped. Worked
  /// out again only when they (or the search, the NEW divider or the
  /// outbox) change, not on every build.
  ThreadLayout _layoutFor(
    ChatThreadData data, {
    required List<OutboxEntry> pending,
    required String? currentUserId,
  }) {
    _threadData = data;
    final messages = _withoutExpired(data.messages);
    final previous = _layout;
    if (previous != null &&
        identical(previous.messages, messages) &&
        identical(previous.readMarkers, data.readMarkers) &&
        identical(previous.pending, pending) &&
        previous.query == _messageSearchQuery &&
        previous.dividerId == _newMessageDividerId &&
        previous.currentUserId == currentUserId &&
        previous.readScope == _readScope) {
      return previous;
    }
    final layout = ThreadLayout.build(
      messages: messages,
      readMarkers: data.readMarkers,
      pending: pending,
      query: _messageSearchQuery,
      dividerId: _newMessageDividerId,
      currentUserId: currentUserId,
      forumPost: widget.forumPost,
      readScope: _readScope,
      search: (messages, query) => ref
          .read(chatsRepositoryProvider)
          .searchThreadMessages(messages, query),
    );
    _layout = layout;
    _itemCache.removeWhere((id, _) => !layout.displayIndex.containsKey(id));
    return layout;
  }

  GlobalKey _keyForMessage(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () {
      final key = GlobalKey();
      _messageIdsByKey[key] = messageId;
      return key;
    });
  }

  /// The oldest-first index of the message the list is built around.
  int _anchorIndexFor(List<ChatMessage> display, ChatThreadData data) {
    if (display.isEmpty) {
      return 0;
    }
    final index = _anchorId == null ? null : _layout?.displayIndex[_anchorId];
    if (widget.forumPost) {
      if (index != null) {
        return index;
      }
      _anchorId = display.first.id;
      return 0;
    }
    if ((_following && !data.hasNewer) || index == null) {
      _anchorId = display.last.id;
      return display.length - 1;
    }
    return index;
  }

  /// After the thread's data changed: loads more when the loaded messages
  /// do not fill the screen, and starts forum posts from their opening
  /// post.
  void _afterThreadData(ChatThreadData data) {
    if (widget.forumPost &&
        !_forumStartRequested &&
        data.hasOlder &&
        !data.hasNewer) {
      _forumStartRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        await ref
            .read(chatThreadProvider(widget.conversationId).notifier)
            .startFromBeginning();
        if (!mounted) {
          return;
        }
        setState(() => _anchorId = null);
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    if (data.hasOlder || data.hasNewer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadMoreIfNeeded();
        }
      });
    }
  }

  /// Loads the next page in a direction when the reader is close to the
  /// loaded end there.
  void _loadMoreIfNeeded() {
    final data = _threadData;
    if (data == null ||
        !_scrollController.hasClients ||
        _messageSearchQuery.trim().isNotEmpty) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }
    final towardOldest = widget.forumPost
        ? position.pixels - position.minScrollExtent
        : position.maxScrollExtent - position.pixels;
    final towardNewest = widget.forumPost
        ? position.maxScrollExtent - position.pixels
        : position.pixels - position.minScrollExtent;
    final reach = position.viewportDimension * 1.5;
    final notifier = ref.read(
      chatThreadProvider(widget.conversationId).notifier,
    );
    if (data.hasOlder && !data.isLoadingOlder && towardOldest < reach) {
      unawaited(notifier.loadOlder());
    }
    if (data.hasNewer && !data.isLoadingNewer && towardNewest < reach) {
      unawaited(notifier.loadNewer());
    }
  }

  /// When a chat comes to rest at the bottom of its latest messages, the
  /// newest one becomes the anchor again, so arriving messages stay in
  /// view. Nothing moves on screen.
  void _handleScrollEnd() {
    if (widget.forumPost || !_scrollController.hasClients) {
      return;
    }
    final data = _threadData;
    final display = _layout?.display;
    if (data == null || data.hasNewer || display == null || display.isEmpty) {
      return;
    }
    final position = _scrollController.position;
    final fromBottom = position.pixels - position.minScrollExtent;
    if (fromBottom > _bottomScrollThreshold) {
      return;
    }
    final newestId = display.last.id;
    if (_following && _anchorId == newestId) {
      return;
    }
    setState(() {
      _anchorId = newestId;
      _following = true;
    });
    if (position.minScrollExtent < 0) {
      // The newest message's edge becomes offset 0.
      _scrollController.jumpTo(math.max(0.0, fromBottom));
    }
  }

  /// Reads out messages from other people that arrive while the chat is
  /// open, for screen readers (a polite announcement: it waits for what is
  /// being read). Not the messages that were there when it opened, nor
  /// pages of history.
  void _announceIncoming(
    List<ChatMessage> oldestToNewest,
    String? currentUserId, {
    required bool detached,
    required String Function(ChatMessage message) nameOf,
  }) {
    if (detached || oldestToNewest.isEmpty) {
      return;
    }
    final latest = oldestToNewest.last;
    final through = _announcedThroughId;
    if (through == latest.id) {
      return;
    }
    _announcedThroughId = latest.id;
    final index = through == null
        ? -1
        : oldestToNewest.indexWhere((message) => message.id == through);
    if (index == -1) {
      return;
    }
    final fresh = [
      for (final message in oldestToNewest.skip(index + 1))
        if (!message.isSentBy(currentUserId) &&
            message.recalledAt == null &&
            !isPendingMessageId(message.id))
          message,
    ];
    if (fresh.isEmpty) {
      return;
    }
    final last = fresh.last;
    final summary = messageSpokenSummary(last, senderName: nameOf(last));
    final text = fresh.length == 1
        ? summary
        : '${tr('{count} new messages', {'count': fresh.length})}. $summary';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            text,
            Directionality.of(context),
          ),
        );
      }
    });
  }

  /// Counts messages that arrived while the reader was scrolled up. Not
  /// while [detached] from the latest messages (after a jump): pages loaded
  /// then are history, not news.
  void _trackUnseenMessages(
    List<ChatMessage> oldestToNewest,
    String? currentUserId, {
    bool detached = false,
  }) {
    if (detached) {
      _latestMessageId = null;
      _latestSeenMessageId = null;
      _unseenMessageCount = 0;
      return;
    }
    final previousLatestMessageId = _latestMessageId;
    _latestMessageId = oldestToNewest.isEmpty ? null : oldestToNewest.last.id;
    // Reversed chats keep the newest message in view by themselves; forum
    // posts follow new replies while the reader is at the end, and show
    // the reader's own replies.
    if (widget.forumPost &&
        previousLatestMessageId != null &&
        _latestMessageId != previousLatestMessageId &&
        (_isAtBottom || oldestToNewest.last.isSentBy(currentUserId))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_scrollToEnd());
        }
      });
    }
    final latestSeenMessageId = _latestSeenMessageId;
    if (_isAtBottom || latestSeenMessageId == null) {
      _latestSeenMessageId = _latestMessageId;
      _unseenMessageCount = 0;
      return;
    }
    final seenIndex = oldestToNewest.indexWhere(
      (message) => message.id == latestSeenMessageId,
    );
    if (seenIndex == -1) {
      return;
    }
    // An album is one new message, not one per picture.
    _unseenMessageCount = countMessagesFoldingAlbums(
      oldestToNewest
          .skip(seenIndex + 1)
          .where((message) => !message.isSentBy(currentUserId)),
    );
  }

  void _handleScroll() {
    final bool isAtBottom;
    if (!_scrollController.hasClients) {
      isAtBottom = true;
    } else {
      final position = _scrollController.position;
      if (!position.hasContentDimensions) {
        return;
      }
      // Forum posts are not reversed, so their latest end is at the bottom.
      // Chats measure from the newest loaded message (offset 0 is the
      // anchor's, which newer messages may be below).
      isAtBottom = widget.forumPost
          ? position.maxScrollExtent - position.pixels <= _bottomScrollThreshold
          : position.pixels - position.minScrollExtent <=
                _bottomScrollThreshold;
      _loadMoreIfNeeded();
    }
    if (!isAtBottom && !widget.forumPost) {
      // The reader scrolled up: arriving messages no longer move the list.
      _following = false;
    }
    if (isAtBottom == _isAtBottom) {
      return;
    }
    setState(() {
      _isAtBottom = isAtBottom;
      if (isAtBottom) {
        _latestSeenMessageId = _latestMessageId;
        _unseenMessageCount = 0;
      }
    });
  }

  void _jumpToLatest() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_threadData?.hasNewer == true) {
      // Back from a jump in history: load the latest page.
      unawaited(_returnToLatest());
      return;
    }
    if (widget.forumPost) {
      unawaited(_scrollToEnd());
      return;
    }
    final position = _scrollController.position;
    if (position.hasContentDimensions &&
        position.pixels - position.minScrollExtent >
            position.viewportDimension * 4) {
      // Far up: straight to the newest message.
      setState(() {
        _anchorId = null;
        _following = true;
      });
      _scrollController.jumpTo(0);
      return;
    }
    unawaited(_scrollToBottom());
  }

  Future<void> _returnToLatest() async {
    await ref
        .read(chatThreadProvider(widget.conversationId).notifier)
        .jumpToLatest();
    if (!mounted) {
      return;
    }
    setState(() {
      _anchorId = null;
      _following = true;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
      if (widget.forumPost) {
        unawaited(_scrollToEnd());
      }
    }
  }

  /// Scrolls a chat down to its newest loaded message; the list builds
  /// lazily, so its extent may grow on the way.
  Future<void> _scrollToBottom() async {
    await _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.pixels <= position.minScrollExtent) {
        break;
      }
      _scrollController.jumpTo(position.minScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (mounted) {
      _handleScrollEnd();
    }
  }

  /// Scrolls a forum post to its latest reply. The list builds lazily, so
  /// its extent grows as the end comes into view.
  Future<void> _scrollToEnd() async {
    if (!_scrollController.hasClients) {
      return;
    }
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent) {
        return;
      }
      _scrollController.jumpTo(position.maxScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _markReadAfterLoad(List<ChatMessage> messages) {
    final latestMessageId = messages.isEmpty ? '' : messages.last.id;
    if (_lastMarkedMessageId == latestMessageId) {
      return;
    }
    _lastMarkedMessageId = latestMessageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(chatsRepositoryProvider)
            .markConversationRead(widget.conversationId)
            .catchError((Object _) {}),
      );
    });
  }

  void _reconcileActiveMessageState(Map<String, ChatMessage> messagesById) {
    if (_pendingDraftReplyId case final replyId?) {
      // Read by the composer further down this build.
      _pendingDraftReplyId = null;
      final message = messagesById[replyId];
      if (_replyingTo == null &&
          _editingMessage == null &&
          message != null &&
          message.recalledAt == null) {
        _replyingTo = message;
      }
    }
    final replyingTo = _replyingTo;
    final editingMessage = _editingMessage;
    if (replyingTo == null && editingMessage == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      var shouldUpdate = false;
      ChatMessage? nextReplyingTo = _replyingTo;
      ChatMessage? nextEditingMessage = _editingMessage;
      var shouldClearComposer = false;

      final activeReply = _replyingTo;
      if (activeReply != null) {
        final latestReply = messagesById[activeReply.id];
        if (latestReply == null || latestReply.recalledAt != null) {
          nextReplyingTo = null;
          shouldUpdate = true;
        } else if (!identical(latestReply, activeReply)) {
          nextReplyingTo = latestReply;
          shouldUpdate = true;
        }
      }

      final activeEdit = _editingMessage;
      if (activeEdit != null) {
        final latestEdit = messagesById[activeEdit.id];
        if (latestEdit == null || latestEdit.recalledAt != null) {
          nextEditingMessage = null;
          shouldClearComposer = true;
          shouldUpdate = true;
        } else if (!identical(latestEdit, activeEdit)) {
          nextEditingMessage = latestEdit;
          shouldUpdate = true;
        }
      }

      if (!shouldUpdate) {
        return;
      }

      setState(() {
        _replyingTo = nextReplyingTo;
        _editingMessage = nextEditingMessage;
        if (shouldClearComposer) {
          _composerController.clear();
        }
      });
    });
  }

  /// Scrolls the thread to [messageId] and briefly highlights it, loading
  /// the pages around it when it is not loaded. The message becomes the
  /// list's anchor, so it is built at once, and is then centred.
  Future<void> _scrollToMessage(String messageId) async {
    final notifier = ref.read(
      chatThreadProvider(widget.conversationId).notifier,
    );
    final messages =
        ref.read(chatThreadProvider(widget.conversationId)).value?.messages ??
        const <ChatMessage>[];
    if (!messages.any((message) => message.id == messageId)) {
      final found = notifier.isPaged && await notifier.jumpTo(messageId);
      if (!mounted) {
        return;
      }
      if (!found) {
        _showSnackBar(tr('That message is not loaded.'));
        return;
      }
    }
    if (_messageSearchQuery.trim().isNotEmpty) {
      setState(() {
        _searchController.clear();
        _messageSearchQuery = '';
      });
    }
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    setState(() {
      _anchorId = messageId;
      _following = false;
    });
    _scrollController.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) {
      return;
    }

    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      _showSnackBar(tr('That message is not loaded.'));
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    if (!mounted) {
      return;
    }
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = messageId;
    });
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  /// Brings the loaded messages up to date after an action, on
  /// [messageId] when it was about one message.
  void _refreshThread({String? messageId}) {
    unawaited(
      ref
          .read(chatThreadProvider(widget.conversationId).notifier)
          .refresh(messageId: messageId),
    );
  }

  Future<void> _previewImage(ImageAttachment attachment) async {
    final file = PreviewFile.fromImageAttachment(
      attachment,
      conversationId: widget.conversationId,
    );
    final gallery = _galleryFiles();
    final known = gallery.where((item) => item.key == file.key).firstOrNull;
    await openFilePreview(
      context,
      file: known ?? file,
      gallery: gallery,
      conversationId: widget.conversationId,
    );
  }
}
