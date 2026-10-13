import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/chats/message_forward_sheet.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';

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

class _MentionSelection {
  const _MentionSelection({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  final String userId;
  final String username;
  final String displayName;
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
    super.key,
  });

  final String conversationId;
  final String? title;
  final String? avatarUrl;
  final ConversationType? conversationType;
  final List<Widget> extraActions;

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
  final _mentionSelections = <String, _MentionSelection>{};
  var _hasCapturedReadPosition = false;
  String? _newMessageDividerId;
  var _isAtBottom = true;
  String? _latestMessageId;
  String? _latestSeenMessageId;
  var _unseenMessageCount = 0;
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

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
      _messageKeys.clear();
      _highlightTimer?.cancel();
      _highlightedMessageId = null;
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
    // Group and channel members feed sender names and @mention candidates.
    final groupDetail =
        conversationType == ConversationType.group ||
            conversationType == ConversationType.channel
        ? ref.watch(groupDetailProvider(widget.conversationId)).valueOrNull
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

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _ThreadAvatar(title: title, avatarUrl: avatarUrl),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            Text(
              [
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
        actions: [
          IconButton(
            tooltip: 'Search messages',
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _isSearchingMessages = !_isSearchingMessages;
                if (!_isSearchingMessages) {
                  _searchController.clear();
                  _messageSearchQuery = '';
                }
              });
            },
          ),
          IconButton(
            tooltip: 'Pinned messages',
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: () => _showPinnedMessages(canPinMessages),
          ),
          IconButton(
            tooltip: 'Media',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () {
              context.push(ChatMediaScreen.pathFor(widget.conversationId));
            },
          ),
          if (conversationType == ConversationType.group)
            IconButton(
              tooltip: 'Group details',
              icon: const Icon(Icons.group_outlined),
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) {
                    return GroupDetailSheet(
                      conversationId: widget.conversationId,
                      title: title,
                    );
                  },
                );
              },
            ),
          ...widget.extraActions,
        ],
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                final newestFirst = visibleOldestToNewest.reversed.toList(
                  growable: false,
                );
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
                    : const <String>{};
                final showSenders =
                    conversationType == ConversationType.group ||
                    conversationType == ConversationType.channel;
                final membersById = {
                  for (final member
                      in groupDetail?.members ?? const <GroupMember>[])
                    member.profile.id: member,
                };

                final list = ListView.builder(
                  key: const ValueKey('chat-message-list'),
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: newestFirst.length,
                  itemBuilder: (context, index) {
                    final message = newestFirst[index];
                    final Widget bubble;
                    if (message.type == MessageType.system) {
                      bubble = _SystemMessageLine(
                        message: message,
                        onOpenPinnedMessage: _scrollToMessage,
                      );
                    } else {
                      final isCurrentUser = message.senderId == currentUserId;
                      final newerMessage = index == 0
                          ? null
                          : newestFirst[index - 1];
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
                      key: _messageKeys.putIfAbsent(message.id, GlobalKey.new),
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
                return Stack(
                  children: [
                    Positioned.fill(child: list),
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
          _Composer(
            controller: _composerController,
            isSending: _isSending,
            isPickingImage: _isPickingImage,
            isSendingImage: _isSendingImage,
            errorText: _sendError,
            mentionCandidates: _mentionCandidates(groupDetail),
            onSelectMention: _insertMention,
            replyPreviewText: _replyingTo == null
                ? null
                : _replyPreviewBody(_replyingTo!),
            isEditing: _editingMessage != null,
            onChanged: _handleComposerChanged,
            onSend: _sendMessage,
            onPickImage: _pickAndSendImage,
            isRecordingVoice: _isRecordingVoice,
            isSendingVoice: _isSendingVoice,
            onStartVoiceRecording: _startVoiceRecording,
            onCancelVoiceRecording: _cancelVoiceRecording,
            onSendVoiceRecording: _sendVoiceRecording,
            onCancelReply: _cancelReply,
            onCancelEdit: _cancelEdit,
          ),
        ],
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
    _latestMessageId = oldestToNewest.isEmpty ? null : oldestToNewest.last.id;
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
        .where((message) => message.senderId != currentUserId)
        .length;
  }

  void _handleScroll() {
    final isAtBottom =
        !_scrollController.hasClients ||
        _scrollController.position.pixels <= _bottomScrollThreshold;
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
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
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
            body: body,
            replyToMessageId: replyingTo?.id,
            replyPreview: replyPreview,
            mentions: _mentionsForBody(body),
          );
      await _setTyping(false);
      _composerController.clear();
      _mentionSelections.clear();
      _isMentioning = false;
      _mentionQuery = '';
      _replyingTo = null;
      ref.invalidate(chatThreadProvider(widget.conversationId));
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

  Future<void> _pickAndSendImage() async {
    if (_isPickingImage || _isSendingImage || _isSending) {
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

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice ||
        _isSendingVoice ||
        _isSending ||
        _editingMessage != null) {
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
    final selection = _composerController.selection;
    final cursor = selection.isValid
        ? selection.baseOffset
        : _composerController.text.length;
    final safeCursor = cursor.clamp(0, _composerController.text.length);
    final prefix = _composerController.text.substring(0, safeCursor);
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$').firstMatch(prefix);
    final isMentioning = match != null;
    final nextQuery = match?.group(1)?.toLowerCase() ?? '';
    if (_isMentioning == isMentioning && _mentionQuery == nextQuery) {
      return;
    }
    setState(() {
      _isMentioning = isMentioning;
      _mentionQuery = nextQuery;
    });
  }

  List<GroupMember> _mentionCandidates(GroupDetail? detail) {
    if (detail == null || !_isMentioning) {
      return const [];
    }
    final query = _mentionQuery;
    return detail.members
        .where((member) {
          return member.profile.username.toLowerCase().contains(query) ||
              _mentionName(member).toLowerCase().contains(query);
        })
        .take(6)
        .toList(growable: false);
  }

  void _insertMention(GroupMember member) {
    final text = _composerController.text;
    final selection = _composerController.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final safeCursor = cursor.clamp(0, text.length);
    final prefix = text.substring(0, safeCursor);
    final match = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$').firstMatch(prefix);
    if (match == null) {
      return;
    }
    final tokenStart = match.start + (prefix[match.start] == '@' ? 0 : 1);
    final mentionText = '@${member.profile.username} ';
    final nextText = text.replaceRange(tokenStart, safeCursor, mentionText);
    _composerController.text = nextText;
    _composerController.selection = TextSelection.collapsed(
      offset: tokenStart + mentionText.length,
    );
    _mentionSelections[member.profile.username] = _MentionSelection(
      userId: member.profile.id,
      username: member.profile.username,
      displayName: _mentionName(member),
    );
    setState(() {
      _isMentioning = false;
      _mentionQuery = '';
    });
  }

  List<MessageMention> _mentionsForBody(String body) {
    final mentions = <MessageMention>[];
    for (final selection in _mentionSelections.values) {
      final token = '@${selection.username}';
      var start = body.indexOf(token);
      while (start != -1) {
        mentions.add(
          MessageMention(
            userId: selection.userId,
            displayName: selection.displayName,
            start: start,
            end: start + token.length,
          ),
        );
        start = body.indexOf(token, start + token.length);
      }
    }
    mentions.sort((a, b) => a.start.compareTo(b.start));
    return mentions;
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
        message.senderId != previous.senderId ||
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
  );
}

class _MessageSender {
  const _MessageSender({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;
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
  });

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final bool isCurrentUser;
  final bool showReadReceipt;

  /// Who sent an incoming message in a group or channel; null hides the
  /// avatar column entirely (own messages, direct chats).
  final _MessageSender? sender;

  /// Continues the previous message's group, so the avatar and name are
  /// left out.
  final bool isFollowUp;

  /// The next message continues this one's group, so the gap below shrinks.
  final bool hasFollowUp;
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

  /// The link whose preview card shows under this message, if any.
  String? get _previewUrl {
    if (message.recalledAt != null ||
        message.type != MessageType.text ||
        message.suppressEmbeds) {
      return null;
    }
    return firstLinkInMarkdown(message.body, mentions: message.mentions);
  }

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              sender.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
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
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onReply(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.forward_outlined),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onForward(message);
                  },
                ),
                if (isCurrentUser && message.type == MessageType.text)
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
                if (isCurrentUser && _hasVisiblePreview(context))
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
  });

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final ImageAttachment? imageAttachment;
  final VoiceAttachment? voiceAttachment;
  final Color textColor;
  final bool isRecalled;

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
    required this.controller,
    required this.isSending,
    required this.isPickingImage,
    required this.isSendingImage,
    required this.errorText,
    required this.mentionCandidates,
    required this.onSelectMention,
    required this.replyPreviewText,
    required this.isEditing,
    required this.onChanged,
    required this.onSend,
    required this.onPickImage,
    required this.isRecordingVoice,
    required this.isSendingVoice,
    required this.onStartVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onSendVoiceRecording,
    required this.onCancelReply,
    required this.onCancelEdit,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isPickingImage;
  final bool isSendingImage;
  final String? errorText;
  final List<GroupMember> mentionCandidates;
  final ValueChanged<GroupMember> onSelectMention;
  final String? replyPreviewText;
  final bool isEditing;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImage;
  final bool isRecordingVoice;
  final bool isSendingVoice;
  final Future<void> Function() onStartVoiceRecording;
  final Future<void> Function() onCancelVoiceRecording;
  final Future<void> Function() onSendVoiceRecording;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBusy = isSending || isSendingImage || isSendingVoice;

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorText != null) ...[
                Text(errorText!, style: TextStyle(color: colorScheme.error)),
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
              if (mentionCandidates.isNotEmpty) ...[
                Material(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final member in mentionCandidates)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              child: Text(_initials(_mentionName(member))),
                            ),
                            title: Text(_mentionName(member)),
                            subtitle: Text('@${member.profile.username}'),
                            onTap: () => onSelectMention(member),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  IconButton(
                    tooltip: 'Send image',
                    onPressed: isBusy || isEditing || isRecordingVoice
                        ? null
                        : () => unawaited(onPickImage()),
                    icon: isSendingImage
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_outlined),
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
                      child: TextField(
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ] else ...[
                    IconButton(
                      tooltip: 'Record voice message',
                      onPressed: isBusy || isEditing
                          ? null
                          : () => unawaited(onStartVoiceRecording()),
                      icon: const Icon(Icons.mic_none_outlined),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: isEditing ? 'Save edit' : 'Send',
                      onPressed: isBusy ? null : () => unawaited(onSend()),
                      icon: isSending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
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
          visualDensity: VisualDensity.compact,
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

/// A mention candidate's name: their circle nickname in channels, otherwise
/// their display name.
String _mentionName(GroupMember member) {
  final nickname = member.nickname?.trim();
  return nickname == null || nickname.isEmpty
      ? member.profile.displayName
      : nickname;
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
    if (message.senderId == currentUserId &&
        message.type != MessageType.system) {
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
    if (message.senderId != currentUserId) {
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
