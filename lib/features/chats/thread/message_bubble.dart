part of '../chat_thread_screen.dart';

// One message in the list: the bubble or card, its menus and hover toolbar.

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.messagesById,
    required this.isCurrentUser,
    required this.showReadReceipt,
    required this.onReply,
    this.canCompose = true,
    this.sender,
    this.showSenderName = true,
    this.isFollowUp = false,
    this.hasFollowUp = false,
    this.mentionsMe = false,
    this.desktop = false,
    this.cards = false,
    required this.onEdit,
    required this.onForward,
    required this.onDelete,
    required this.onPreviewImage,
    required this.onToggleReaction,
    required this.onShowReactors,
    required this.canPin,
    required this.onTogglePin,
    required this.onRemoveEmbed,
    this.canStartThread = false,
    this.onOpenThread,
    this.isOpeningPost = false,
    this.postTitle,
    this.replyCount = 0,
    this.pollActions,
    this.canModerate = false,
    this.circleId,
    this.onPublish,
    this.onRemind,
    this.isSaved = false,
    this.onToggleSaved,
  });

  /// The current user saved this message ("Save for later").
  final bool isSaved;

  /// Saves the message, or takes it out of Saved; null for messages that
  /// cannot be saved.
  final Future<void> Function(ChatMessage message)? onToggleSaved;

  /// Sets a reminder about this message ("Remind me"); null for messages
  /// that cannot have one.
  final Future<void> Function(ChatMessage message)? onRemind;

  /// Publishes this announcement to the following channels; null when the
  /// current user cannot (or it is not an unpublished announcement).
  final Future<void> Function(ChatMessage message)? onPublish;

  /// The circle of a channel or its thread, whose custom emoji the reaction
  /// picker lists first.
  final String? circleId;

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final bool isCurrentUser;

  /// Offers "Delete message" on someone else's message: the current user
  /// moderates the conversation, or created the webhook that posted it.
  final bool canModerate;

  /// Votes, voter lists and ending for poll messages.
  final PollActions? pollActions;

  /// The first message of a forum post, shown full width and larger with
  /// [postTitle] above it and [replyCount] below.
  final bool isOpeningPost;
  final String? postTitle;
  final int replyCount;
  final bool showReadReceipt;

  /// Who sent the message, shown as an avatar beside incoming bubbles (and
  /// every card).
  final MessageSender? sender;

  /// Shows [sender]'s name above the first message of a group.
  final bool showSenderName;

  /// Continues the previous message's group, so the name (and on cards the
  /// avatar) is left out.
  final bool isFollowUp;

  /// The next message continues this one's group: the gap below shrinks
  /// and the avatar of a bubble run waits for its last message.
  final bool hasFollowUp;

  /// Mentions the current user (or everyone online): cards are tinted.
  final bool mentionsMe;

  /// Desktop sizes, hover toolbar and right-click menu.
  final bool desktop;

  /// The card ("cozy") layout of circle channels instead of bubbles.
  final bool cards;

  /// The composer is available, so replying and editing are offered.
  final bool canCompose;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final ValueChanged<ChatMessage> onForward;
  final Future<void> Function(ChatMessage message) onDelete;
  final Future<void> Function(ImageAttachment attachment) onPreviewImage;
  final Future<void> Function(ChatMessage message, String emoji)
  onToggleReaction;
  final void Function(ChatMessage message, MessageReaction reaction)
  onShowReactors;
  final bool canPin;
  final Future<void> Function(ChatMessage message) onTogglePin;
  final Future<void> Function(ChatMessage message) onRemoveEmbed;

  /// Threads can start from messages in this conversation.
  final bool canStartThread;

  /// Opens this message's thread, starting one first if needed.
  final Future<void> Function(ChatMessage message)? onOpenThread;

  bool get _isRecalled => message.recalledAt != null;

  /// Still being sent (or part of an album that is): there is no stored
  /// message to reply to, react to or delete yet.
  bool get _isPending =>
      isPendingMessageId(message.id) ||
      (message.album?.any((item) => isPendingMessageId(item.id)) ?? false);

  /// The link whose preview card shows under this message, if any.
  String? get _previewUrl {
    if (message.recalledAt != null ||
        message.type != MessageType.text ||
        message.suppressEmbeds ||
        gifUrlIn(message.body) != null) {
      return null;
    }
    return firstLinkInMarkdown(message.body, mentions: message.mentions);
  }

  /// A text post's image, or an image post's.
  ImageAttachment? get _openingPostImage {
    final attachment = message.attachment;
    if (message.recalledAt != null ||
        attachment == null ||
        attachment['kind'] != 'image') {
      return null;
    }
    try {
      return ImageAttachment.fromJson(attachment);
    } on Object {
      return null;
    }
  }

  Color _nameColor(WeCordPalette c) => switch (sender?.roleColor) {
    final color? => Color(0xFF000000 | color),
    null => c.ink,
  };

  Widget _buildOpeningPost(BuildContext context) {
    final c = context.tokens.colors;
    final isRecalled = _isRecalled;
    final replies = switch (replyCount) {
      0 => tr('No replies yet'),
      1 => tr('1 reply'),
      final count => tr('{count} replies', {'count': count}),
    };
    final side = cards ? (desktop ? 24.0 : 14.0) : 0.0;

    return Padding(
      key: const ValueKey('forum-opening-post'),
      padding: EdgeInsets.fromLTRB(side, 4, side, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Builder(
            builder: (cardContext) => GestureDetector(
              onLongPress: isRecalled
                  ? null
                  : () => _openPhoneMenu(
                      cardContext,
                      preview: _liftedCard(context, _openingPostBody(context)),
                      alignEnd: false,
                    ),
              onSecondaryTapDown: isRecalled
                  ? null
                  : (details) => _showContextMenu(
                      context,
                      Rect.fromLTWH(
                        details.globalPosition.dx,
                        details.globalPosition.dy,
                        0,
                        0,
                      ),
                    ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: c.well,
                  borderRadius: BorderRadius.circular(WeCordRadii.xl),
                ),
                child: _openingPostBody(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: c.subtle,
                ),
                const SizedBox(width: 6),
                Text(
                  replies,
                  key: const ValueKey('forum-opening-post-replies'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 1, color: c.lineSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _openingPostBody(BuildContext context) {
    final c = context.tokens.colors;
    final isRecalled = _isRecalled;
    final image = _openingPostImage;
    final sender = this.sender;
    final previewUrl = _previewUrl;
    final reactions = isRecalled
        ? const <MessageReaction>[]
        : message.reactions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (postTitle case final title?) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            ChatAvatar(
              name: sender?.name ?? '?',
              avatarUrl: sender?.avatarUrl,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sender?.name ?? tr('Someone'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _nameColor(c),
                    ),
                  ),
                  Text(
                    formatThreadActivity(message.createdAt),
                    style: TextStyle(fontSize: 12, color: c.subtle),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isRecalled)
          Text(
            message.deletedLabel,
            style: TextStyle(color: c.muted, fontStyle: FontStyle.italic),
          )
        else if (message.body.trim().isNotEmpty)
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: desktop ? 15 : 16, height: 1.5),
            child: MessageMarkdownText(
              body: message.body,
              mentions: message.mentions,
              color: c.ink,
              enlargeEmojiOnly: true,
            ),
          ),
        if (!isRecalled && message.type == MessageType.text)
          AiTranslationView(
            messageId: message.id,
            text: message.body,
            conversationId: message.conversationId,
            color: c.ink,
          ),
        if (image != null) ...[
          const SizedBox(height: 12),
          _ImageMessageContent(
            attachment: image,
            desktop: desktop,
            framed: true,
          ),
        ],
        if (message.editedAt != null) ...[
          const SizedBox(height: 4),
          EditedMarker(color: c.muted),
        ],
        if (previewUrl != null) ...[
          const SizedBox(height: 10),
          MessageLinkPreviewCard(url: previewUrl, bottomGap: 0),
        ],
        if (reactions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _reactionChips(),
        ],
      ],
    );
  }

  Widget _reactionChips() {
    return MessageReactionChips(
      reactions: message.reactions,
      onToggle: (emoji) => unawaited(onToggleReaction(message, emoji)),
      onShowReactors: (reaction) => onShowReactors(message, reaction),
    );
  }

  /// Whether a screen reader can take the message in one stop: text,
  /// pictures and stickers. Voice messages, files, polls, albums, bot
  /// buttons and links keep their own controls reachable instead.
  bool get _readAsOneNode {
    if (_isRecalled) {
      return true;
    }
    return switch (message.type) {
      MessageType.voice || MessageType.file || MessageType.poll => false,
      MessageType.text =>
        message.album == null &&
            message.locationCard == null &&
            message.liveLocationCard == null &&
            message.interaction == null &&
            firstLinkInMarkdown(message.body, mentions: message.mentions) ==
                null,
      MessageType.image => message.album == null && !message.isViewOnce,
      MessageType.system || MessageType.sticker => true,
    };
  }

  /// What a screen reader can do with the message, besides reading it.
  List<MessageSemanticAction> _semanticActions(BuildContext context) {
    return [
      // A card is read as part of the message, so opening it is an action.
      if (message.chatHistoryCard case final history?)
        MessageSemanticAction(
          tr('Open chat history'),
          () => unawaited(
            openChatHistory(
              context,
              messageId: message.id,
              title: history.title,
            ),
          ),
        ),
      if (message.contactCard case final contact?)
        MessageSemanticAction(
          contact.isUser ? tr('Open profile') : tr('Open circle invite'),
          () => unawaited(openContactCard(context, contact)),
        ),
      for (final action in _actions(context))
        MessageSemanticAction(action.label, action.onSelected),
      MessageSemanticAction(
        tr('Add reaction'),
        () => unawaited(_pickReaction(context)),
      ),
      for (final reaction in message.reactions)
        MessageSemanticAction(
          reaction.reactedByMe
              ? tr('Remove {emoji} reaction', {
                  'emoji': reaction.customName ?? reaction.emoji,
                })
              : tr('React with {emoji}', {
                  'emoji': reaction.customName ?? reaction.emoji,
                }),
          () => unawaited(onToggleReaction(message, reaction.emoji)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final senderName = isCurrentUser
        ? tr('You')
        : (sender?.name ?? message.webhookName ?? tr('Someone'));
    final canShowActions = !_isRecalled && !_isPending;
    final oneNode = _readAsOneNode;
    final Widget content;
    if (isOpeningPost) {
      content = _buildOpeningPost(context);
    } else {
      final hoverable = desktop && !_isRecalled && !usesTouchInput(context);
      content = _MessageHover(
        enabled: hoverable,
        builder: (context, hovered) => cards
            ? _buildCard(context, hovered)
            : _buildBubbleRow(context, hovered),
      );
    }
    return MessageFrame(
      label: messageSpokenSummary(
        message,
        senderName: senderName,
        includeContent: oneNode,
        pending: _isPending,
      ),
      readAsOneNode: oneNode,
      enabled: canShowActions,
      actions: canShowActions ? _semanticActions(context) : const [],
      onOpenMenu: (rect) => _showContextMenu(
        context,
        Rect.fromLTWH(
          rect.left + 24,
          math.min(rect.bottom, rect.top + 48),
          0,
          0,
        ),
      ),
      child: content,
    );
  }

  /// Whether the message is only an image or GIF, shown edge to edge in
  /// its bubble.
  bool get _mediaOnly {
    if (_isRecalled ||
        message.isViewOnce ||
        message.replyPreview != null ||
        message.forwardPreview != null ||
        message.crosspost != null ||
        message.interaction != null ||
        message.editedAt != null ||
        message.isPublished) {
      return false;
    }
    return message.album != null ||
        MessageMediaGroup.isTile(message) ||
        (message.type == MessageType.text && gifUrlIn(message.body) != null);
  }

  Widget _content(BuildContext context, Color textColor) {
    final isRecalled = _isRecalled;
    final content = _messageContent(context, isRecalled, textColor);
    if (isRecalled || message.type != MessageType.text) {
      return content;
    }
    // A translation (message menu → Translate) sits under the text.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        AiTranslationView(
          messageId: message.id,
          text: message.body,
          conversationId: message.conversationId,
          color: textColor,
        ),
      ],
    );
  }

  BubbleFooterRegistry _footerRegistry(BuildContext context) =>
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(bubbleFooterRegistryProvider);

  BubbleFooterContext _footerContext(BuildContext context, Color textColor) {
    return BubbleFooterContext(
      context: context,
      message: message,
      isCurrentUser: isCurrentUser,
      cards: cards,
      desktop: desktop,
      textColor: textColor,
      previewUrl: _previewUrl,
      showReadReceipt: showReadReceipt,
      onToggleReaction: onToggleReaction,
      onShowReactors: onShowReactors,
      onOpenThread: onOpenThread,
    );
  }

  Widget _messageContent(
    BuildContext context,
    bool isRecalled,
    Color textColor,
  ) {
    return _MessageContent(
      footer: _footerContext(context, textColor),
      message: message,
      messagesById: messagesById,
      voiceAttachment: isRecalled ? null : message.voiceAttachment,
      textColor: textColor,
      isRecalled: isRecalled,
      pollActions: pollActions,
      outgoing: !cards && isCurrentUser,
      desktop: desktop,
      cards: cards,
    );
  }

  /// The bubble itself; [lifted] adds the shadow of the long-press menu.
  Widget _bubble(BuildContext context, {bool lifted = false}) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final outgoing = isCurrentUser;
    final textColor = outgoing ? c.onInk : c.ink;
    final media = _mediaOnly;
    // A chat history or contact card is its own card: no bubble around it.
    final card =
        !_isRecalled &&
        message.replyPreview == null &&
        message.forwardPreview == null &&
        (message.chatHistoryCard != null || message.contactCard != null);
    // Over a wallpaper the bubbles stay solid and apart from it.
    final onWallpaper = ChatWallpaperScope.activeOf(context);
    return Container(
      padding: card
          ? EdgeInsets.zero
          : media
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: card
            ? null
            : outgoing
            ? c.ink
            : onWallpaper
            ? WallpaperSurfaces.incomingBubble(tokens)
            : c.raised,
        borderRadius: lifted
            ? BorderRadius.circular(WeCordRadii.bubble + 2)
            : chatBubbleRadius(
                outgoing: outgoing,
                joinsAbove: isFollowUp,
                joinsBelow: hasFollowUp,
              ),
        boxShadow: card
            ? null
            : lifted
            ? tokens.shadows.menu
            : onWallpaper
            ? WallpaperSurfaces.bubbleShadow(tokens)
            : null,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontSize: desktop ? 14.5 : 15.5,
          height: 1.45,
          color: textColor,
        ),
        child: _content(context, textColor),
      ),
    );
  }

  Widget _buildBubbleRow(BuildContext context, bool hovered) {
    final c = context.tokens.colors;
    final outgoing = isCurrentUser;
    final sender = this.sender;
    final stickerAttachment = _isRecalled ? null : message.stickerAttachment;
    final footerItems = _footerRegistry(
      context,
    ).below(_footerContext(context, outgoing ? c.onInk : c.ink));
    final canShowActions = !_isRecalled && !_isPending;
    final avatarSize = desktop ? 32.0 : 30.0;
    final showAvatar = sender != null && !outgoing;
    final indent = showAvatar ? avatarSize + 8 : 0.0;
    final gap = context.density.space(hasFollowUp ? 3 : 10);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubble = math.min(
          (constraints.maxWidth - indent) * (desktop ? 0.66 : 0.8),
          desktop ? 560.0 : 520.0,
        );
        final Widget visual = stickerAttachment != null
            ? Padding(
                key: ValueKey('sticker-message-${message.id}'),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: StickerMessageContent(
                  attachment: stickerAttachment,
                  textColor: c.muted,
                ),
              )
            : _bubble(context);
        final bubble = Builder(
          builder: (bubbleContext) => GestureDetector(
            onLongPress: canShowActions
                ? () => _openPhoneMenu(
                    bubbleContext,
                    preview: stickerAttachment != null
                        ? visual
                        : _bubble(context, lifted: true),
                    alignEnd: outgoing,
                  )
                : null,
            onSecondaryTapDown: canShowActions
                ? (details) => _showContextMenu(
                    context,
                    Rect.fromLTWH(
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                      0,
                      0,
                    ),
                  )
                : null,
            child: QuickDoubleTap(
              enabled: canShowActions,
              onDoubleTap: () => _quickReact(bubbleContext),
              child: visual,
            ),
          ),
        );
        final toolbar = hovered
            ? LayoutBuilder(
                builder: (context, space) => space.maxWidth < 112
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: outgoing
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        heightFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _hoverToolbar(context),
                        ),
                      ),
              )
            : const SizedBox.shrink();
        Widget extra(Widget child, double bottom) => Padding(
          padding: EdgeInsets.only(left: indent, bottom: bottom),
          child: Align(
            alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubble),
              child: child,
            ),
          ),
        );
        final afterBubble = [
          for (final item in footerItems)
            switch (item.entry.wrap) {
              BubbleFooterWrap.plain => extra(item.child, 0),
              BubbleFooterWrap.pill => extra(
                Align(
                  alignment: outgoing
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: WallpaperPill(child: item.child),
                ),
                0,
              ),
              BubbleFooterWrap.receipt => Padding(
                padding: const EdgeInsets.only(right: 2, top: 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: WallpaperPill(child: item.child),
                ),
              ),
            },
        ];
        return Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sender != null && showSenderName && !isFollowUp)
                Padding(
                  padding: EdgeInsets.only(left: indent + 6, bottom: 3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: WallpaperPill(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              sender.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: sender.roleColor == null
                                    ? c.muted
                                    : _nameColor(c),
                              ),
                            ),
                          ),
                          if (sender.isBot) ...[
                            const SizedBox(width: 6),
                            const MessageBotTag(),
                          ],
                          if (sender.userId case final userId?)
                            ProfileNameBadges(userId: userId),
                        ],
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showAvatar) ...[
                    SizedBox(
                      width: avatarSize,
                      child: hasFollowUp
                          ? null
                          : PatAvatar(
                              conversationId: message.conversationId,
                              userId: sender.userId,
                              name: sender.name,
                              child: ChatAvatar(
                                key: ValueKey('message-avatar-${message.id}'),
                                name: sender.name,
                                avatarUrl: sender.avatarUrl,
                                size: avatarSize,
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (outgoing) Expanded(child: toolbar),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxBubble),
                    child: bubble,
                  ),
                  if (!outgoing) Expanded(child: toolbar),
                ],
              ),
              if (afterBubble.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final (index, child) in afterBubble.indexed) ...[
                  if (index > 0) const SizedBox(height: 4),
                  child,
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// A card (circle channels): avatar, name in the role color, time, then
  /// the message without a bubble.
  Widget _buildCard(BuildContext context, bool hovered) {
    final c = context.tokens.colors;
    final sender = this.sender;
    final stickerAttachment = _isRecalled ? null : message.stickerAttachment;
    final footerItems = _footerRegistry(
      context,
    ).below(_footerContext(context, c.ink));
    final canShowActions = !_isRecalled && !_isPending;
    final density = context.density;
    final avatarSize = density.avatar(desktop ? 40 : 36);
    final side = desktop ? 24.0 : 14.0;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isFollowUp)
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    sender?.name ?? tr('Someone'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: desktop ? 14.5 : 15,
                      fontWeight: FontWeight.w700,
                      color: _nameColor(c),
                    ),
                  ),
                ),
                if (sender?.isBot == true) ...[
                  const SizedBox(width: 6),
                  const MessageBotTag(),
                ],
                if (sender?.userId case final userId?)
                  ProfileNameBadges(userId: userId),
                const SizedBox(width: 8),
                Text(
                  chatClockTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: c.subtle,
                  ),
                ),
              ],
            ),
          ),
        if (stickerAttachment != null)
          Padding(
            key: ValueKey('sticker-message-${message.id}'),
            padding: const EdgeInsets.only(top: 4),
            child: StickerMessageContent(
              attachment: stickerAttachment,
              textColor: c.muted,
            ),
          )
        else
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: desktop ? 14.5 : 15.5,
              height: 1.5,
              color: c.ink,
            ),
            child: _content(context, c.ink),
          ),
        for (final item in footerItems)
          ...switch (item.entry.wrap) {
            BubbleFooterWrap.plain => [
              SizedBox(height: item.entry.cardGap),
              if (item.entry.cardMaxWidth case final maxWidth?)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: item.child,
                )
              else
                item.child,
            ],
            BubbleFooterWrap.pill || BubbleFooterWrap.receipt => [
              Padding(
                padding: EdgeInsets.only(top: item.entry.cardGap),
                child: item.child,
              ),
            ],
          },
      ],
    );

    Widget row(BuildContext context, {bool lifted = false}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: avatarSize,
          child: isFollowUp
              ? (hovered && !lifted
                    ? Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          chatClockTime(message.createdAt),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, color: c.subtle),
                        ),
                      )
                    : null)
              : PatAvatar(
                  conversationId: message.conversationId,
                  userId: sender?.userId,
                  name: sender?.name ?? '?',
                  child: ChatAvatar(
                    key: lifted
                        ? null
                        : ValueKey('message-avatar-${message.id}'),
                    name: sender?.name ?? '?',
                    avatarUrl: sender?.avatarUrl,
                    size: avatarSize,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(child: body),
      ],
    );

    // Over a wallpaper each message is a solid card, so the text is never
    // straight on the picture.
    final onWallpaper = ChatWallpaperScope.activeOf(context);
    final tint = onWallpaper
        ? (mentionsMe
              ? Color.alphaBlend(c.accentSoft, c.panel)
              : hovered
              ? c.raised
              : c.panel)
        : mentionsMe
        ? c.accentSoft.withValues(alpha: 0.6)
        : hovered
        ? c.raised.withValues(alpha: 0.6)
        : c.raised.withValues(alpha: 0);

    return Builder(
      builder: (rowContext) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: canShowActions
            ? () => _openPhoneMenu(
                rowContext,
                preview: _liftedCard(
                  context,
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: row(context, lifted: true),
                  ),
                ),
                alignEnd: false,
              )
            : null,
        onSecondaryTapDown: canShowActions
            ? (details) => _showContextMenu(
                context,
                Rect.fromLTWH(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  0,
                  0,
                ),
              )
            : null,
        child: AnimatedContainer(
          duration: WeCordMotion.quick,
          margin: onWallpaper
              ? EdgeInsets.symmetric(horizontal: desktop ? 14 : 8, vertical: 2)
              : null,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: onWallpaper
                ? BorderRadius.circular(WeCordRadii.lg)
                : null,
          ),
          padding: EdgeInsets.fromLTRB(
            side,
            density.space(isFollowUp ? 2 : 10),
            side,
            density.space(hasFollowUp ? 2 : 6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              QuickDoubleTap(
                enabled: canShowActions,
                onDoubleTap: () => _quickReact(rowContext),
                child: row(context),
              ),
              if (hovered)
                Positioned(
                  top: isFollowUp ? -6 : -4,
                  right: 0,
                  child: _hoverToolbar(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// [child] on a panel card with the menu shadow: what a long-pressed
  /// card or forum post lifts.
  Widget _liftedCard(BuildContext context, Widget child) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.colors.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        boxShadow: tokens.shadows.menu,
      ),
      child: child,
    );
  }

  Widget _hoverToolbar(BuildContext context) {
    return MessageHoverToolbar(
      onReact: () => unawaited(_pickReaction(context)),
      onReply: canCompose ? () => onReply(message) : null,
      onMore: (buttonContext) =>
          _showContextMenu(buttonContext, globalRectOf(buttonContext)),
    );
  }

  /// A double tap (touch) or double click (desktop) reacts with the
  /// user's quick reaction: a tick of haptics and a small pop. Reacting
  /// again with one already made does nothing, so a stray second double
  /// tap cannot take it back.
  void _quickReact(BuildContext context) {
    final emoji = ProviderScope.containerOf(
      context,
    ).read(quickReactionProvider);
    WeCordHaptics.light();
    playQuickReactionPop(context, emoji);
    final reacted = message.reactions.any(
      (reaction) => reaction.emoji == emoji && reaction.reactedByMe,
    );
    if (!reacted) {
      unawaited(onToggleReaction(message, emoji));
    }
  }

  Future<void> _pickReaction(BuildContext context) async {
    final emoji = await showEmojiReactionPicker(
      context,
      includeCustom: true,
      circleId: circleId,
    );
    if (emoji != null) {
      await onToggleReaction(message, emoji);
    }
  }

  /// What can be done with this message, in menu order: whatever the
  /// message action registry collects (see `registry/message_actions.dart`).
  List<MessageAction> _actions(BuildContext context) {
    final ctx = MessageActionContext(
      context: context,
      message: message,
      isCurrentUser: isCurrentUser,
      canCompose: canCompose,
      canPin: canPin,
      canStartThread: canStartThread,
      canModerate: canModerate,
      isSaved: isSaved,
      circleId: circleId,
      previewUrl: _previewUrl,
      onReply: onReply,
      onEdit: onEdit,
      onForward: onForward,
      onDelete: onDelete,
      onPreviewImage: onPreviewImage,
      onTogglePin: onTogglePin,
      onRemoveEmbed: onRemoveEmbed,
      onOpenThread: onOpenThread,
      onRemind: onRemind,
      onToggleSaved: onToggleSaved,
      onPublish: onPublish,
    );
    return ctx.container.read(messageActionRegistryProvider).actionsFor(ctx);
  }

  QuickReactionBar _quickReactions(
    BuildContext context, {
    required bool compact,
  }) {
    return QuickReactionBar(
      compact: compact,
      reactedEmojis: {
        for (final reaction in message.reactions)
          if (reaction.reactedByMe) reaction.emoji,
      },
      onSelect: (emoji) {
        Navigator.of(context).pop();
        unawaited(onToggleReaction(message, emoji));
      },
      onMore: () {
        Navigator.of(context).pop();
        unawaited(_pickReaction(context));
      },
    );
  }

  /// The long-press menu: the message lifted over the blurred chat.
  void _openPhoneMenu(
    BuildContext messageContext, {
    required Widget preview,
    required bool alignEnd,
  }) {
    unawaited(
      showMessageActionMenu(
        messageContext,
        messageRect: globalRectOf(messageContext),
        alignEnd: alignEnd,
        preview: preview,
        reactions: _quickReactions(messageContext, compact: false),
        actions: _actions(messageContext),
      ),
    );
  }

  /// The glass context menu (right-click, or the hover toolbar's More).
  void _showContextMenu(BuildContext context, Rect anchor) {
    unawaited(
      showMessageContextMenu(
        context,
        anchor: anchor,
        reactions: _quickReactions(context, compact: true),
        actions: _actions(context),
      ),
    );
  }
}

/// Tracks the pointer over a message on desktop, for its hover tint and
/// toolbar.
class _MessageHover extends StatefulWidget {
  const _MessageHover({required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_MessageHover> createState() => _MessageHoverState();
}

class _MessageHoverState extends State<_MessageHover> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.builder(context, false);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(context, _hovered),
    );
  }
}
