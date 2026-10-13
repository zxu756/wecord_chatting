import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/chats/mention_picker.dart';
import 'package:wecord/features/chats/message_forward_sheet.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/chats/poll_composer_sheet.dart';
import 'package:wecord/features/chats/poll_message.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';

final chatThreadProvider = FutureProvider.autoDispose
    .family<ChatThreadData, String>((ref, conversationId) async {
      final repository = ref.watch(chatsRepositoryProvider);
      final subscription = repository.threadChanges(conversationId).listen((_) {
        ref.invalidateSelf();
      });
      ref.onDispose(subscription.cancel);
      final results = await Future.wait([
        repository.listMessages(conversationId),
        repository.listReadMarkers(conversationId),
      ]);
      return ChatThreadData(
        messages: results[0] as List<ChatMessage>,
        readMarkers: results[1] as List<ConversationReadMarker>,
      );
    });

final chatActivityProvider = StreamProvider.autoDispose
    .family<ConversationActivity, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .conversationActivity(conversationId);
    });

final canManageThreadProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, threadId) {
    return ref.watch(chatsRepositoryProvider).canManageThread(threadId);
  },
);

/// Whether the current user may end others' polls in a conversation.
final canModeratePollsProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .canModeratePolls(conversationId);
    });

final chatConversationSummaryProvider = FutureProvider.autoDispose
    .family<ConversationSummary?, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .getConversationSummary(conversationId);
    });

class ChatThreadData {
  const ChatThreadData({required this.messages, required this.readMarkers});

  final List<ChatMessage> messages;
  final List<ConversationReadMarker> readMarkers;
}

/// A chat thread app bar action: an icon button when there is room, and a
/// labelled entry in the More menu on phones.
class ChatThreadAction {
  const ChatThreadAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selectedIcon,
    this.isSelected,
  });

  /// Also the label in the More menu.
  final String tooltip;
  final IconData icon;
  final IconData? selectedIcon;
  final bool? isSelected;
  final VoidCallback? onPressed;

  IconButton toIconButton() {
    return IconButton(
      tooltip: tooltip,
      isSelected: isSelected,
      icon: Icon(icon),
      selectedIcon: selectedIcon == null ? null : Icon(selectedIcon),
      onPressed: onPressed,
    );
  }
}

class _AnnouncementStrip extends StatelessWidget {
  const _AnnouncementStrip({required this.announcement});

  final String announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              announcement,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    required this.conversationId,
    this.title,
    this.avatarUrl,
    this.conversationType,
    this.extraActions = const [],
    this.onOpenThread,
    this.canSendMessages,
    this.slowmodeSeconds,
    this.topic,
    this.forumPost = false,
    this.onBack,
    super.key,
  });

  final String conversationId;
  final String? title;
  final String? avatarUrl;
  final ConversationType? conversationType;

  /// Added after the built-in app bar actions. On phones the first one stays
  /// visible next to search and the rest move into the More menu.
  final List<ChatThreadAction> extraActions;

  /// Opens a thread started here. Defaults to pushing it full screen.
  final ValueChanged<ThreadTarget>? onOpenThread;

  /// Whether the current user may send here; false replaces the composer
  /// with a notice. Defaults to what the conversation list says.
  final bool? canSendMessages;

  /// Seconds the current user waits between messages here (0 for none).
  /// Defaults to what the conversation list says.
  final int? slowmodeSeconds;

  /// A channel's topic, shown under the title instead of the online state;
  /// tapping it shows all of it.
  final String? topic;

  /// A forum post: its first message shows as the opening post, larger and
  /// with the post's title, and the rest as replies. Posts read top down:
  /// they open at the opening post, offering a jump to unread replies.
  final bool forumPost;

  /// Shows a back button in place of the avatar.
  final VoidCallback? onBack;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _composerController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  ChatsRepository? _typingRepository;
  VoiceMessageRecorder? _voiceMessageRecorder;
  late final StateController<String?> _activeConversationController;
  var _isSending = false;
  var _isPickingImage = false;
  var _isSendingImage = false;
  var _isRecordingVoice = false;
  var _isSendingVoice = false;
  var _isTypingShared = false;
  String? _sendError;
  String? _lastMarkedMessageId;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;
  var _isSearchingMessages = false;
  var _messageSearchQuery = '';
  var _isMentioning = false;
  var _mentionQuery = '';
  final _mentionDraft = MentionDraft();

  /// The command name typed after a leading `/`, while the command list
  /// shows, and the command Enter or Tab picks from it.
  String? _slashQuery;
  var _slashIndex = 0;

  /// What the conversation allows, refreshed on every build.
  var _slashContext = const SlashCommandContext();
  String? _circleId;
  var _hasCapturedReadPosition = false;
  String? _newMessageDividerId;
  var _isAtBottom = true;
  String? _latestMessageId;
  String? _latestSeenMessageId;
  var _unseenMessageCount = 0;

  /// Whether the reader took (or no longer needs) the jump to a forum
  /// post's unread replies.
  var _newRepliesDismissed = false;
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// When the server last refused a message for slowmode, the time it said
  /// the next one is allowed.
  DateTime? _slowmodeRetryAt;

  /// The end of the current slowmode wait, refreshed on every build.
  DateTime? _slowmodeUntil;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _activeConversationController = ref.read(
      activeConversationIdProvider.notifier,
    );
    _scheduleActiveConversationUpdate(widget.conversationId);
  }

  @override
  void didUpdateWidget(covariant ChatThreadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _scheduleActiveConversationUpdate(widget.conversationId);
      _hasCapturedReadPosition = false;
      _newMessageDividerId = null;
      _isAtBottom = true;
      _latestMessageId = null;
      _latestSeenMessageId = null;
      _unseenMessageCount = 0;
      _newRepliesDismissed = false;
      _messageKeys.clear();
      _highlightTimer?.cancel();
      _highlightedMessageId = null;
      _slowmodeRetryAt = null;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _highlightTimer?.cancel();
    if (_isTypingShared) {
      unawaited(
        _typingRepository
            ?.setTyping(conversationId: widget.conversationId, isTyping: false)
            .catchError((Object _) {}),
      );
    }
    if (_isRecordingVoice) {
      unawaited(_voiceMessageRecorder?.cancel().catchError((Object _) {}));
    }
    final conversationId = widget.conversationId;
    Future<void>.microtask(() {
      if (!_activeConversationController.mounted) {
        return;
      }
      if (_activeConversationController.state == conversationId) {
        _activeConversationController.state = null;
      }
    });
    _composerController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleActiveConversationUpdate(String conversationId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _activeConversationController.state = conversationId;
    });
  }

  /// [actions] as app bar buttons. Phones keep the first one (search) and
  /// [primary], and list the rest under More.
  List<Widget> _appBarActions({
    required bool compact,
    required List<ChatThreadAction> actions,
    required ChatThreadAction primary,
  }) {
    if (!compact || actions.length <= 2) {
      return [for (final action in actions) action.toIconButton()];
    }
    final search = actions.first;
    final overflow = [
      for (final action in actions)
        if (!identical(action, search) && !identical(action, primary)) action,
    ];
    return [
      search.toIconButton(),
      primary.toIconButton(),
      PopupMenuButton<ChatThreadAction>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => action.onPressed?.call(),
        itemBuilder: (context) => [
          for (final action in overflow)
            PopupMenuItem(
              value: action,
              enabled: action.onPressed != null,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  action.isSelected == true
                      ? action.selectedIcon ?? action.icon
                      : action.icon,
                ),
                title: Text(action.tooltip),
              ),
            ),
        ],
      ),
    ];
  }

  void _toggleMessageSearch() {
    setState(() {
      _isSearchingMessages = !_isSearchingMessages;
      if (!_isSearchingMessages) {
        _searchController.clear();
        _messageSearchQuery = '';
      }
    });
  }

  void _showTopic(String title, String topic) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: SelectableText(topic),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGroupDetails(String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return GroupDetailSheet(
          conversationId: widget.conversationId,
          title: title,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
    final activity = ref.watch(chatActivityProvider(widget.conversationId));
    _voiceMessageRecorder = ref.watch(voiceMessageRecorderProvider);
    final conversationSummary = ref
        .watch(chatConversationSummaryProvider(widget.conversationId))
        .valueOrNull;
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id;
    final title = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : conversationSummary?.title?.trim().isNotEmpty == true
        ? conversationSummary!.title!.trim()
        : 'Conversation';
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
        ? ref.watch(groupDetailProvider(widget.conversationId)).valueOrNull
        : null;
    final threadId = isThread ? conversationSummary?.threadId : null;
    final canManageThread =
        threadId != null &&
        (ref.watch(canManageThreadProvider(threadId)).valueOrNull ?? false);
    final threadArchived = conversationSummary?.threadArchivedAt != null;
    final canSend =
        widget.canSendMessages ?? conversationSummary?.canSendMessages ?? true;
    final slowmodeSeconds =
        widget.slowmodeSeconds ?? conversationSummary?.slowmodeSeconds ?? 0;
    _circleId = conversationSummary?.circleId;
    _slashContext = SlashCommandContext(
      isCircleConversation: _circleId != null,
      canCreatePolls: true,
    );
    _slowmodeUntil = slowmodeSeconds > 0
        ? _slowmodeEnd(
            messages: thread.valueOrNull?.messages ?? const [],
            currentUserId: currentUserId,
            slowmodeSeconds: slowmodeSeconds,
            retryAt: _slowmodeRetryAt,
          )
        : null;
    final currentActivity =
        activity.valueOrNull ?? const ConversationActivity();
    // A direct peer is online when they have the app open anywhere; in
    // groups and channels this still means another member is viewing.
    final onlineUserIds =
        ref.watch(onlineUserIdsProvider).valueOrNull ?? const <String>{};
    final directPeerId = conversationType == ConversationType.direct
        ? conversationSummary?.directUserId ??
              _directPeerId(thread.valueOrNull?.readMarkers, currentUserId)
        : null;
    final peerIsOnline = conversationType == ConversationType.direct
        ? directPeerId != null && onlineUserIds.contains(directPeerId)
        : currentActivity.onlineUserIds.any((id) {
            return id != currentUserId;
          });
    final peerIsTyping = currentActivity.typingUserIds.any((id) {
      return id != currentUserId;
    });
    final canPinMessages =
        ref.watch(canPinMessagesProvider(widget.conversationId)).valueOrNull ??
        false;
    final canModeratePolls =
        ref
            .watch(canModeratePollsProvider(widget.conversationId))
            .valueOrNull ??
        false;
    final pollActions = PollActions(
      onVote: _votePoll,
      onEnd: _endPoll,
      onShowVoters: _showPollVoters,
      canEnd: (message) =>
          canSend &&
          (canModeratePolls ||
              (currentUserId != null && message.senderId == currentUserId)),
    );

    final searchAction = ChatThreadAction(
      tooltip: 'Search messages',
      icon: Icons.search,
      onPressed: _toggleMessageSearch,
    );
    final pinnedAction = ChatThreadAction(
      tooltip: 'Pinned messages',
      icon: Icons.push_pin_outlined,
      onPressed: () => _showPinnedMessages(canPinMessages),
    );
    final groupDetailsAction = conversationType == ConversationType.group
        ? ChatThreadAction(
            tooltip: 'Group details',
            icon: Icons.group_outlined,
            onPressed: () => _showGroupDetails(title),
          )
        : null;
    final threadNoun = widget.forumPost ? 'post' : 'thread';
    final archiveAction = canManageThread
        ? ChatThreadAction(
            tooltip: threadArchived
                ? 'Unarchive $threadNoun'
                : 'Archive $threadNoun',
            icon: threadArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            onPressed: () => _setThreadArchived(threadId, !threadArchived),
          )
        : null;
    final appBarActions = [
      searchAction,
      pinnedAction,
      ChatThreadAction(
        tooltip: 'Media',
        icon: Icons.photo_library_outlined,
        onPressed: () {
          context.push(ChatMediaScreen.pathFor(widget.conversationId));
        },
      ),
      ?groupDetailsAction,
      ?archiveAction,
      ...widget.extraActions,
    ];
    // Next to search on phones: the circle's member list, the group's
    // details, or a managed thread's archive toggle.
    final primaryAction =
        widget.extraActions.firstOrNull ??
        groupDetailsAction ??
        archiveAction ??
        pinnedAction;

    // Measured here rather than from the screen, so a thread panel in the
    // wide circle layout also gets the compact app bar.
    return LayoutBuilder(
      builder: (context, constraints) => Scaffold(
        appBar: AppBar(
          leading: widget.onBack != null
              ? IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                )
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: isThread
                      ? const CircleAvatar(child: Icon(Icons.forum_outlined))
                      : _ThreadAvatar(title: title, avatarUrl: avatarUrl),
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // A notch smaller than a plain app bar title, so long names
              // keep more of themselves next to the subtitle on phones.
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (topic != null)
                InkWell(
                  key: const ValueKey('chat-thread-topic'),
                  onTap: () => _showTopic(title, topic),
                  child: Text(
                    topic,
                    key: const ValueKey('chat-thread-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                )
              else
                Text(
                  isThread
                      ? _threadSubtitle(conversationSummary)
                      : [
                          peerIsOnline ? 'Online' : 'Offline',
                          if (conversationType == ConversationType.direct)
                            ?activeCustomStatus(
                              conversationSummary?.directCustomStatus,
                            )?.label,
                        ].join(' · '),
                  key: const ValueKey('chat-thread-subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          actions: _appBarActions(
            compact: isCompactWidth(constraints.maxWidth),
            actions: appBarActions,
            primary: primaryAction,
          ),
        ),
        body: Column(
          children: [
            if (conversationType == ConversationType.group &&
                conversationSummary?.announcement.trim().isNotEmpty == true)
              _AnnouncementStrip(
                announcement: conversationSummary!.announcement.trim(),
              ),
            if (_isSearchingMessages)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Search messages',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _messageSearchQuery = value;
                          });
                        },
                      ),
                    ),
                    if (_messageSearchQuery.trim().isNotEmpty) ...[
                      const SizedBox(width: 12),
                      thread.maybeWhen(
                        data: (data) {
                          final resultCount = ref
                              .read(chatsRepositoryProvider)
                              .searchThreadMessages(
                                data.messages,
                                _messageSearchQuery,
                              )
                              .length;
                          return Text(
                            '$resultCount ${resultCount == 1 ? 'result' : 'results'}',
                          );
                        },
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: thread.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Center(
                  child: Text(
                    error.toString(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                data: (data) {
                  final messages = data.messages;
                  final visibleMessages = ref
                      .read(chatsRepositoryProvider)
                      .searchThreadMessages(messages, _messageSearchQuery);
                  final messagesById = {
                    for (final message in messages) message.id: message,
                  };
                  final fullOldestToNewest = _messagesOldestToNewest(messages);
                  _captureNewMessageDivider(
                    fullOldestToNewest,
                    data.readMarkers,
                    currentUserId,
                  );
                  _trackUnseenMessages(fullOldestToNewest, currentUserId);
                  _markReadAfterLoad(messages);
                  _reconcileActiveMessageState(messagesById);
                  if (messages.isEmpty) {
                    return const Center(child: Text('No messages yet'));
                  }
                  if (visibleMessages.isEmpty) {
                    return const Center(child: Text('No matching messages'));
                  }

                  final visibleOldestToNewest = _messagesOldestToNewest(
                    visibleMessages,
                  );
                  // Chats list newest first from the bottom; forum posts read
                  // top down from the opening post.
                  final ordered = widget.forumPost
                      ? visibleOldestToNewest
                      : visibleOldestToNewest.reversed.toList(growable: false);
                  final latestOutgoingReadState = _latestOutgoingReadState(
                    messages: fullOldestToNewest,
                    readMarkers: data.readMarkers,
                    currentUserId: currentUserId,
                  );
                  // Grouping compares neighbours, which search results are not.
                  final followUpIds = _messageSearchQuery.trim().isEmpty
                      ? _followUpMessageIds(
                          visibleOldestToNewest,
                          newMessageDividerId: _newMessageDividerId,
                        )
                      : <String>{};
                  // A forum post opens with its first message; replies start
                  // their own group under it.
                  final openingPostId = widget.forumPost
                      ? fullOldestToNewest
                            .where(
                              (message) => message.type != MessageType.system,
                            )
                            .firstOrNull
                            ?.id
                      : null;
                  if (openingPostId != null) {
                    final index = visibleOldestToNewest.indexWhere(
                      (message) => message.id == openingPostId,
                    );
                    if (index >= 0 &&
                        index + 1 < visibleOldestToNewest.length) {
                      followUpIds.remove(visibleOldestToNewest[index + 1].id);
                    }
                  }
                  final showSenders = canStartThreads || isThread;
                  final membersById = {
                    for (final member
                        in groupDetail?.members ?? const <GroupMember>[])
                      member.profile.id: member,
                  };

                  final list = ListView.builder(
                    key: const ValueKey('chat-message-list'),
                    controller: _scrollController,
                    reverse: !widget.forumPost,
                    padding: const EdgeInsets.all(16),
                    itemCount: ordered.length,
                    itemBuilder: (context, index) {
                      final message = ordered[index];
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
                          sender: _senderFor(message, membersById),
                          isOpeningPost: true,
                          postTitle: title,
                          replyCount: messages
                              .where(
                                (other) =>
                                    other.id != message.id &&
                                    other.type != MessageType.system &&
                                    other.recalledAt == null,
                              )
                              .length,
                          isFollowUp: false,
                          hasFollowUp: false,
                          showReadReceipt: false,
                          canCompose: canSend,
                          onReply: _startReply,
                          onEdit: _startEdit,
                          onForward: _showForwardSheet,
                          onDelete: _deleteMessage,
                          onPreviewImage: _previewImage,
                          onToggleReaction: _toggleReaction,
                          onShowReactors: _showReactors,
                          canPin: canPinMessages,
                          onTogglePin: _togglePin,
                          onRemoveEmbed: _removeEmbed,
                          canStartThread: false,
                          pollActions: pollActions,
                        );
                      } else {
                        final isCurrentUser = message.isSentBy(currentUserId);
                        final newerIndex = widget.forumPost
                            ? index + 1
                            : index - 1;
                        final newerMessage =
                            newerIndex < 0 || newerIndex >= ordered.length
                            ? null
                            : ordered[newerIndex];
                        bubble = _MessageBubble(
                          message: message,
                          messagesById: messagesById,
                          isCurrentUser: isCurrentUser,
                          sender: showSenders && !isCurrentUser
                              ? _senderFor(message, membersById)
                              : null,
                          isFollowUp: followUpIds.contains(message.id),
                          hasFollowUp:
                              newerMessage != null &&
                              followUpIds.contains(newerMessage.id),
                          showReadReceipt:
                              latestOutgoingReadState.latestOutgoingMessageId ==
                                  message.id &&
                              latestOutgoingReadState.isRead,
                          canCompose: canSend,
                          onReply: _startReply,
                          onEdit: _startEdit,
                          onForward: _showForwardSheet,
                          onDelete: _deleteMessage,
                          onPreviewImage: _previewImage,
                          onToggleReaction: _toggleReaction,
                          onShowReactors: _showReactors,
                          canPin: canPinMessages,
                          onTogglePin: _togglePin,
                          onRemoveEmbed: _removeEmbed,
                          canStartThread: canStartThreads && canSend,
                          onOpenThread: _openOrCreateThread,
                          pollActions: pollActions,
                        );
                      }
                      final highlighted = AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: message.id == _highlightedMessageId
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: bubble,
                      );
                      return KeyedSubtree(
                        key: _messageKeys.putIfAbsent(
                          message.id,
                          GlobalKey.new,
                        ),
                        child: message.id == _newMessageDividerId
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _NewMessagesDivider(),
                                  highlighted,
                                ],
                              )
                            : highlighted,
                      );
                    },
                  );
                  final showJumpToLatest =
                      !_isAtBottom && _unseenMessageCount > 0;
                  final newRepliesId = _newMessageDividerId;
                  final showJumpToNewReplies =
                      widget.forumPost &&
                      !showJumpToLatest &&
                      !_isAtBottom &&
                      !_newRepliesDismissed &&
                      newRepliesId != null &&
                      newRepliesId != openingPostId &&
                      _messageSearchQuery.trim().isEmpty;
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
                      Positioned.fill(child: list),
                      if (showJumpToNewReplies)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton.extended(
                            key: const ValueKey('forum-jump-to-new-replies'),
                            heroTag: null,
                            tooltip: 'Jump to new replies',
                            onPressed: () {
                              setState(() => _newRepliesDismissed = true);
                              unawaited(_scrollToMessage(newRepliesId));
                            },
                            icon: const Icon(Icons.arrow_downward),
                            label: const Text('Jump to new replies'),
                          ),
                        ),
                      if (showJumpToLatest)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton.extended(
                            heroTag: null,
                            tooltip: 'Jump to latest',
                            onPressed: _jumpToLatest,
                            icon: const Icon(Icons.arrow_downward),
                            label: Text(
                              _unseenMessageCount == 1
                                  ? '1 new message'
                                  : '$_unseenMessageCount new messages',
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (peerIsTyping)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('typing...'),
                ),
              ),
            if (!canSend)
              const _ReadOnlyComposerNotice()
            else
              _SlowmodeGate(
                until: _slowmodeUntil,
                builder: (context, slowmodeRemaining) => _Composer(
                  slowmodeSeconds: slowmodeSeconds,
                  slowmodeRemainingSeconds: slowmodeRemaining,
                  controller: _composerController,
                  isSending: _isSending,
                  isPickingImage: _isPickingImage,
                  isSendingImage: _isSendingImage,
                  errorText: _sendError,
                  mentionCandidates: _mentionCandidates(groupDetail),
                  onSelectMention: _insertMention,
                  slashCommands: _slashCandidates(),
                  highlightedSlashIndex: _slashIndex,
                  onSelectSlashCommand: _selectSlashCommand,
                  onComposerKey: _handleComposerKey,
                  replyPreviewText: _replyingTo == null
                      ? null
                      : _replyPreviewBody(_replyingTo!),
                  isEditing: _editingMessage != null,
                  onChanged: _handleComposerChanged,
                  onSend: _sendMessage,
                  onPickImage: _pickAndSendImage,
                  onCreatePoll: _openPollComposer,
                  isRecordingVoice: _isRecordingVoice,
                  isSendingVoice: _isSendingVoice,
                  onStartVoiceRecording: _startVoiceRecording,
                  onCancelVoiceRecording: _cancelVoiceRecording,
                  onSendVoiceRecording: _sendVoiceRecording,
                  onCancelReply: _cancelReply,
                  onCancelEdit: _cancelEdit,
                  // What is left above the keyboard, so a short phone keeps
                  // some of the conversation in view while typing.
                  availableHeight:
                      constraints.maxHeight -
                      MediaQuery.viewInsetsOf(context).bottom,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Remembers where the reader left off before the thread marks itself read,
  /// so the NEW divider stays put for as long as the thread stays open.
  void _captureNewMessageDivider(
    List<ChatMessage> oldestToNewest,
    List<ConversationReadMarker> readMarkers,
    String? currentUserId,
  ) {
    if (_hasCapturedReadPosition) {
      return;
    }
    _hasCapturedReadPosition = true;
    _newMessageDividerId = _firstUnreadMessageId(
      messages: oldestToNewest,
      readMarkers: readMarkers,
      currentUserId: currentUserId,
    );
  }

  void _trackUnseenMessages(
    List<ChatMessage> oldestToNewest,
    String? currentUserId,
  ) {
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
    _unseenMessageCount = oldestToNewest
        .skip(seenIndex + 1)
        .where((message) => !message.isSentBy(currentUserId))
        .length;
  }

  void _handleScroll() {
    final bool isAtBottom;
    if (!_scrollController.hasClients) {
      isAtBottom = true;
    } else {
      final position = _scrollController.position;
      // Forum posts are not reversed, so their latest end is at the bottom.
      isAtBottom = widget.forumPost
          ? position.maxScrollExtent - position.pixels <= _bottomScrollThreshold
          : position.pixels <= _bottomScrollThreshold;
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
    if (widget.forumPost) {
      unawaited(_scrollToEnd());
      return;
    }
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
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

  Future<void> _sendMessage() async {
    final body = _composerController.text.trim();
    if (body.isEmpty || _isSending) {
      return;
    }

    final editingMessage = _editingMessage;
    if (editingMessage != null) {
      await _saveEdit(editingMessage, body);
      return;
    }

    final command = parseSlashCommand(
      body,
      context: _slashContext,
      random: ref.read(slashCommandRandomProvider),
    );
    final String messageBody;
    switch (command) {
      case SlashCommandError(:final message):
        setState(() => _sendError = message);
        return;
      case SlashSetNickname(:final nickname):
        await _runSlashAction(() => _setNicknameFromCommand(nickname));
        return;
      case SlashSetStatus():
        await _runSlashAction(() => _setStatusFromCommand(command));
        return;
      case SlashOpenPoll():
        _clearComposerAfterCommand();
        await _openPollComposer();
        return;
      case SlashSendText(body: final commandBody):
        messageBody = commandBody;
      case null:
        messageBody = body;
    }

    if (_isSlowedDown) {
      return;
    }

    final replyingTo = _replyingTo;
    setState(() {
      _isSending = true;
      _sendError = null;
    });

    try {
      final replyPreview = replyingTo == null
          ? null
          : _replyPreviewForMessage(replyingTo);
      await ref
          .read(chatsRepositoryProvider)
          .sendTextMessage(
            conversationId: widget.conversationId,
            body: messageBody,
            replyToMessageId: replyingTo?.id,
            replyPreview: replyPreview,
            mentions: _mentionsForBody(messageBody),
          );
      await _setTyping(false);
      _composerController.clear();
      _mentionDraft.clear();
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _replyingTo = null;
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not send message. Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _saveEdit(ChatMessage message, String body) async {
    setState(() {
      _isSending = true;
      _sendError = null;
    });

    try {
      await ref
          .read(chatsRepositoryProvider)
          .editMessage(messageId: message.id, body: body);
      await _setTyping(false);
      _composerController.clear();
      _editingMessage = null;
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not save edit. Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// Slowmode keeps the current user from sending a new message right now.
  bool get _isSlowedDown {
    final until = _slowmodeUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Counts down from the server's answer, which wins over the local
  /// estimate (clocks drift, and other devices may have sent meanwhile).
  void _waitOutSlowmode(SlowmodeException error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _slowmodeRetryAt = DateTime.now().add(
        Duration(seconds: error.remainingSeconds),
      );
      _sendError = null;
    });
  }

  Future<void> _pickAndSendImage() async {
    if (_isPickingImage || _isSendingImage || _isSending || _isSlowedDown) {
      return;
    }

    setState(() {
      _isPickingImage = true;
      _sendError = null;
    });

    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isPickingImage = false;
        _isSendingImage = true;
      });
      await ref
          .read(chatsRepositoryProvider)
          .sendImageMessage(
            conversationId: widget.conversationId,
            image: image,
          );
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sendError = _imageSendErrorText(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
          _isSendingImage = false;
        });
      }
    }
  }

  Future<void> _openPollComposer() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    final posted = await showPollComposerSheet(
      context,
      conversationId: widget.conversationId,
    );
    if (posted == true && mounted) {
      ref.invalidate(chatThreadProvider(widget.conversationId));
    }
  }

  Future<void> _votePoll(ChatMessage message, List<String> optionIds) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .votePoll(messageId: message.id, optionIds: optionIds);
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } catch (_) {
      _showSnackBar('Could not record your vote. Try again.');
      rethrow;
    }
  }

  Future<void> _endPoll(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('End poll'),
        content: const Text(
          'End this poll now? Nobody can vote after it ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('poll-end-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End poll'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(chatsRepositoryProvider).endPoll(messageId: message.id);
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } catch (_) {
      _showSnackBar('Could not end the poll. Try again.');
    }
  }

  void _showPollVoters(ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => PollVotersSheet(message: message),
    );
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice ||
        _isSendingVoice ||
        _isSending ||
        _editingMessage != null ||
        _isSlowedDown) {
      return;
    }

    setState(() {
      _sendError = null;
    });

    try {
      await _voiceRecorder.start();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not start recording. Check microphone access.';
        });
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice || _isSendingVoice) {
      return;
    }

    try {
      await _voiceRecorder.cancel();
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
        });
      }
    }
  }

  Future<void> _sendVoiceRecording() async {
    if (!_isRecordingVoice || _isSendingVoice) {
      return;
    }

    setState(() {
      _isSendingVoice = true;
      _sendError = null;
    });

    try {
      final recording = await _voiceRecorder.stop();
      if (recording == null) {
        return;
      }
      await ref
          .read(chatsRepositoryProvider)
          .sendVoiceMessage(
            conversationId: widget.conversationId,
            bytes: recording.bytes,
            mimeType: recording.mimeType,
            durationMs: recording.durationMs,
          );
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not send voice message. Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _isSendingVoice = false;
        });
      }
    }
  }

  VoiceMessageRecorder get _voiceRecorder =>
      _voiceMessageRecorder ?? ref.read(voiceMessageRecorderProvider);

  void _handleComposerChanged(String value) {
    _updateMentionQuery();
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

  void _updateSlashQuery() {
    final query = slashCommandQueryAt(_composerController.text);
    if (query == _slashQuery) {
      return;
    }
    setState(() {
      _slashQuery = query;
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
    final commands = _slashCandidates();
    if (commands.isEmpty || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        _slashIndex = (_slashIndex + step) % commands.length;
      });
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.tab)) {
      _selectSlashCommand(commands[_slashIndex.clamp(0, commands.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clearComposerAfterCommand() {
    _composerController.clear();
    _mentionDraft.clear();
    setState(() {
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _sendError = null;
    });
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
      _showSnackBar('Could not change nickname. Try again.');
      return false;
    }
    // Messages, mentions and member lists show nicknames.
    ref.invalidate(chatThreadProvider);
    ref.invalidate(groupDetailProvider);
    ref.invalidate(circleDetailProvider(circleId));
    _showSnackBar(
      nickname == null
          ? 'Your nickname was reset.'
          : 'Your nickname is now $nickname.',
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
            ? 'Could not clear status. Try again.'
            : 'Could not set status. Try again.',
      );
      return false;
    }
    ref.invalidate(currentProfileProvider);
    _showSnackBar(
      status.clears
          ? 'Status cleared.'
          : 'Status set to ${CustomStatus(emoji: status.emoji, text: status.text).label}.',
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
  }

  List<MessageMention> _mentionsForBody(String body) {
    return _mentionDraft.mentionsFor(body);
  }

  Future<void> _setTyping(bool isTyping) async {
    if (_isTypingShared == isTyping) {
      return;
    }
    _isTypingShared = isTyping;
    var repository = _typingRepository;
    if (repository == null) {
      repository = ref.read(chatsRepositoryProvider);
      _typingRepository = repository;
    }
    final activeRepository = repository!;
    await activeRepository
        .setTyping(conversationId: widget.conversationId, isTyping: isTyping)
        .catchError((Object _) {});
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .recallMessage(messageId: message.id);
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not delete message. Try again.';
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
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not update reaction. Try again.';
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
      ref.invalidate(chatThreadProvider(widget.conversationId));
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    } on PinnedMessageLimitException {
      _showSnackBar(
        'This conversation already has $maxPinnedMessagesPerConversation '
        'pinned messages.',
      );
    } catch (_) {
      _showSnackBar(
        message.isPinned
            ? 'Could not unpin message. Try again.'
            : 'Could not pin message. Try again.',
      );
    }
  }

  Future<void> _removeEmbed(ChatMessage message) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .setMessageSuppressEmbeds(messageId: message.id, suppress: true);
      ref.invalidate(chatThreadProvider(widget.conversationId));
    } catch (_) {
      _showSnackBar('Could not remove the link preview. Try again.');
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
          _ThreadTitleDialog(initialTitle: _suggestedTitleFor(message)),
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
      ref.invalidate(chatThreadProvider(widget.conversationId));
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
      _showSnackBar('Could not create thread. Try again.');
    }
  }

  Future<void> _setThreadArchived(String threadId, bool archived) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .setThreadArchived(threadId: threadId, archived: archived);
      ref.invalidate(chatConversationSummaryProvider(widget.conversationId));
      ref.invalidate(conversationsProvider);
      _showSnackBar(archived ? 'Thread archived.' : 'Thread unarchived.');
    } catch (_) {
      _showSnackBar(
        archived
            ? 'Could not archive thread. Try again.'
            : 'Could not unarchive thread. Try again.',
      );
    }
  }

  Future<void> _unpinFromList(String messageId) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .unpinMessage(messageId: messageId);
      ref.invalidate(chatThreadProvider(widget.conversationId));
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    } catch (_) {
      _showSnackBar('Could not unpin message. Try again.');
    }
  }

  Future<void> _showPinnedMessages(bool canManagePins) async {
    ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    final messageId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
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

  /// Scrolls the thread to [messageId] and briefly highlights it. The list is
  /// built lazily, so walk up from the newest message until it is built.
  Future<void> _scrollToMessage(String messageId) async {
    final messages =
        ref
            .read(chatThreadProvider(widget.conversationId))
            .valueOrNull
            ?.messages ??
        const <ChatMessage>[];
    if (!messages.any((message) => message.id == messageId)) {
      _showSnackBar('That message is not loaded.');
      return;
    }
    if (_messageSearchQuery.trim().isNotEmpty) {
      setState(() {
        _searchController.clear();
        _messageSearchQuery = '';
      });
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_scrollController.hasClients) {
      return;
    }

    if (_messageKeys[messageId]?.currentContext == null) {
      _scrollController.jumpTo(0);
      for (var attempt = 0; attempt < 500; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        if (_messageKeys[messageId]?.currentContext != null) {
          break;
        }
        final position = _scrollController.position;
        if (position.pixels >= position.maxScrollExtent) {
          break;
        }
        _scrollController.jumpTo(
          (position.pixels + position.viewportDimension * 0.8).clamp(
            0.0,
            position.maxScrollExtent,
          ),
        );
      }
    }

    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      _showSnackBar('That message is not loaded.');
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

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _showReactors(ChatMessage message, MessageReaction reaction) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return MessageReactorsSheet(
          messageId: message.id,
          emoji: reaction.emoji,
        );
      },
    );
  }

  void _startReply(ChatMessage message) {
    if (message.recalledAt != null) {
      return;
    }
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
      _sendError = null;
    });
  }

  void _startEdit(ChatMessage message) {
    if (message.recalledAt != null || message.type != MessageType.text) {
      return;
    }
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _sendError = null;
      _composerController.text = message.body;
      _composerController.selection = TextSelection.collapsed(
        offset: _composerController.text.length,
      );
    });
  }

  void _showForwardSheet(ChatMessage message) {
    if (message.recalledAt != null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => MessageForwardSheet(message: message),
    );
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _composerController.clear();
    });
  }

  Future<void> _previewImage(ImageAttachment attachment) async {
    try {
      final url = await ref
          .read(chatsRepositoryProvider)
          .createImageUrl(attachment);
      if (!mounted) {
        return;
      }
      showImagePreview(context, url);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = 'Could not open image preview. Try again.';
        });
      }
    }
  }
}

/// "in #channel" (or "in Group") under a thread's title.
String _threadSubtitle(ConversationSummary? summary) {
  final parentTitle = summary?.parentTitle?.trim();
  if (parentTitle == null || parentTitle.isEmpty) {
    return 'Thread';
  }
  final archived = summary?.threadArchivedAt != null ? ' · Archived' : '';
  return summary?.circleId != null
      ? 'in #$parentTitle$archived'
      : 'in $parentTitle$archived';
}

String _suggestedTitleFor(ChatMessage message) {
  return switch (message.type) {
    MessageType.text => suggestedThreadTitle(
      plainTextFromMarkdown(message.body),
    ),
    MessageType.image => 'Image',
    MessageType.voice => 'Voice message',
    MessageType.file => 'File',
    MessageType.system => 'Thread',
    MessageType.poll => suggestedThreadTitle(message.body),
  };
}

/// Asks for a thread title. Returns the trimmed title, or null when
/// cancelled.
class _ThreadTitleDialog extends StatefulWidget {
  const _ThreadTitleDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_ThreadTitleDialog> createState() => _ThreadTitleDialogState();
}

class _ThreadTitleDialogState extends State<_ThreadTitleDialog> {
  late final _controller = TextEditingController(text: widget.initialTitle);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = 'Thread title is required.');
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Create thread'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: ConversationThread.maxTitleLength,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Thread title',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}

/// "n replies · time" under a thread's root message; opens the thread.
class _ThreadChip extends StatelessWidget {
  const _ThreadChip({
    required this.messageId,
    required this.summary,
    required this.onTap,
  });

  final String messageId;
  final MessageThreadSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final unread = summary.unreadCount > 0;
    final replies = switch (summary.replyCount) {
      0 => 'No replies yet',
      1 => '1 reply',
      final count => '$count replies',
    };
    final lastReplyAt = summary.lastReplyAt;
    final detail = summary.replyCount > 0 && lastReplyAt != null
        ? '$replies · ${formatThreadActivity(lastReplyAt)}'
        : replies;
    return Material(
      key: ValueKey('thread-chip-$messageId'),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          // Title and activity sit on their own lines so neither is squeezed
          // out on narrow screens.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: unread
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: unread ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('thread-chip-unread'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How long ago a thread was last active: "just now", "5m ago", "3h ago",
/// then the date.
String formatThreadActivity(DateTime value, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final difference = current.difference(value.toUtc());
  if (difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h ago';
  }
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}

/// The other member of a direct conversation, from its read markers (one
/// per member).
String? _directPeerId(
  List<ConversationReadMarker>? readMarkers,
  String? currentUserId,
) {
  for (final marker in readMarkers ?? const <ConversationReadMarker>[]) {
    if (marker.userId != currentUserId) {
      return marker.userId;
    }
  }
  return null;
}

const _bottomScrollThreshold = 48.0;

const _senderAvatarSize = 32.0;

/// Messages from the same sender this close together read as one group.
const _messageGroupWindow = Duration(minutes: 7);

/// Ids of messages that continue the previous message's group: same sender,
/// at most [_messageGroupWindow] apart, on the same day, and with no system
/// notice or NEW divider between them.
Set<String> _followUpMessageIds(
  List<ChatMessage> oldestToNewest, {
  required String? newMessageDividerId,
}) {
  final ids = <String>{};
  for (var index = 1; index < oldestToNewest.length; index++) {
    final previous = oldestToNewest[index - 1];
    final message = oldestToNewest[index];
    if (message.type == MessageType.system ||
        previous.type == MessageType.system ||
        message.authorKey != previous.authorKey ||
        message.id == newMessageDividerId) {
      continue;
    }
    final gap = message.createdAt.difference(previous.createdAt);
    if (gap.isNegative || gap > _messageGroupWindow) {
      continue;
    }
    if (!_isSameLocalDay(previous.createdAt, message.createdAt)) {
      continue;
    }
    ids.add(message.id);
  }
  return ids;
}

bool _isSameLocalDay(DateTime left, DateTime right) {
  final localLeft = left.toLocal();
  final localRight = right.toLocal();
  return localLeft.year == localRight.year &&
      localLeft.month == localRight.month &&
      localLeft.day == localRight.day;
}

/// Name and avatar shown above a group of incoming messages.
_MessageSender _senderFor(
  ChatMessage message,
  Map<String, GroupMember> membersById,
) {
  // Webhook messages show the webhook, never its creator's profile.
  if (message.webhookName case final webhookName?) {
    return _MessageSender(
      name: webhookName,
      avatarUrl: message.webhookAvatarUrl,
      isBot: true,
    );
  }
  final member = membersById[message.senderId];
  final profile = message.sender ?? member?.profile;
  final nickname = (message.senderNickname ?? member?.nickname)?.trim() ?? '';
  final label = nickname.isNotEmpty
      ? nickname
      : profile?.displayLabel.trim() ?? '';
  return _MessageSender(
    name: label.isNotEmpty
        ? label
        : profile?.username.trim().isNotEmpty == true
        ? profile!.username
        : 'Unknown member',
    avatarUrl: profile?.avatarUrl,
    roleColor: message.senderRoleColor,
  );
}

class _MessageSender {
  const _MessageSender({
    required this.name,
    this.avatarUrl,
    this.roleColor,
    this.isBot = false,
  });

  final String name;
  final String? avatarUrl;

  /// A webhook, marked with a BOT tag.
  final bool isBot;

  /// The sender's highest coloured circle role, as 0xRRGGBB.
  final int? roleColor;
}

/// The small "BOT" label next to a webhook's name.
class _BotTag extends StatelessWidget {
  const _BotTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('message-bot-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'BOT',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          height: 1.2,
        ),
      ),
    );
  }
}

class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: color, height: 1)),
          const SizedBox(width: 8),
          Text(
            'NEW',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadAvatar extends ConsumerWidget {
  const _ThreadAvatar({
    required this.title,
    required this.avatarUrl,
    this.radius,
  });

  final String title;
  final String? avatarUrl;
  final double? radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref.watch(avatarDisplayUrlProvider(avatarUrl));
    final image = displayUrl.valueOrNull == null
        ? null
        : NetworkImage(displayUrl.valueOrNull!);
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      onBackgroundImageError: image == null ? null : (_, _) {},
      child: image == null ? Text(_initials(title)) : null,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.messagesById,
    required this.isCurrentUser,
    required this.showReadReceipt,
    required this.onReply,
    this.canCompose = true,
    this.sender,
    this.isFollowUp = false,
    this.hasFollowUp = false,
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
  });

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final bool isCurrentUser;

  /// Votes, voter lists and ending for poll messages.
  final PollActions? pollActions;

  /// The first message of a forum post, shown full width and larger with
  /// [postTitle] above it and [replyCount] below.
  final bool isOpeningPost;
  final String? postTitle;
  final int replyCount;
  final bool showReadReceipt;

  /// Who sent an incoming message in a group or channel; null hides the
  /// avatar column entirely (own messages, direct chats).
  final _MessageSender? sender;

  /// Continues the previous message's group, so the avatar and name are
  /// left out.
  final bool isFollowUp;

  /// The next message continues this one's group, so the gap below shrinks.
  final bool hasFollowUp;

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

  /// The link whose preview card shows under this message, if any.
  String? get _previewUrl {
    if (message.recalledAt != null ||
        message.type != MessageType.text ||
        message.suppressEmbeds) {
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

  Widget _buildOpeningPost(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRecalled = message.recalledAt != null;
    final image = _openingPostImage;
    final sender = this.sender;
    final previewUrl = _previewUrl;
    final reactions = isRecalled
        ? const <MessageReaction>[]
        : message.reactions;
    final replies = switch (replyCount) {
      0 => 'No replies yet',
      1 => '1 reply',
      final count => '$count replies',
    };

    return Padding(
      key: const ValueKey('forum-opening-post'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onLongPress: isRecalled ? null : () => _showActions(context, image),
            onSecondaryTapDown: isRecalled
                ? null
                : (_) => _showActions(context, image),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (postTitle case final title?) ...[
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      _ThreadAvatar(
                        title: sender?.name ?? '?',
                        avatarUrl: sender?.avatarUrl,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sender?.name ?? 'Someone',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: switch (sender?.roleColor) {
                                  final color? => Color(0xFF000000 | color),
                                  null => colorScheme.onSurface,
                                },
                              ),
                            ),
                            Text(
                              formatThreadActivity(message.createdAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isRecalled)
                    Text(
                      'Message deleted',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else if (message.body.trim().isNotEmpty)
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyLarge,
                      child: MessageMarkdownText(
                        body: message.body,
                        mentions: message.mentions,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  if (image != null) ...[
                    const SizedBox(height: 12),
                    _ImageMessageContent(attachment: image),
                  ],
                  if (message.editedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'edited',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (previewUrl != null)
                    MessageLinkPreviewCard(url: previewUrl, bottomGap: 0),
                  if (reactions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    MessageReactionChips(
                      reactions: reactions,
                      onToggle: (emoji) =>
                          unawaited(onToggleReaction(message, emoji)),
                      onShowReactors: (reaction) =>
                          onShowReactors(message, reaction),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  replies,
                  key: const ValueKey('forum-opening-post-replies'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: Divider()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isOpeningPost) {
      return _buildOpeningPost(context);
    }
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = isCurrentUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final textColor = isCurrentUser
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final isRecalled = message.recalledAt != null;
    final imageAttachment = isRecalled ? null : message.imageAttachment;
    final voiceAttachment = isRecalled ? null : message.voiceAttachment;
    final canShowActions = !isRecalled;
    final reactions = isRecalled
        ? const <MessageReaction>[]
        : message.reactions;
    final gap = hasFollowUp ? 2.0 : 8.0;
    final sender = this.sender;
    final previewUrl = _previewUrl;

    final column = Column(
      crossAxisAlignment: isCurrentUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (sender != null && !isFollowUp)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    sender.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: switch (sender.roleColor) {
                        final color? => Color(0xFF000000 | color),
                        null => colorScheme.onSurface,
                      },
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (sender.isBot) ...[
                  const SizedBox(width: 6),
                  const _BotTag(),
                ],
              ],
            ),
          ),
        Align(
          alignment: isCurrentUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: GestureDetector(
              onLongPress: canShowActions
                  ? () => _showActions(context, imageAttachment)
                  : null,
              onSecondaryTapDown: canShowActions
                  ? (_) => _showActions(context, imageAttachment)
                  : null,
              child: Container(
                margin: EdgeInsets.only(
                  bottom: showReadReceipt || reactions.isNotEmpty ? 4 : gap,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _MessageContent(
                  message: message,
                  messagesById: messagesById,
                  imageAttachment: imageAttachment,
                  voiceAttachment: voiceAttachment,
                  textColor: textColor,
                  isRecalled: isRecalled,
                  pollActions: pollActions,
                ),
              ),
            ),
          ),
        ),
        if (previewUrl != null)
          MessageLinkPreviewCard(
            url: previewUrl,
            bottomGap: showReadReceipt || reactions.isNotEmpty ? 4 : gap,
          ),
        if (message.threadSummary case final thread? when onOpenThread != null)
          Padding(
            padding: EdgeInsets.only(
              bottom: showReadReceipt || reactions.isNotEmpty ? 4 : gap,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: _ThreadChip(
                messageId: message.id,
                summary: thread,
                onTap: () => unawaited(onOpenThread!(message)),
              ),
            ),
          ),
        if (reactions.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: showReadReceipt ? 4 : gap),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: MessageReactionChips(
                reactions: reactions,
                onToggle: (emoji) =>
                    unawaited(onToggleReaction(message, emoji)),
                onShowReactors: (reaction) => onShowReactors(message, reaction),
              ),
            ),
          ),
        if (showReadReceipt)
          Padding(
            padding: EdgeInsets.only(right: 4, bottom: gap),
            child: Text(
              'Read',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
    if (sender == null) {
      return column;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _senderAvatarSize,
          child: isFollowUp
              ? null
              : _ThreadAvatar(
                  title: sender.name,
                  avatarUrl: sender.avatarUrl,
                  radius: _senderAvatarSize / 2,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(child: column),
      ],
    );
  }

  bool _hasVisiblePreview(BuildContext context) {
    final url = _previewUrl;
    if (url == null) {
      return false;
    }
    return ProviderScope.containerOf(
          context,
          listen: false,
        ).read(linkPreviewProvider(url)).valueOrNull !=
        null;
  }

  void _showActions(BuildContext context, ImageAttachment? imageAttachment) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QuickReactionBar(
                  reactedEmojis: {
                    for (final reaction in message.reactions)
                      if (reaction.reactedByMe) reaction.emoji,
                  },
                  onSelect: (emoji) {
                    Navigator.of(sheetContext).pop();
                    unawaited(onToggleReaction(message, emoji));
                  },
                  onMore: () async {
                    Navigator.of(sheetContext).pop();
                    final emoji = await showEmojiReactionPicker(context);
                    if (emoji != null) {
                      await onToggleReaction(message, emoji);
                    }
                  },
                ),
                const Divider(height: 1),
                if (canCompose)
                  ListTile(
                    leading: const Icon(Icons.reply_outlined),
                    title: const Text('Reply'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onReply(message);
                    },
                  ),
                if (onOpenThread != null &&
                    (message.threadSummary != null ||
                        (canStartThread && message.type != MessageType.system)))
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(
                      message.threadSummary == null
                          ? 'Create thread'
                          : 'Open thread',
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(onOpenThread!(message));
                    },
                  ),
                // A poll's votes belong to the original, so polls are not
                // forwarded.
                if (message.type != MessageType.poll)
                  ListTile(
                    leading: const Icon(Icons.forward_outlined),
                    title: const Text('Forward'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onForward(message);
                    },
                  ),
                if (canCompose &&
                    isCurrentUser &&
                    message.type == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Edit'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onEdit(message);
                    },
                  ),
                if (imageAttachment != null)
                  ListTile(
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Preview'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(onPreviewImage(imageAttachment));
                    },
                  ),
                if (canPin)
                  ListTile(
                    leading: Icon(
                      message.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(message.isPinned ? 'Unpin' : 'Pin'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(onTogglePin(message));
                    },
                  ),
                if (canCompose && isCurrentUser && _hasVisiblePreview(context))
                  ListTile(
                    leading: const Icon(Icons.link_off),
                    title: const Text('Remove embed'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(onRemoveEmbed(message));
                    },
                  ),
                if (message.type == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: const Text('Copy'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        Clipboard.setData(ClipboardData(text: message.body)),
                      );
                    },
                  ),
                if (isCurrentUser)
                  ListTile(
                    iconColor: colorScheme.error,
                    textColor: colorScheme.error,
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Delete'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(onDelete(message));
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SystemMessageLine extends StatelessWidget {
  const _SystemMessageLine({
    required this.message,
    required this.onOpenPinnedMessage,
  });

  final ChatMessage message;
  final Future<void> Function(String messageId) onOpenPinnedMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pinnedMessageId = message.pinnedMessageId;
    final text = Text(
      message.body,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: pinnedMessageId == null
            ? text
            : InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => unawaited(onOpenPinnedMessage(pinnedMessageId)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.push_pin_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(child: text),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.message,
    required this.messagesById,
    required this.imageAttachment,
    required this.voiceAttachment,
    required this.textColor,
    required this.isRecalled,
    this.pollActions,
  });

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final ImageAttachment? imageAttachment;
  final VoiceAttachment? voiceAttachment;
  final Color textColor;
  final bool isRecalled;
  final PollActions? pollActions;

  @override
  Widget build(BuildContext context) {
    if (isRecalled) {
      return Text(
        'Message deleted',
        style: TextStyle(color: textColor, fontStyle: FontStyle.italic),
      );
    }

    final content = <Widget>[
      if (message.replyPreview != null) ...[
        _QuotedReplyPreview(
          senderName: message.replyPreview!.senderName,
          body: _displayBodyForReplyPreview(message.replyPreview!),
          foregroundColor: textColor,
        ),
        const SizedBox(height: 8),
      ],
      if (message.forwardPreview != null) ...[
        _ForwardedPreview(
          preview: message.forwardPreview!,
          foregroundColor: textColor,
        ),
        const SizedBox(height: 8),
      ],
    ];

    final attachment = imageAttachment;
    if (attachment != null) {
      content.add(_ImageMessageContent(attachment: attachment));
    } else if (voiceAttachment != null) {
      content.add(VoiceMessagePlayer(attachment: voiceAttachment!));
    } else if (message.type == MessageType.poll) {
      content.add(
        PollMessageContent(
          message: message,
          textColor: textColor,
          actions: pollActions,
        ),
      );
    } else {
      content.add(
        MessageMarkdownText(
          body: message.body,
          mentions: message.mentions,
          color: textColor,
        ),
      );
    }

    if (message.editedAt != null) {
      content.add(const SizedBox(height: 4));
      content.add(
        Text(
          'edited',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: textColor.withValues(alpha: 0.72),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: content,
    );
  }

  String _displayBodyForReplyPreview(ReplyPreview preview) {
    final referencedMessage = messagesById[preview.messageId];
    if (referencedMessage?.recalledAt != null) {
      return 'Message deleted';
    }
    return preview.type == MessageType.text
        ? plainTextFromMarkdown(preview.body)
        : preview.body;
  }
}

class _ForwardedPreview extends StatelessWidget {
  const _ForwardedPreview({
    required this.preview,
    required this.foregroundColor,
  });

  final ForwardPreview preview;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: foregroundColor.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Forwarded from ${preview.senderName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            _displayBodyForForwardPreview(preview),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: foregroundColor),
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
  });

  final String senderName;
  final String body;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: foregroundColor, width: 3)),
        color: foregroundColor.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: foregroundColor),
          ),
        ],
      ),
    );
  }
}

String _displayBodyForForwardPreview(ForwardPreview preview) {
  final body = preview.body.trim();
  return switch (preview.type) {
    MessageType.text => body.isEmpty ? 'Message' : plainTextFromMarkdown(body),
    MessageType.system => body.isEmpty ? 'Message' : body,
    MessageType.image => 'Image',
    MessageType.file => 'File',
    MessageType.voice => 'Voice message',
    MessageType.poll => pollPreviewText(body),
  };
}

class _ImageMessageContent extends ConsumerStatefulWidget {
  const _ImageMessageContent({required this.attachment});

  final ImageAttachment attachment;

  @override
  ConsumerState<_ImageMessageContent> createState() =>
      _ImageMessageContentState();
}

class _ImageMessageContentState extends ConsumerState<_ImageMessageContent> {
  late Future<String> _imageUrl;

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
    }
  }

  Future<String> _loadImageUrl() {
    return ref.read(chatsRepositoryProvider).createImageUrl(widget.attachment);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _imageUrl,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
          return const SizedBox(
            width: 220,
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showImagePreview(context, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              url,
              width: 220,
              height: 160,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox(
                  width: 220,
                  height: 160,
                  child: Icon(Icons.broken_image_outlined),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

void showImagePreview(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(title: const Text('Image preview')),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.broken_image_outlined, size: 48);
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.slowmodeSeconds,
    required this.slowmodeRemainingSeconds,
    required this.controller,
    required this.isSending,
    required this.isPickingImage,
    required this.isSendingImage,
    required this.errorText,
    required this.mentionCandidates,
    required this.onSelectMention,
    required this.slashCommands,
    required this.highlightedSlashIndex,
    required this.onSelectSlashCommand,
    required this.onComposerKey,
    required this.replyPreviewText,
    required this.isEditing,
    required this.onChanged,
    required this.onSend,
    required this.onPickImage,
    required this.onCreatePoll,
    required this.isRecordingVoice,
    required this.isSendingVoice,
    required this.onStartVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onSendVoiceRecording,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.availableHeight,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isPickingImage;
  final bool isSendingImage;
  final String? errorText;
  final List<GroupMember> mentionCandidates;
  final ValueChanged<GroupMember> onSelectMention;

  /// The commands offered while one is typed after a leading `/`.
  final List<SlashCommand> slashCommands;
  final int highlightedSlashIndex;
  final ValueChanged<SlashCommand> onSelectSlashCommand;

  /// Sees the text field's key presses first (arrow keys and Enter in the
  /// command list).
  final FocusOnKeyEventCallback onComposerKey;
  final String? replyPreviewText;
  final bool isEditing;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImage;
  final Future<void> Function() onCreatePoll;
  final bool isRecordingVoice;
  final bool isSendingVoice;
  final Future<void> Function() onStartVoiceRecording;
  final Future<void> Function() onCancelVoiceRecording;
  final Future<void> Function() onSendVoiceRecording;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;

  /// Height of the thread above the keyboard, app bar included.
  final double availableHeight;

  /// The channel's slowmode for the current user (0 when off) and how long
  /// they still wait before their next message.
  final int slowmodeSeconds;
  final int slowmodeRemainingSeconds;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBusy = isSending || isSendingImage || isSendingVoice;
    // Edits are not new messages, so slowmode leaves them alone.
    final isSlowed = slowmodeRemainingSeconds > 0 && !isEditing;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        // On short screens with the keyboard up, banners and suggestions
        // scroll above the text field instead of pushing the messages out.
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight * 0.5),
          child: SingleChildScrollView(
            reverse: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorText != null) ...[
                    Text(
                      errorText!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (replyPreviewText != null) ...[
                    _ComposerModeBanner(
                      text: 'Replying to $replyPreviewText',
                      tooltip: 'Cancel reply',
                      icon: Icons.close,
                      onPressed: onCancelReply,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (isEditing) ...[
                    _ComposerModeBanner(
                      text: 'Editing message',
                      tooltip: 'Cancel edit',
                      icon: Icons.close,
                      onPressed: onCancelEdit,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (slowmodeSeconds > 0) ...[
                    _SlowmodeBanner(remainingSeconds: slowmodeRemainingSeconds),
                    const SizedBox(height: 8),
                  ],
                  if (slashCommands.isNotEmpty) ...[
                    SlashCommandList(
                      commands: slashCommands,
                      highlightedIndex: highlightedSlashIndex,
                      onSelect: onSelectSlashCommand,
                      maxHeight: math.min(240, availableHeight * 0.3),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (mentionCandidates.isNotEmpty) ...[
                    MentionCandidateList(
                      candidates: mentionCandidates,
                      onSelect: onSelectMention,
                      maxHeight: math.min(180, availableHeight * 0.25),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      if (isSendingImage)
                        const IconButton(
                          tooltip: 'Sending image',
                          onPressed: null,
                          icon: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        PopupMenuButton<_ComposerAttachment>(
                          key: const ValueKey('composer-attach-button'),
                          tooltip: 'Attach',
                          enabled:
                              !isBusy &&
                              !isEditing &&
                              !isRecordingVoice &&
                              !isSlowed,
                          icon: const Icon(Icons.add_circle_outline),
                          onSelected: (choice) => unawaited(switch (choice) {
                            _ComposerAttachment.image => onPickImage(),
                            _ComposerAttachment.poll => onCreatePoll(),
                          }),
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _ComposerAttachment.image,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.image_outlined),
                                title: Text('Send image'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _ComposerAttachment.poll,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.poll_outlined),
                                title: Text('Create poll'),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(width: 8),
                      if (isRecordingVoice)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons.mic,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('Recording...')),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: Focus(
                            canRequestFocus: false,
                            skipTraversal: true,
                            onKeyEvent: onComposerKey,
                            child: TextField(
                              key: const ValueKey('chat-composer-field'),
                              controller: controller,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: onChanged,
                              onSubmitted: (_) {
                                unawaited(onSend());
                              },
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      if (isRecordingVoice) ...[
                        IconButton(
                          tooltip: 'Cancel voice message',
                          onPressed: isSendingVoice
                              ? null
                              : () => unawaited(onCancelVoiceRecording()),
                          icon: const Icon(Icons.close),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Send voice message',
                          onPressed: isSendingVoice
                              ? null
                              : () => unawaited(onSendVoiceRecording()),
                          icon: isSendingVoice
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        ),
                      ] else ...[
                        IconButton(
                          tooltip: 'Record voice message',
                          onPressed: isBusy || isEditing || isSlowed
                              ? null
                              : () => unawaited(onStartVoiceRecording()),
                          icon: const Icon(Icons.mic_none_outlined),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: isEditing ? 'Save edit' : 'Send',
                          onPressed: isBusy || isSlowed
                              ? null
                              : () => unawaited(onSend()),
                          icon: isSending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ComposerAttachment { image, poll }

/// Rebuilds [builder] every second until [until], with the whole seconds
/// left (0 once it has passed or without [until]).
class _SlowmodeGate extends StatefulWidget {
  const _SlowmodeGate({required this.until, required this.builder});

  final DateTime? until;
  final Widget Function(BuildContext context, int remainingSeconds) builder;

  @override
  State<_SlowmodeGate> createState() => _SlowmodeGateState();
}

class _SlowmodeGateState extends State<_SlowmodeGate> {
  Timer? _ticker;

  int get _remainingSeconds {
    final until = widget.until;
    if (until == null) {
      return 0;
    }
    final left = until.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _SlowmodeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (_remainingSeconds == 0) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_remainingSeconds == 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _remainingSeconds);
  }
}

class _SlowmodeBanner extends StatelessWidget {
  const _SlowmodeBanner({required this.remainingSeconds});

  final int remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      key: const ValueKey('composer-slowmode'),
      children: [
        Icon(Icons.timer_outlined, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Slowmode is enabled',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        if (remainingSeconds > 0)
          Text(
            formatSlowmodeCountdown(remainingSeconds),
            key: const ValueKey('composer-slowmode-countdown'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// A slowmode wait as `45s`, `2:05` or `1:00:00`.
String formatSlowmodeCountdown(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$rest';
  }
  return '$minutes:$rest';
}

/// When the current user's slowmode wait ends: their latest message plus
/// [slowmodeSeconds], or the server's [retryAt] if later. Null when they
/// have not sent anything here.
DateTime? _slowmodeEnd({
  required List<ChatMessage> messages,
  required String? currentUserId,
  required int slowmodeSeconds,
  required DateTime? retryAt,
}) {
  DateTime? lastSentAt;
  for (final message in messages) {
    if (message.isSentBy(currentUserId) &&
        message.type != MessageType.system &&
        (lastSentAt == null || message.createdAt.isAfter(lastSentAt))) {
      lastSentAt = message.createdAt;
    }
  }
  final localEnd = lastSentAt?.add(Duration(seconds: slowmodeSeconds));
  if (retryAt == null) {
    return localEnd;
  }
  if (localEnd == null || retryAt.isAfter(localEnd)) {
    return retryAt;
  }
  return localEnd;
}

/// Takes the composer's place where the current user may not send.
class _ReadOnlyComposerNotice extends StatelessWidget {
  const _ReadOnlyComposerNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        key: const ValueKey('chat-read-only-notice'),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You don't have permission to send messages in this "
                  'channel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerModeBanner extends StatelessWidget {
  const _ComposerModeBanner({
    required this.text,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String text;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        IconButton(
          tooltip: tooltip,
          // Full size on touch screens, so it stays easy to hit.
          visualDensity: usesTouchInput(context) ? null : VisualDensity.compact,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ],
    );
  }
}

ReplyPreview _replyPreviewForMessage(ChatMessage message) {
  return ReplyPreview(
    messageId: message.id,
    senderName: 'Message',
    body: _replyPreviewBody(message),
    type: message.type,
  );
}

String _replyPreviewBody(ChatMessage message) {
  if (message.recalledAt != null) {
    return 'Message';
  }
  return switch (message.type) {
    MessageType.text =>
      message.body.trim().isEmpty
          ? 'Message'
          : plainTextFromMarkdown(message.body.trim()),
    MessageType.system =>
      message.body.trim().isEmpty ? 'Message' : message.body.trim(),
    MessageType.image => 'Image',
    MessageType.file => 'File',
    MessageType.voice => 'Voice message',
    MessageType.poll => pollPreviewText(message.body),
  };
}

String _imageSendErrorText(Object error) {
  if (error is ImagePickerException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'Could not upload image. The request timed out. Try a smaller image or check your network.';
  }
  return 'Could not send image. Try again. $error';
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}

_LatestOutgoingReadState _latestOutgoingReadState({
  required List<ChatMessage> messages,
  required List<ConversationReadMarker> readMarkers,
  required String? currentUserId,
}) {
  if (currentUserId == null) {
    return const _LatestOutgoingReadState();
  }

  ChatMessage? latestOutgoing;
  for (final message in messages) {
    if (message.isSentBy(currentUserId) && message.type != MessageType.system) {
      latestOutgoing = message;
    }
  }
  if (latestOutgoing == null) {
    return const _LatestOutgoingReadState();
  }

  final messagesById = {for (final message in messages) message.id: message};
  final isRead = readMarkers.any((marker) {
    if (marker.userId == currentUserId) {
      return false;
    }
    final readMessage = messagesById[marker.lastReadMessageId];
    return readMessage != null &&
        !readMessage.createdAt.isBefore(latestOutgoing!.createdAt);
  });

  return _LatestOutgoingReadState(
    latestOutgoingMessageId: latestOutgoing.id,
    isRead: isRead,
  );
}

/// The first message from someone else after the reader's last read message,
/// or null when everything was already read or the read position is unknown.
String? _firstUnreadMessageId({
  required List<ChatMessage> messages,
  required List<ConversationReadMarker> readMarkers,
  required String? currentUserId,
}) {
  if (currentUserId == null) {
    return null;
  }
  ConversationReadMarker? marker;
  for (final readMarker in readMarkers) {
    if (readMarker.userId == currentUserId) {
      marker = readMarker;
      break;
    }
  }
  if (marker == null) {
    return null;
  }
  final lastReadMessageId = marker.lastReadMessageId;
  var startIndex = 0;
  if (lastReadMessageId != null) {
    final lastReadIndex = messages.indexWhere(
      (message) => message.id == lastReadMessageId,
    );
    if (lastReadIndex == -1) {
      return null;
    }
    startIndex = lastReadIndex + 1;
  }
  for (final message in messages.skip(startIndex)) {
    if (!message.isSentBy(currentUserId)) {
      return message.id;
    }
  }
  return null;
}

List<ChatMessage> _messagesOldestToNewest(List<ChatMessage> messages) {
  return [...messages]..sort((left, right) {
    final createdCompare = left.createdAt.compareTo(right.createdAt);
    if (createdCompare != 0) {
      return createdCompare;
    }
    return left.id.compareTo(right.id);
  });
}

class _LatestOutgoingReadState {
  const _LatestOutgoingReadState({
    this.latestOutgoingMessageId,
    this.isRead = false,
  });

  final String? latestOutgoingMessageId;
  final bool isRead;
}
