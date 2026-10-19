part of '../chat_thread_screen.dart';

// What is inside a message: system lines, text, quotes, forwards and pictures.

class _SystemMessageLine extends StatelessWidget {
  const _SystemMessageLine({
    required this.message,
    required this.onOpenPinnedMessage,
  });

  final ChatMessage message;
  final Future<void> Function(String messageId) onOpenPinnedMessage;

  @override
  Widget build(BuildContext context) {
    if (PatInfo.maybeFromAttachment(message.attachment) case final pat?) {
      return PatLine(message: message, pat: pat);
    }
    if (AutoModAlert.maybeFromJson(message.attachment) case final alert?) {
      return AutoModAlertCard(alert: alert);
    }
    if (NewcomerNotice.maybeFromJson(message.attachment) case final notice?) {
      return NewcomerCard(
        conversationId: message.conversationId,
        notice: notice,
      );
    }
    final announcedEvent = message.attachment;
    if (announcedEvent != null &&
        announcedEvent['kind'] == 'event' &&
        announcedEvent['event_id'] is String) {
      return ChatEventCard(
        conversationId: message.conversationId,
        eventId: announcedEvent['event_id'] as String,
        fallbackTitle: message.body,
      );
    }
    final c = context.tokens.colors;
    final pinnedMessageId = message.pinnedMessageId;
    final noticeSeconds = message.disappearingNoticeSeconds;
    final icon = pinnedMessageId != null
        ? Icons.push_pin_rounded
        : message.attachment?['kind'] == 'call'
        ? Icons.call_rounded
        : noticeSeconds != null
        ? Icons.timer_outlined
        : null;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c.muted),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              noticeSeconds == null
                  ? systemNoticeText(message.body)
                  : disappearingNoticeText(
                      noticeSeconds,
                      message.attachment?['actor_name'] as String? ??
                          tr('Someone'),
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: c.muted,
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Center(
        child: pinnedMessageId == null
            ? pill
            : WeCordPressable(
                onPressed: () =>
                    unawaited(onOpenPinnedMessage(pinnedMessageId)),
                builder: (context, states) => pill,
              ),
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.footer,
    required this.message,
    required this.messagesById,
    required this.voiceAttachment,
    required this.textColor,
    required this.isRecalled,
    this.pollActions,
    this.outgoing = false,
    this.desktop = false,
    this.cards = false,
  });

  /// What the footer slot's entries inside the bubble need.
  final BubbleFooterContext footer;
  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final VoiceAttachment? voiceAttachment;
  final Color textColor;
  final bool isRecalled;
  final PollActions? pollActions;

  /// In an outgoing (ink) bubble.
  final bool outgoing;
  final bool desktop;

  /// In a card rather than a bubble: attachments get their own rounded
  /// cards.
  final bool cards;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (isRecalled) {
      return Text(
        message.deletedLabel,
        style: TextStyle(
          color: textColor.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final content = <Widget>[
      if (message.crosspost case final crosspost?)
        CrosspostOrigin(crosspost: crosspost, foregroundColor: textColor),
      if (message.interaction case final interaction?)
        InteractionOrigin(interaction: interaction, foregroundColor: textColor),
      if (message.storyRef case final storyRef?)
        StoryReplyOrigin(
          message: message,
          reference: storyRef,
          foregroundColor: textColor,
        ),
      if (message.replyPreview != null) ...[
        _QuotedReplyPreview(
          senderName: message.replyPreview!.senderName,
          body: _displayBodyForReplyPreview(message.replyPreview!),
          foregroundColor: textColor,
          cards: cards,
          quoted: _showsQuote(message.replyPreview!),
          onOpen: _openRepliedMessage(context, message.replyPreview!),
        ),
        const SizedBox(height: 6),
      ],
      if (message.forwardPreview != null) ...[
        _ForwardedPreview(
          preview: message.forwardPreview!,
          foregroundColor: textColor,
          cards: cards,
        ),
        const SizedBox(height: 6),
      ],
    ];

    if (message.isViewOnce) {
      content.add(
        ViewOnceMessageContent(message: message, textColor: textColor),
      );
    } else if (message.album != null || MessageMediaGroup.isTile(message)) {
      content.add(
        MessageMediaGroup(
          messages: message.album ?? [message],
          textColor: textColor,
          desktop: desktop,
          framed: cards,
        ),
      );
    } else if (voiceAttachment != null) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 4 : 0),
          child: VoiceMessagePlayer(
            attachment: voiceAttachment!,
            foregroundColor: cards ? c.ink : textColor,
            card: cards,
            messageId: isPendingMessageId(message.id) ? null : message.id,
            conversationId: message.conversationId,
            autoplayNext: true,
          ),
        ),
      );
    } else if (message.fileAttachment case final file?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cards ? 420 : 300),
            child: FileMessageContent(
              attachment: file,
              textColor: textColor,
              card: cards,
              messageId: message.id,
              conversationId: message.conversationId,
              sentAt: message.createdAt,
            ),
          ),
        ),
      );
    } else if (message.type == MessageType.poll) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 2, bottom: cards ? 0 : 2),
          child: cards
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(WeCordRadii.lg),
                      border: Border.all(color: c.lineSoft),
                    ),
                    child: PollMessageContent(
                      message: message,
                      textColor: c.ink,
                      actions: pollActions,
                    ),
                  ),
                )
              : PollMessageContent(
                  message: message,
                  textColor: textColor,
                  actions: pollActions,
                ),
        ),
      );
    } else if (message.chainCard case final chainCard?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 2, bottom: cards ? 0 : 2),
          child: ChainCardView(card: chainCard),
        ),
      );
    } else if (message.formCard case final formCard?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 2, bottom: cards ? 0 : 2),
          child: FormCardView(card: formCard),
        ),
      );
    } else if (message.chatHistoryCard case final historyCard?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 2, bottom: cards ? 0 : 2),
          child: ChatHistoryCardView(card: historyCard, messageId: message.id),
        ),
      );
    } else if (message.contactCard case final contactCard?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 2, bottom: cards ? 0 : 2),
          child: ContactCardView(card: contactCard),
        ),
      );
    } else if (message.locationCard case final location?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 0),
          child: LocationMessageCard(
            place: location.place,
            textColor: cards ? c.ink : textColor,
            sharedBy: message.senderNickname ?? message.sender?.displayName,
          ),
        ),
      );
    } else if (message.liveLocationCard case final live?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 0),
          child: LiveLocationMessageCard(
            card: live,
            conversationId: message.conversationId,
            senderId: message.senderId,
            senderName:
                message.senderNickname ?? message.sender?.displayName ?? '',
            textColor: cards ? c.ink : textColor,
          ),
        ),
      );
    } else if (message.workspaceCard case final workspaceCard?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 2, bottom: cards ? 0 : 2),
          child: WorkspaceCardView(
            card: workspaceCard,
            conversationId: message.conversationId,
          ),
        ),
      );
    } else if (gifUrlIn(message.body) case final gifUrl?) {
      content.add(
        Padding(
          padding: EdgeInsets.only(top: cards ? 6 : 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            child: GifMessageImage(url: gifUrl, textColor: textColor),
          ),
        ),
      );
    } else {
      content.add(
        MessageMarkdownText(
          body: message.body,
          mentions: message.mentions,
          color: textColor,
          enlargeEmojiOnly: true,
        ),
      );
    }

    content.addAll(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(bubbleFooterRegistryProvider).inside(footer),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: content,
    );
  }

  /// The reply quotes a part of the message, and the message is still
  /// there.
  bool _showsQuote(ReplyPreview preview) =>
      preview.quote != null &&
      messagesById[preview.messageId]?.recalledAt == null &&
      preview.body.isNotEmpty;

  /// Tapping the quote shows the message it answers; null where the list
  /// cannot jump or the message is deleted.
  VoidCallback? _openRepliedMessage(
    BuildContext context,
    ReplyPreview preview,
  ) {
    final jump = MessageJumpScope.maybeOf(context);
    if (jump == null ||
        preview.body.isEmpty ||
        messagesById[preview.messageId]?.recalledAt != null) {
      return null;
    }
    return () => unawaited(jump(preview.messageId));
  }

  String _displayBodyForReplyPreview(ReplyPreview preview) {
    final referencedMessage = messagesById[preview.messageId];
    // The server empties the quote when the original is deleted.
    if (referencedMessage?.recalledAt != null || preview.body.isEmpty) {
      return tr('Message deleted');
    }
    if (preview.quote case final quote?) {
      return quote.text;
    }
    return switch (preview.type) {
      MessageType.text => plainTextFromMarkdown(preview.body),
      // These previews hold a fixed English label.
      MessageType.image ||
      MessageType.file ||
      MessageType.voice => tr(preview.body),
      _ => preview.body,
    };
  }
}

class _ForwardedPreview extends StatelessWidget {
  const _ForwardedPreview({
    required this.preview,
    required this.foregroundColor,
    this.cards = false,
  });

  final ForwardPreview preview;
  final Color foregroundColor;
  final bool cards;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: cards ? null : double.infinity,
      constraints: cards ? const BoxConstraints(maxWidth: 440) : null,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cards ? c.well : foregroundColor.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.shortcut_rounded,
                size: 13,
                color: foregroundColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  tr('Forwarded from {name}', {'name': preview.senderName}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: foregroundColor.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _displayBodyForForwardPreview(preview),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: foregroundColor.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotedReplyPreview extends StatelessWidget {
  const _QuotedReplyPreview({
    required this.senderName,
    required this.body,
    required this.foregroundColor,
    this.cards = false,
    this.quoted = false,
    this.onOpen,
  });

  final String senderName;
  final String body;
  final Color foregroundColor;
  final bool cards;

  /// [body] is a part of the message picked by the sender (A9).
  final bool quoted;

  /// Shows the message the reply answers.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final quote = Container(
      width: cards ? null : double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cards ? c.well : foregroundColor.withValues(alpha: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: foregroundColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            body,
            maxLines: quoted ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: foregroundColor.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
    final openable = onOpen == null
        ? quote
        : WeCordPressable(
            key: const ValueKey('reply-quote-open'),
            onPressed: onOpen,
            pressedScale: 0.99,
            hint: tr('Go to the message this answers'),
            minTapSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            builder: (context, states) => quote,
          );
    if (!cards) {
      return openable;
    }
    // Cards point at the quoted message with a small elbow.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: c.faint),
        const SizedBox(width: 4),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: openable,
          ),
        ),
      ],
    );
  }
}

String _displayBodyForForwardPreview(ForwardPreview preview) {
  final body = preview.body.trim();
  return switch (preview.type) {
    MessageType.text =>
      body.isEmpty ? tr('Message') : plainTextFromMarkdown(body),
    MessageType.system => body.isEmpty ? tr('Message') : body,
    MessageType.image => tr('Image'),
    MessageType.file => tr('File'),
    MessageType.voice => tr('Voice message'),
    MessageType.poll => pollPreviewText(body),
    MessageType.sticker => stickerPreviewText(body),
  };
}

class _ImageMessageContent extends ConsumerStatefulWidget {
  const _ImageMessageContent({
    required this.attachment,
    this.desktop = false,
    this.framed = false,
  });

  final ImageAttachment attachment;
  final bool desktop;

  /// On its own (cards) rather than inside a bubble: adds a hairline.
  final bool framed;

  @override
  ConsumerState<_ImageMessageContent> createState() =>
      _ImageMessageContentState();
}

class _ImageMessageContentState extends ConsumerState<_ImageMessageContent> {
  late Future<String> _imageUrl;

  /// Whether the URL was signed again after the image failed to load.
  bool _resigned = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = _loadImageUrl();
  }

  @override
  void didUpdateWidget(covariant _ImageMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.path != widget.attachment.path ||
        oldWidget.attachment.bucket != widget.attachment.bucket) {
      _imageUrl = _loadImageUrl();
      _resigned = false;
    }
  }

  String get _urlKey =>
      SignedUrlCache.keyFor(widget.attachment.bucket, widget.attachment.path);

  /// Reused while valid, so scrolling back to an image does not sign and
  /// load it again.
  Future<String> _loadImageUrl() {
    return ref
        .read(chatSignedUrlCacheProvider)
        .get(
          _urlKey,
          () => ref
              .read(chatsRepositoryProvider)
              .createImageUrl(widget.attachment),
        );
  }

  /// The signed URL may have expired while the chat stayed open: sign it
  /// again, once.
  void _resignAfterError() {
    if (_resigned) {
      return;
    }
    _resigned = true;
    scheduleMicrotask(() {
      if (mounted) {
        ref.read(chatSignedUrlCacheProvider).evict(_urlKey);
        setState(() {
          _imageUrl = _loadImageUrl();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final width = widget.desktop ? 300.0 : 228.0;
    final height = widget.desktop ? 188.0 : 156.0;
    final radius = BorderRadius.circular(WeCordRadii.lg);
    Widget placeholder(Widget? child) => Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.framed ? c.raised : c.well,
        borderRadius: radius,
      ),
      child: child,
    );
    return Padding(
      padding: EdgeInsets.only(top: widget.framed ? 6 : 0),
      child: FutureBuilder<String>(
        future: _imageUrl,
        initialData: _resigned
            ? null
            : ref.read(chatSignedUrlCacheProvider).peek(_urlKey),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null) {
            return placeholder(
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: c.faint,
                ),
              ),
            );
          }
          return WeCordPressable(
            onPressed: () => unawaited(
              openFilePreviewInScope(
                context,
                PreviewFile.fromImageAttachment(widget.attachment),
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: radius),
            pressedScale: 0.98,
            semanticLabel: tr('Image'),
            builder: (context, states) => DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: widget.framed ? Border.all(color: c.lineSoft) : null,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: MotionSafeImage(
                  image: imageDecodedFor(
                    NetworkImage(url),
                    box: Size(width, height),
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    sourceWidth: widget.attachment.width,
                    sourceHeight: widget.attachment.height,
                  ),
                  animated: isAnimatedImage(
                    mimeType: widget.attachment.mimeType,
                  ),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  // Read out as "Image from Ada" by the message around it.
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stackTrace) {
                    _resignAfterError();
                    return placeholder(
                      Icon(
                        Icons.broken_image_outlined,
                        color: c.faint,
                        size: 28,
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
