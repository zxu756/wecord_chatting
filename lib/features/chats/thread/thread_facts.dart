part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Everything one build of the thread works out once.
class _ThreadFacts {
  const _ThreadFacts({
    required this.thread,
    required this.savedIds,
    required this.pendingEntries,
    required this.profileLayout,
    required this.docsWidth,
    required this.pinnedNote,
    required this.conversationSummary,
    required this.currentUserId,
    required this.isNoteToSelf,
    required this.title,
    required this.avatarUrl,
    required this.conversationType,
    required this.isThread,
    required this.topic,
    required this.canStartThreads,
    required this.groupDetail,
    required this.threadId,
    required this.canManageThread,
    required this.threadArchived,
    required this.isDirectOrGroup,
    required this.disappearingSeconds,
    required this.canSend,
    required this.slowmodeSeconds,
    required this.circleId,
    required this.currentActivity,
    required this.onlineUserIds,
    required this.directPeerId,
    required this.peerIsOnline,
    required this.peerPresence,
    required this.canPinMessages,
    required this.canModeratePolls,
    required this.canModerateMessages,
    required this.canDeleteAsModerator,
    required this.canPublish,
    required this.pollActions,
    required this.canCall,
    required this.tokens,
    required this.c,
    required this.desktop,
    required this.isChannel,
    required this.cards,
    required this.typingIds,
    required this.typingName,
    required this.presenceColor,
    required this.composerBottomGap,
  });

  final AsyncValue<ChatThreadData> thread;
  final Set<String> savedIds;
  final List<OutboxEntry> pendingEntries;
  final ({double width, bool collapsed}) profileLayout;
  final double docsWidth;
  final NoteMeta? pinnedNote;
  final ConversationSummary? conversationSummary;
  final String? currentUserId;
  final bool isNoteToSelf;
  final String title;
  final String? avatarUrl;
  final ConversationType? conversationType;
  final bool isThread;
  final String? topic;
  final bool canStartThreads;
  final GroupDetail? groupDetail;
  final String? threadId;
  final bool canManageThread;
  final bool threadArchived;
  final bool isDirectOrGroup;
  final int? disappearingSeconds;
  final bool canSend;
  final int slowmodeSeconds;
  final String? circleId;
  final ConversationActivity currentActivity;
  final Set<String> onlineUserIds;
  final String? directPeerId;
  final bool peerIsOnline;
  final PresenceStatus? peerPresence;
  final bool canPinMessages;
  final bool canModeratePolls;
  final bool canModerateMessages;
  final bool Function(ChatMessage message) canDeleteAsModerator;
  final bool Function(ChatMessage message) canPublish;
  final PollActions pollActions;
  final bool canCall;
  final WeCordTokens tokens;
  final WeCordPalette c;
  final bool desktop;
  final bool isChannel;
  final bool cards;
  final List<String> typingIds;
  final String? typingName;
  final Color presenceColor;
  final double composerBottomGap;
}

/// The header buttons of one build.
class _HeaderActions {
  const _HeaderActions({
    required this.searchAction,
    required this.pinnedAction,
    required this.eventsAction,
    required this.appBarActions,
    required this.primaryAction,
    required this.openDisappearing,
    required this.openWallpaper,
  });

  final ChatThreadAction searchAction;
  final ChatThreadAction pinnedAction;
  final ChatThreadAction? eventsAction;
  final List<ChatThreadAction> appBarActions;
  final ChatThreadAction primaryAction;
  final VoidCallback openDisappearing;
  final VoidCallback openWallpaper;
}

/// What the width of the thread decides.
class _ThreadLayoutFacts {
  const _ThreadLayoutFacts({
    required this.constraints,
    required this.docsPlacement,
    required this.showDocs,
    required this.profileUserId,
    required this.profilePlacement,
    required this.showProfile,
    required this.compact,
    required this.inlineSearch,
    required this.headerActions,
    required this.resultLabel,
    required this.selecting,
  });

  final BoxConstraints constraints;
  final SidePanelPlacement docsPlacement;
  final bool showDocs;
  final String? profileUserId;
  final SidePanelPlacement profilePlacement;
  final bool showProfile;
  final bool compact;
  final bool inlineSearch;
  final List<ChatThreadAction> headerActions;
  final String? resultLabel;
  final bool selecting;
}

/// The build of the thread, in steps.
extension _ThreadFactsState on _ChatThreadScreenState {
  /// Watches and works out everything the thread draws from, once per build.
  _ThreadFacts _gatherFacts(BuildContext context) {
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
    final savedIds = ref.watch(savedMessageIdsProvider);
    final pendingEntries = ref.watch(
      conversationOutboxProvider(widget.conversationId),
    );
    final activity = ref.watch(chatActivityProvider(widget.conversationId));
    final profileLayout = ref.watch(
      panelLayoutProvider.select(
        (layout) =>
            (width: layout.profileWidth, collapsed: layout.profileCollapsed),
      ),
    );
    final docsWidth = ref.watch(
      panelLayoutProvider.select((layout) => layout.docsWidth),
    );
    final pinnedNote = ref
        .watch(conversationWorkspaceProvider(widget.conversationId))
        .value
        ?.pinnedNote;
    _voiceMessageRecorder = ref.watch(voiceMessageRecorderProvider);
    // Loaded early, so the first double tap already knows the choice.
    ref.watch(quickReactionProvider);
    final conversationSummary = ref
        .watch(chatConversationSummaryProvider(widget.conversationId))
        .value;
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id;
    final isNoteToSelf = conversationSummary?.isNoteToSelf ?? false;
    _isNoteToSelf = isNoteToSelf;
    final title = isNoteToSelf
        ? noteToSelfTitle()
        : widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : conversationSummary?.title?.trim().isNotEmpty == true
        ? conversationSummary!.title!.trim()
        : tr('Conversation');
    final avatarUrl = widget.avatarUrl ?? conversationSummary?.avatarUrl;
    final conversationType =
        widget.conversationType ?? conversationSummary?.type;
    final isThread = conversationType == ConversationType.thread;
    final topic = conversationType == ConversationType.channel
        ? switch (widget.topic?.trim()) {
            final String topic when topic.isNotEmpty => topic,
            _ => null,
          }
        : null;
    final canStartThreads =
        conversationType == ConversationType.group ||
        conversationType == ConversationType.channel;
    // Group, channel and thread members feed sender names and @mention
    // candidates.
    final groupDetail = canStartThreads || isThread
        ? ref.watch(groupDetailProvider(widget.conversationId)).value
        : null;
    final threadId = isThread ? conversationSummary?.threadId : null;
    final canManageThread =
        threadId != null &&
        (ref
                .watch(
                  canManageThreadProvider((
                    conversationId: widget.conversationId,
                    threadId: threadId,
                  )),
                )
                .value ??
            false);
    final threadArchived = conversationSummary?.threadArchivedAt != null;
    // Direct chats and groups can have messages that disappear.
    final isDirectOrGroup =
        conversationType == ConversationType.direct ||
        conversationType == ConversationType.group;
    final disappearingSeconds = isDirectOrGroup
        ? ref.watch(disappearingSecondsProvider(widget.conversationId)).value
        : null;
    if (isDirectOrGroup) {
      _refreshDisappearingOnNotice(thread.value?.messages);
    }
    final canSend =
        widget.canSendMessages ?? conversationSummary?.canSendMessages ?? true;
    final slowmodeSeconds =
        widget.slowmodeSeconds ?? conversationSummary?.slowmodeSeconds ?? 0;
    _circleId = conversationSummary?.circleId;
    // Bots answer commands in channels (not threads).
    final circleId = _circleId;
    _slashContext = SlashCommandContext(
      isCircleConversation: circleId != null,
      canCreatePolls: true,
      botCommands:
          circleId != null &&
              conversationType == ConversationType.channel &&
              canSend
          ? ref.watch(circleBotCommandsProvider(circleId)).value ?? const []
          : const [],
    );
    _slowmodeUntil = slowmodeSeconds > 0
        ? slowmodeEnd(
            messages: thread.value?.messages ?? const [],
            currentUserId: currentUserId,
            slowmodeSeconds: slowmodeSeconds,
            retryAt: _slowmodeRetryAt,
          )
        : null;
    final currentActivity = activity.value ?? const ConversationActivity();
    // A direct peer is online when they have the app open anywhere; in
    // groups and channels this still means another member is viewing.
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).value ?? const <String>{};
    final directPeerId = conversationType == ConversationType.direct
        ? conversationSummary?.directUserId ??
              directPeerIdFrom(thread.value?.readMarkers, currentUserId)
        : null;
    _mentionTargets = canStartThreads || isThread
        ? ref
                  .watch(
                    conversationMentionTargetsProvider(widget.conversationId),
                  )
                  .value ??
              const MentionTargets()
        : const MentionTargets();
    _hereUserIds = _mentionTargets.canMentionEveryone
        ? [
            for (final member in groupDetail?.members ?? const <GroupMember>[])
              if (member.profile.id != currentUserId &&
                  onlineUserIds.contains(member.profile.id))
                member.profile.id,
          ]
        : null;
    final peerIsOnline = conversationType == ConversationType.direct
        ? directPeerId != null && onlineUserIds.contains(directPeerId)
        : currentActivity.onlineUserIds.any((id) {
            return id != currentUserId;
          });
    // Direct peers also show Idle or Do Not Disturb.
    final peerPresence = conversationType == ConversationType.direct
        ? presenceOf(
            directPeerId,
            onlineUserIds: onlineUserIds,
            statuses: ref.watch(presenceStatusesProvider).value,
          )
        : null;
    final canPinMessages =
        ref.watch(canPinMessagesProvider(widget.conversationId)).value ?? false;
    final canModeratePolls =
        ref.watch(canModeratePollsProvider(widget.conversationId)).value ??
        false;
    final canModerateMessages =
        ref.watch(canModerateMessagesProvider(widget.conversationId)).value ??
        false;
    // Moderators delete others' messages; a webhook's creator deletes its
    // messages (they are sent as the creator).
    bool canDeleteAsModerator(ChatMessage message) {
      return !message.isSentBy(currentUserId) &&
          message.type != MessageType.system &&
          (canModerateMessages ||
              (message.isWebhook &&
                  currentUserId != null &&
                  message.senderId == currentUserId));
    }

    // The author or a moderator publishes announcement posts once.
    bool canPublish(ChatMessage message) {
      return widget.isAnnouncementChannel &&
          !isThread &&
          message.type == MessageType.text &&
          message.recalledAt == null &&
          message.crosspost == null &&
          !message.isPublished &&
          (canModerateMessages || (message.isSentBy(currentUserId) && canSend));
    }

    final pollActions = PollActions(
      onVote: _votePoll,
      onEnd: _endPoll,
      onShowVoters: _showPollVoters,
      onAddOption: _addPollOption,
      canEnd: (message) =>
          canSend &&
          (canModeratePolls ||
              (currentUserId != null && message.senderId == currentUserId)),
    );

    final canCall =
        !isNoteToSelf &&
        (conversationType == ConversationType.direct ||
            conversationType == ConversationType.group);
    final tokens = context.tokens;
    final c = tokens.colors;
    final desktop = chatUsesDesktopChrome(context);
    final isChannel = conversationType == ConversationType.channel;
    // Circle channels (and their threads) read as cards; direct chats and
    // groups as bubbles.
    final cards = isChannel || (isThread && circleId != null);
    final typingIds = [
      for (final id in currentActivity.typingUserIds)
        if (id != currentUserId) id,
    ];
    final typingName = typingIds.length != 1
        ? null
        : conversationType == ConversationType.direct
        ? title
        : switch (groupDetail?.members
              .where((member) => member.profile.id == typingIds.single)
              .firstOrNull) {
            final member? => mentionName(member),
            null => null,
          };
    final presenceColor = switch (peerPresence) {
      PresenceStatus.online => c.success,
      PresenceStatus.idle => c.warning,
      PresenceStatus.doNotDisturb => c.danger,
      _ => c.faint,
    };
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final composerBottomGap = desktop
        ? 18.0
        : keyboardUp
        ? 8.0
        : math.max(safeBottom - 6, 10.0);
    return _ThreadFacts(
      thread: thread,
      savedIds: savedIds,
      pendingEntries: pendingEntries,
      profileLayout: profileLayout,
      docsWidth: docsWidth,
      pinnedNote: pinnedNote,
      conversationSummary: conversationSummary,
      currentUserId: currentUserId,
      isNoteToSelf: isNoteToSelf,
      title: title,
      avatarUrl: avatarUrl,
      conversationType: conversationType,
      isThread: isThread,
      topic: topic,
      canStartThreads: canStartThreads,
      groupDetail: groupDetail,
      threadId: threadId,
      canManageThread: canManageThread,
      threadArchived: threadArchived,
      isDirectOrGroup: isDirectOrGroup,
      disappearingSeconds: disappearingSeconds,
      canSend: canSend,
      slowmodeSeconds: slowmodeSeconds,
      circleId: circleId,
      currentActivity: currentActivity,
      onlineUserIds: onlineUserIds,
      directPeerId: directPeerId,
      peerIsOnline: peerIsOnline,
      peerPresence: peerPresence,
      canPinMessages: canPinMessages,
      canModeratePolls: canModeratePolls,
      canModerateMessages: canModerateMessages,
      canDeleteAsModerator: canDeleteAsModerator,
      canPublish: canPublish,
      pollActions: pollActions,
      canCall: canCall,
      tokens: tokens,
      c: c,
      desktop: desktop,
      isChannel: isChannel,
      cards: cards,
      typingIds: typingIds,
      typingName: typingName,
      presenceColor: presenceColor,
      composerBottomGap: composerBottomGap,
    );
  }

  /// The header buttons, in More menu order.
  _HeaderActions _headerActionsFor(BuildContext context, _ThreadFacts f) {
    final _ThreadFacts(
      :thread,
      :title,
      :conversationType,
      :groupDetail,
      :threadId,
      :canManageThread,
      :threadArchived,
      :isDirectOrGroup,
      :disappearingSeconds,
      :canSend,
      :circleId,
      :canPinMessages,
      :canCall,
      :desktop,
    ) = f;
    final searchAction = ChatThreadAction(
      tooltip: tr('Search messages'),
      icon: Icons.search,
      onPressed: _toggleMessageSearch,
    );
    final pinnedAction = ChatThreadAction(
      tooltip: tr('Pinned messages'),
      icon: Icons.push_pin_outlined,
      // Pins are what a channel's header is for; elsewhere they are in More.
      primary: conversationType == ConversationType.channel,
      onPressed: () => _showPinnedMessages(canPinMessages),
    );
    // Group chats and direct messages can plan events (circles have their
    // own).
    final eventsAction = canCall
        ? ChatThreadAction(
            tooltip: tr('Events'),
            icon: Icons.event_outlined,
            onPressed: () => showChatEventsList(
              context,
              conversationId: widget.conversationId,
              canCreate: canSend,
            ),
          )
        : null;
    final callAction = canCall
        ? ChatThreadAction(
            tooltip: tr('Start voice call'),
            icon: Icons.call_outlined,
            primary: true,
            onPressed: () => startDirectCall(
              context,
              ref,
              conversationId: widget.conversationId,
              name: title,
            ),
          )
        : null;
    final videoCallAction = canCall
        ? ChatThreadAction(
            tooltip: tr('Start video call'),
            icon: Icons.videocam_outlined,
            primary: true,
            onPressed: () => startDirectCall(
              context,
              ref,
              conversationId: widget.conversationId,
              name: title,
              video: true,
            ),
          )
        : null;
    void openDisappearing() => unawaited(
      showDisappearingSheet(
        context,
        conversationId: widget.conversationId,
        isGroup: conversationType == ConversationType.group,
        canChange:
            conversationType == ConversationType.direct ||
            (groupDetail?.canManageGroup ?? false),
      ),
    );
    final disappearingAction = isDirectOrGroup
        ? ChatThreadAction(
            tooltip: tr('Disappearing messages'),
            icon: Icons.timer_outlined,
            selectedIcon: Icons.timer_rounded,
            isSelected: disappearingSeconds != null,
            menuOnly: true,
            onPressed: openDisappearing,
          )
        : null;
    void openWallpaper() => unawaited(
      showWallpaperPicker(context, conversationId: widget.conversationId),
    );
    // Wallpapers are personal: this one is only for this chat, only for you.
    final wallpaperAction = ChatThreadAction(
      tooltip: tr('Wallpaper'),
      icon: Icons.wallpaper_outlined,
      selectedIcon: Icons.wallpaper_rounded,
      isSelected: ref.watch(
        wallpapersProvider.select(
          (state) => state.settings.hasOwn(widget.conversationId),
        ),
      ),
      menuOnly: true,
      onPressed: openWallpaper,
    );
    final groupDetailsAction = conversationType == ConversationType.group
        ? ChatThreadAction(
            tooltip: tr('Group details'),
            icon: Icons.group_outlined,
            primary: true,
            onPressed: () => _showGroupDetails(title),
          )
        : null;
    final archiveAction = canManageThread
        ? ChatThreadAction(
            tooltip: switch ((threadArchived, widget.forumPost)) {
              (true, true) => tr('Unarchive post'),
              (true, false) => tr('Unarchive thread'),
              (false, true) => tr('Archive post'),
              (false, false) => tr('Archive thread'),
            },
            icon: threadArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            onPressed: () => _setThreadArchived(threadId!, !threadArchived),
          )
        : null;
    final summarizeAction = ref.watch(aiAvailableProvider(circleId))
        ? ChatThreadAction(
            tooltip: tr('Summarize'),
            icon: Icons.auto_awesome_outlined,
            onPressed: _catchUpController.requestSummary,
          )
        : null;
    final notesAction = ChatThreadAction(
      tooltip: chatUsesDesktopChrome(context)
          ? tr('Notes and lists')
          : tr('Notes'),
      icon: Icons.description_outlined,
      selectedIcon: Icons.description_rounded,
      isSelected: _workspaceOpen,
      onPressed: () => openWorkspace(
        context,
        conversationId: widget.conversationId,
        tab: _workspaceRequest?.tab ?? WorkspaceTab.notes,
        title: title,
      ),
    );
    // The desktop panel has both tabs, so it needs only the one button.
    final listsAction = ChatThreadAction(
      tooltip: tr('Lists'),
      icon: Icons.checklist_rounded,
      isSelected:
          _workspaceOpen && _workspaceRequest?.tab == WorkspaceTab.lists,
      onPressed: () => openWorkspace(
        context,
        conversationId: widget.conversationId,
        tab: WorkspaceTab.lists,
        title: title,
      ),
    );
    // Search comes first: phones keep it next to the primary action.
    final appBarActions = [
      searchAction,
      ?callAction,
      ?videoCallAction,
      pinnedAction,
      notesAction,
      if (!chatUsesDesktopChrome(context)) listsAction,
      ?disappearingAction,
      wallpaperAction,
      ChatThreadAction(
        tooltip: tr('Media'),
        icon: Icons.photo_library_outlined,
        onPressed: () {
          context.push(ChatMediaScreen.pathFor(widget.conversationId));
        },
      ),
      ?groupDetailsAction,
      ?archiveAction,
      ?summarizeAction,
      ...widget.extraActions,
    ];
    // Next to search on phones: the circle's member list, a direct call,
    // the group's details, or a managed thread's archive toggle.
    final primaryAction =
        widget.extraActions.firstOrNull ??
        (conversationType == ConversationType.direct ? callAction : null) ??
        groupDetailsAction ??
        archiveAction ??
        pinnedAction;
    return _HeaderActions(
      searchAction: searchAction,
      pinnedAction: pinnedAction,
      eventsAction: eventsAction,
      appBarActions: appBarActions,
      primaryAction: primaryAction,
      openDisappearing: openDisappearing,
      openWallpaper: openWallpaper,
    );
  }

  /// Where the side panels go for this width, the header buttons that fit
  /// and whether search is inline.
  _ThreadLayoutFacts _resolveLayout(
    BuildContext context,
    BoxConstraints constraints,
    _ThreadFacts f,
    _HeaderActions h,
  ) {
    final _ThreadFacts(
      :thread,
      :profileLayout,
      :docsWidth,
      :conversationType,
      :directPeerId,
      :desktop,
    ) = f;
    final _HeaderActions(:searchAction, :eventsAction, :appBarActions) = h;
    // The notes and lists panel takes the profile's place when open.
    final docsPlacement = resolveSidePanel(
      ResizablePanel.docs,
      width: docsWidth,
      collapsed: !_workspaceOpen || !desktop,
      rowWidth: constraints.maxWidth,
      forced: true,
    );
    final showDocs = desktop && docsPlacement.shown;
    // Direct chats on desktop can show the other person's profile, in
    // a resizable panel that closes first when the window gets narrow.
    final profileUserId = desktop && conversationType == ConversationType.direct
        ? directPeerId
        : null;
    SidePanelPlacement placeProfile({
      required bool collapsed,
      bool forced = false,
    }) => resolveSidePanel(
      ResizablePanel.profile,
      width: profileLayout.width,
      collapsed: collapsed,
      rowWidth: constraints.maxWidth,
      forced: forced,
    );
    final profileFits = placeProfile(collapsed: false).shown;
    if (profileFits) {
      // There is room again; closing for lack of room applies again.
      _profileForced = false;
    }
    final profilePlacement = placeProfile(
      collapsed: profileLayout.collapsed || profileUserId == null,
      forced: _profileForced,
    );
    final showProfile = profilePlacement.shown;
    // What the chat itself gets, beside the panel that is open.
    final chatWidth =
        constraints.maxWidth -
        (showDocs
            ? docsPlacement.width
            : showProfile
            ? profilePlacement.width
            : 0);
    final compact = isCompactWidth(
      constraints.maxWidth - (showDocs ? docsPlacement.width : 0),
    );
    // Desktop puts the search field in the header when there is room.
    final inlineSearch = desktop && chatWidth >= 760;
    final profileAction = profileUserId == null
        ? null
        : ChatThreadAction(
            tooltip: showProfile ? tr('Hide profile') : tr('Show profile'),
            icon: Icons.view_sidebar_outlined,
            selectedIcon: Icons.view_sidebar_rounded,
            isSelected: showProfile,
            primary: true,
            onPressed: () {
              setState(() => _profileForced = !showProfile && !profileFits);
              ref
                  .read(panelLayoutProvider.notifier)
                  .setCollapsed(ResizablePanel.profile, showProfile);
            },
          );
    final headerActions = [
      for (final action in appBarActions)
        if (!inlineSearch || !identical(action, searchAction)) action,
      ?eventsAction,
      ?profileAction,
    ];
    final searchResultCount = _messageSearchQuery.trim().isEmpty
        ? null
        : thread.value == null
        ? null
        : ref
              .read(chatsRepositoryProvider)
              .searchThreadMessages(thread.value!.messages, _messageSearchQuery)
              .length;
    final resultLabel = searchResultCount == null
        ? null
        : searchResultCount == 1
        ? tr('1 result')
        : tr('{count} results', {'count': searchResultCount});
    final selecting = ref.watch(
      chatSelectionProvider(
        widget.conversationId,
      ).select((state) => state.active),
    );
    return _ThreadLayoutFacts(
      constraints: constraints,
      docsPlacement: docsPlacement,
      showDocs: showDocs,
      profileUserId: profileUserId,
      profilePlacement: profilePlacement,
      showProfile: showProfile,
      compact: compact,
      inlineSearch: inlineSearch,
      headerActions: headerActions,
      resultLabel: resultLabel,
      selecting: selecting,
    );
  }
}
