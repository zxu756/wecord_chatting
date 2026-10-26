part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// The composer: drafts, mentions, emoji, slash commands, keys.
extension _ThreadComposerState on _ChatThreadScreenState {
  /// Puts the conversation's saved draft (text, picked mentions and reply)
  /// back in an untouched composer.
  Future<void> _restoreDraft() async {
    final drafts = ref.read(composerDraftsProvider.notifier);
    final conversationId = widget.conversationId;
    await drafts.loaded;
    final draft = drafts.draftFor(conversationId);
    if (!mounted ||
        draft == null ||
        widget.conversationId != conversationId ||
        _composerController.text.isNotEmpty ||
        _editingMessage != null) {
      return;
    }
    setState(() {
      _composerController.value = TextEditingValue(
        text: draft.text,
        selection: TextSelection.collapsed(offset: draft.text.length),
      );
      _mentionDraft.restore(draft.mentions);
      _pendingDraftReplyId = draft.replyToMessageId;
    });
  }

  /// Keeps what is in the composer as this conversation's draft; edits of
  /// sent messages are not drafts.
  void _saveDraft() {
    if (_editingMessage != null) {
      return;
    }
    ref
        .read(composerDraftsProvider.notifier)
        .set(
          widget.conversationId,
          ComposerDraft(
            text: _composerController.text,
            replyToMessageId: _replyingTo?.id ?? _pendingDraftReplyId,
            mentions: _mentionDraft.picked,
          ),
        );
  }

  /// Opens the AI rewrite sheet for the draft (the composer's AI button,
  /// ⌘/Ctrl+Shift+E). Nothing is sent from it.
  void _openAiRewrite() {
    if (!ref.read(aiAvailableProvider(_circleId)) ||
        _isRecordingVoice ||
        _isSending ||
        _isSendingVoice ||
        !mounted) {
      return;
    }
    void setDraft(String text) {
      _composerController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _handleComposerChanged(text);
      _composerFocus.requestFocus();
    }

    unawaited(
      showAiRewriteSheet(
        context,
        draft: _composerController.text,
        conversationId: widget.conversationId,
        onReplace: setDraft,
        onInsertBelow: (text) {
          final current = _composerController.text.trimRight();
          setDraft(current.isEmpty ? text : '$current\n$text');
        },
      ),
    );
  }

  void _handleComposerChanged(String value) {
    _saveDraft();
    _updateMentionQuery();
    _updateEmojiQuery();
    _updateSlashQuery();
    _typingTimer?.cancel();
    if (value.trim().isEmpty) {
      unawaited(_setTyping(false));
      return;
    }

    unawaited(_setTyping(true));
    _typingTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_setTyping(false));
    });
  }

  void _updateMentionQuery() {
    final query = mentionQueryAt(_composerController.value);
    final isMentioning = query != null;
    final nextQuery = query ?? '';
    if (_isMentioning == isMentioning && _mentionQuery == nextQuery) {
      return;
    }
    setState(() {
      _isMentioning = isMentioning;
      _mentionQuery = nextQuery;
    });
  }

  void _updateEmojiQuery() {
    final query = emojiQueryAt(_composerController.value);
    if (query == _emojiQuery) {
      return;
    }
    setState(() => _emojiQuery = query);
  }

  /// The current user's custom emoji matching the `:name` being typed.
  List<CircleEmoji> _emojiCandidates() {
    final query = _emojiQuery;
    if (query == null) {
      return const [];
    }
    return customEmojiCandidates(
      ref.watch(usableEmojisProvider).value ?? const [],
      query,
      circleId: _circleId,
    );
  }

  void _insertCustomEmoji(CircleEmoji emoji) {
    if (!_emojiDraft.insert(_composerController, emoji)) {
      return;
    }
    setState(() => _emojiQuery = null);
  }

  /// Whether [message] mentions [userId] by name, or everyone online.
  bool _mentionsUser(ChatMessage message, String? userId) {
    if (userId == null || message.isSentBy(userId)) {
      return false;
    }
    return message.mentions.any(
      (mention) => mention.isHere || mention.userId == userId,
    );
  }

  /// [text] with picked (and typed) `:name:` of usable emoji as tokens.
  String _encodeCustomEmoji(String text) {
    return _emojiDraft.encode(
      text,
      usable: ref.read(usableEmojisProvider).value ?? const [],
      circleId: _circleId,
    );
  }

  void _updateSlashQuery() {
    final query = slashQueryAt(_composerController.text);
    if (query == _slashQuery) {
      return;
    }
    setState(() {
      _slashQuery = query;
      _slashIndex = 0;
    });
  }

  /// Sends a bot's command to it; the bot answers in the channel.
  Future<bool> _invokeBotCommand(
    BotSlashCommand command,
    String options,
  ) async {
    try {
      await ref
          .read(circleBotRepositoryProvider)
          .invoke(
            conversationId: widget.conversationId,
            command: command.name,
            options: options,
          );
      _showSnackBar(
        tr('Sent /{command} to {bot}.', {
          'command': command.name,
          'bot': command.botName,
        }),
      );
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _sendError = tr('Could not use the command. Try again.'),
        );
      }
      return false;
    }
  }

  /// The person's own phrases offered for what is being typed (A8); none
  /// while editing.
  List<QuickReply> _quickReplyCandidates() {
    final query = _slashQuery;
    if (query == null || _editingMessage != null) {
      return const [];
    }
    return quickReplyCandidates(query, _slashContext.quickReplies);
  }

  /// [body] with a lone `/shortcut` swapped for the phrase it names (A8):
  /// sending without picking from the list still sends the phrase. Built-in
  /// and bot commands were dealt with before this; anything else is sent as
  /// written.
  String _bodyAfterQuickReply(String body) {
    return quickReplyNamedBy(body, _slashContext.quickReplies)?.body ?? body;
  }

  /// Puts the phrase in the box, ready to read, change and send.
  void _selectQuickReply(QuickReply reply) {
    _composerController.value = TextEditingValue(
      text: reply.body,
      selection: TextSelection.collapsed(offset: reply.body.length),
    );
    setState(() {
      _slashQuery = null;
      _slashIndex = 0;
    });
    _composerFocus.requestFocus();
    _handleComposerChanged(reply.body);
  }

  /// The bots' commands offered for what is being typed.
  List<BotSlashCommand> _botSlashCandidates() {
    final query = _slashQuery;
    if (query == null || _editingMessage != null) {
      return const [];
    }
    return botSlashCommandCandidates(query, _slashContext);
  }

  /// Puts `/name ` in the composer, ready for the bot command's options.
  void _selectBotSlashCommand(BotSlashCommand command) {
    final text = '/${command.name} ';
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _slashQuery = null;
      _slashIndex = 0;
    });
  }

  /// The commands offered for what is being typed; none while editing.
  List<SlashCommand> _slashCandidates() {
    final query = _slashQuery;
    if (query == null || _editingMessage != null) {
      return const [];
    }
    return slashCommandCandidates(query, _slashContext);
  }

  /// Puts `/name ` in the composer, ready for the command's arguments;
  /// `/poll` opens the poll form instead.
  void _selectSlashCommand(SlashCommand command) {
    if (command == SlashCommand.poll) {
      _clearComposerAfterCommand();
      unawaited(_openPollComposer());
      return;
    }
    final text = '/${command.name} ';
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _slashQuery = null;
      _slashIndex = 0;
    });
  }

  /// Arrow keys move through the command list; Enter and Tab pick.
  KeyEventResult _handleComposerKey(FocusNode node, KeyEvent event) {
    final quickReplies = _quickReplyCandidates();
    final commands = _slashCandidates();
    final botCommands = _botSlashCandidates();
    final count = quickReplies.length + commands.length + botCommands.length;
    if (count == 0) {
      return _handleComposerShortcut(event);
    }
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        _slashIndex = (_slashIndex + step) % count;
      });
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.tab)) {
      final index = _slashIndex.clamp(0, count - 1);
      if (index < quickReplies.length) {
        _selectQuickReply(quickReplies[index]);
      } else if (index < quickReplies.length + commands.length) {
        _selectSlashCommand(commands[index - quickReplies.length]);
      } else {
        _selectBotSlashCommand(
          botCommands[index - quickReplies.length - commands.length],
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Esc backs out of an edit, a reply or the search, else marks the
  /// conversation read; Up in an empty field edits the last message sent.
  KeyEventResult _handleComposerShortcut(KeyEvent event) {
    switch (composerShortcutFor(event, text: _composerController.text)) {
      case ComposerShortcut.escape:
        if (_editingMessage != null) {
          _cancelEdit();
        } else if (_replyingTo != null) {
          _cancelReply();
        } else if (_isSearchingMessages) {
          _toggleMessageSearch();
        } else {
          unawaited(
            ref
                .read(chatsRepositoryProvider)
                .markConversationRead(widget.conversationId)
                .then((_) => ref.invalidate(conversationsProvider))
                .catchError((Object _) {}),
          );
          _jumpToLatest();
        }
        return KeyEventResult.handled;
      case ComposerShortcut.editLast:
        final message = lastEditableMessage(
          ref.read(chatThreadProvider(widget.conversationId)).value?.messages ??
              const [],
          ref.read(authRepositoryProvider).currentUser?.id,
        );
        if (message == null || _editingMessage != null) {
          return KeyEventResult.ignored;
        }
        _startEdit(message);
        return KeyEventResult.handled;
      case ComposerShortcut.rewriteWithAi:
        if (!ref.read(aiAvailableProvider(_circleId))) {
          return KeyEventResult.ignored;
        }
        _openAiRewrite();
        return KeyEventResult.handled;
      case null:
        return KeyEventResult.ignored;
    }
  }

  void _clearComposerAfterCommand() {
    _composerController.clear();
    _mentionDraft.clear();
    _emojiDraft.clear();
    setState(() {
      _emojiQuery = null;
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _sendError = null;
    });
    _saveDraft();
    unawaited(_setTyping(false));
  }

  /// Runs a command that changes something other than the conversation,
  /// clearing the composer once it worked.
  Future<void> _runSlashAction(Future<bool> Function() action) async {
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      if (await action() && mounted) {
        _clearComposerAfterCommand();
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<bool> _setNicknameFromCommand(String? nickname) async {
    final circleId = _circleId;
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    if (circleId == null || userId == null) {
      return false;
    }
    try {
      await ref
          .read(circlesRepositoryProvider)
          .setNickname(circleId: circleId, userId: userId, nickname: nickname);
    } catch (_) {
      _showSnackBar(tr('Could not change nickname. Try again.'));
      return false;
    }
    // Messages, mentions and member lists show nicknames.
    ref.invalidate(chatThreadProvider);
    ref.invalidate(groupDetailProvider);
    ref.invalidate(circleDetailProvider(circleId));
    _showSnackBar(
      nickname == null
          ? tr('Your nickname was reset.')
          : tr('Your nickname is now {nickname}.', {'nickname': nickname}),
    );
    return true;
  }

  Future<bool> _setStatusFromCommand(SlashSetStatus status) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setCustomStatus(emoji: status.emoji, text: status.text);
    } catch (_) {
      _showSnackBar(
        status.clears
            ? tr('Could not clear status. Try again.')
            : tr('Could not set status. Try again.'),
      );
      return false;
    }
    ref.invalidate(currentProfileProvider);
    _showSnackBar(
      status.clears
          ? tr('Status cleared.')
          : tr('Status set to {status}.', {
              'status': CustomStatus(
                emoji: status.emoji,
                text: status.text,
              ).label,
            }),
    );
    return true;
  }

  List<GroupMember> _mentionCandidates(GroupDetail? detail) {
    if (detail == null || !_isMentioning) {
      return const [];
    }
    return mentionCandidates(detail.members, _mentionQuery);
  }

  void _insertMention(GroupMember member) {
    if (!_mentionDraft.insert(_composerController, member)) {
      return;
    }
    setState(() {
      _isMentioning = false;
      _mentionQuery = '';
    });
    _saveDraft();
  }

  /// `@here` and roles matching the mention being typed.
  List<SpecialMention> _specialMentionCandidates() {
    if (!_isMentioning) {
      return const [];
    }
    return specialMentionCandidates(
      _mentionTargets,
      _mentionQuery,
      allowHere: _hereUserIds != null,
    );
  }

  void _insertSpecialMention(SpecialMention mention) {
    if (!_mentionDraft.insertSpecial(_composerController, mention)) {
      return;
    }
    setState(() {
      _isMentioning = false;
      _mentionQuery = '';
    });
    _saveDraft();
  }

  List<MessageMention> _mentionsForBody(String body) {
    return _mentionDraft.mentionsFor(body, hereUserIds: _hereUserIds);
  }

  /// The quote of the reply being written, if the person picked a part of
  /// the message's text.
  ReplyQuote? get _activeReplyQuote =>
      _replyingTo != null && _replyQuoteFor?.messageId == _replyingTo!.id
      ? _replyQuoteFor!.quote
      : null;

  void _startReply(ChatMessage message) {
    if (message.recalledAt != null) {
      return;
    }
    final request = ref.read(replyQuoteRequestProvider);
    ref.read(replyQuoteRequestProvider.notifier).clear();
    setState(() {
      _replyQuoteFor = request != null && request.messageId == message.id
          ? (messageId: message.id, quote: request.quote)
          : null;
      _replyingTo = message;
      _editingMessage = null;
      _sendError = null;
    });
    _saveDraft();
  }

  void _startEdit(ChatMessage message) {
    if (message.recalledAt != null || message.type != MessageType.text) {
      return;
    }
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _sendError = null;
      _composerController.text = _emojiDraft.decode(
        message.body,
        ref.read(usableEmojisByIdProvider),
      );
      _composerController.selection = TextSelection.collapsed(
        offset: _composerController.text.length,
      );
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
      _replyQuoteFor = null;
      _pendingDraftReplyId = null;
    });
    _saveDraft();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _composerController.clear();
    });
    unawaited(_restoreDraft());
  }
}
