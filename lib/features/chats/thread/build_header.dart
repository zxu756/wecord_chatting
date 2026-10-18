part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ThreadHeaderBuild on _ChatThreadScreenState {
  /// The thread header: title, status line and buttons (or the selection
  /// header while choosing messages).
  Widget _buildHeader(
    BuildContext context,
    _ThreadFacts f,
    _HeaderActions h,
    _ThreadLayoutFacts l,
  ) {
    final _ThreadFacts(
      :thread,
      :conversationSummary,
      :isNoteToSelf,
      :title,
      :avatarUrl,
      :conversationType,
      :isThread,
      :topic,
      :groupDetail,
      :isDirectOrGroup,
      :disappearingSeconds,
      :onlineUserIds,
      :peerIsOnline,
      :peerPresence,
      :tokens,
      :c,
      :desktop,
      :isChannel,
      :presenceColor,
    ) = f;
    final _HeaderActions(
      :searchAction,
      :pinnedAction,
      :primaryAction,
      :openDisappearing,
    ) = h;
    final _ThreadLayoutFacts(
      :constraints,
      :compact,
      :inlineSearch,
      :headerActions,
      :resultLabel,
      :selecting,
    ) = l;
    // Small phones keep more of the name.
    final headerAvatarSize = desktop
        ? 34.0
        : constraints.maxWidth < 380
        ? 34.0
        : 40.0;
    final headerAvatar = isNoteToSelf
        ? NoteToSelfAvatar(size: headerAvatarSize)
        : isThread
        ? ChatAvatar(
            name: title,
            avatarUrl: null,
            thing: true,
            icon: Icons.forum_outlined,
            size: headerAvatarSize,
          )
        : isChannel
        // Channel titles may already start with their #.
        ? (desktop || title.startsWith('#')
              ? null
              : ChatAvatar(
                  name: title,
                  avatarUrl: null,
                  thing: true,
                  icon: Icons.tag_rounded,
                  size: headerAvatarSize,
                ))
        : ChatAvatar(
            name: title,
            avatarUrl: avatarUrl,
            thing: conversationType == ConversationType.group,
            size: headerAvatarSize,
            presence: conversationType == ConversationType.direct
                ? presenceColor
                : null,
            ringColor: desktop ? c.panel : tokens.glass.solidFill,
          );
    final memberLine = _memberLine(
      type: conversationType,
      groupDetail: groupDetail,
      summary: conversationSummary,
      onlineUserIds: onlineUserIds,
    );
    final subtitle = topic != null
        ? Text(
            topic,
            key: const ValueKey('chat-thread-subtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Text.rich(
            TextSpan(
              children: [
                if (disappearingSeconds != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.timer_outlined,
                        key: const ValueKey('chat-thread-timer'),
                        size: 13,
                        semanticLabel: tr('Messages disappear after {time}', {
                          'time': disappearingLabel(disappearingSeconds),
                        }),
                      ),
                    ),
                  ),
                TextSpan(
                  text: isNoteToSelf
                      ? tr('Only you can see this chat')
                      : isThread
                      ? threadSubtitle(conversationSummary)
                      : memberLine != null
                      ? [
                          memberLine,
                          if (disappearingSeconds != null)
                            disappearingShortLabel(disappearingSeconds),
                        ].join(' · ')
                      : [
                          peerPresence?.label ??
                              (peerIsOnline ? tr('Online') : tr('Offline')),
                          if (conversationType == ConversationType.direct)
                            ?activeCustomStatus(
                              conversationSummary?.directCustomStatus,
                            )?.label,
                          if (disappearingSeconds != null)
                            disappearingShortLabel(disappearingSeconds),
                        ].join(' · '),
                ),
              ],
            ),
            key: const ValueKey('chat-thread-subtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
    final threadHeader = ChatThreadHeader(
      desktop: desktop,
      compact: compact,
      onBack: widget.onBack,
      avatar: headerAvatar,
      channelIcon: desktop && isChannel ? Icons.tag_rounded : null,
      title: title,
      subtitle: subtitle,
      onSubtitleTap: topic != null
          ? () => _showTopic(title, topic)
          : isDirectOrGroup
          ? openDisappearing
          : null,
      subtitleHint: topic != null
          ? null
          : isDirectOrGroup
          ? tr('Opens disappearing messages')
          : null,
      actions: headerActions,
      primaryAction: identical(primaryAction, searchAction)
          ? pinnedAction
          : primaryAction,
      searchField: inlineSearch
          ? ChatHeaderSearchField(
              controller: _searchController,
              hint: isChannel
                  ? tr('Search this channel')
                  : tr('Search this conversation'),
              resultLabel: resultLabel,
              onChanged: (value) {
                setState(() => _messageSearchQuery = value);
              },
              onOpenFullSearch: _openFullSearch,
            )
          : null,
    );
    final header = selecting
        ? ChatSelectionHeader(
            conversationId: widget.conversationId,
            desktop: desktop,
          )
        : threadHeader;
    return header;
  }

  /// The strips under the header, and the AI catch-up banner.
  ({Widget catchUpBanner, List<Widget> banners}) _buildBanners(
    BuildContext context,
    _ThreadFacts f,
    _HeaderActions h,
    _ThreadLayoutFacts l,
  ) {
    final _ThreadFacts(
      :pinnedNote,
      :conversationSummary,
      :title,
      :conversationType,
      :circleId,
      :canCall,
      :desktop,
    ) = f;
    final _ThreadLayoutFacts(:inlineSearch, :resultLabel) = l;
    final catchUpBanner = AiCatchUpBanner(
      key: ValueKey('ai-catch-up-${widget.conversationId}'),
      conversationId: widget.conversationId,
      circleId: circleId,
      controller: _catchUpController,
      unreadCount: conversationSummary?.unreadCount,
      readMarker: _initialReadMarker,
      firstUnreadId: _newMessageDividerId,
      desktop: desktop,
      onJumpToMessage: (id) => unawaited(_scrollToMessage(id)),
    );
    final banners = <Widget>[
      const ConnectivityBanner(
        key: ValueKey('chat-connectivity-banner'),
        padding: EdgeInsets.only(top: 6, bottom: 2),
      ),
      if (canCall)
        DirectCallBar(conversationId: widget.conversationId, title: title),
      if (conversationType == ConversationType.group &&
          conversationSummary?.announcement.trim().isNotEmpty == true)
        _AnnouncementStrip(
          announcement: conversationSummary!.announcement.trim(),
        ),
      if (pinnedNote != null)
        Padding(
          padding: desktop
              ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
              : EdgeInsets.zero,
          child: PinnedNoteBanner(
            conversationId: widget.conversationId,
            note: pinnedNote,
          ),
        ),
      if (canCall) ChatEventStrip(conversationId: widget.conversationId),
      if (canCall)
        LiveLocationBanner(
          conversationId: widget.conversationId,
          desktop: desktop,
        ),
      if (_isSearchingMessages && !inlineSearch)
        _SearchBar(
          controller: _searchController,
          resultLabel: resultLabel,
          onChanged: (value) {
            setState(() => _messageSearchQuery = value);
          },
          onClose: _toggleMessageSearch,
          onOpenFullSearch: _openFullSearch,
        ),
    ];
    return (catchUpBanner: catchUpBanner, banners: banners);
  }
}
