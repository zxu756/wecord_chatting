import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
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

class ChatThreadData {
  const ChatThreadData({required this.messages, required this.readMarkers});

  final List<ChatMessage> messages;
  final List<ConversationReadMarker> readMarkers;
}

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    required this.conversationId,
    this.title,
    this.avatarUrl,
    this.conversationType,
    super.key,
  });

  final String conversationId;
  final String? title;
  final String? avatarUrl;
  final ConversationType? conversationType;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _composerController = TextEditingController();
  Timer? _typingTimer;
  ChatsRepository? _typingRepository;
  var _isSending = false;
  var _isPickingImage = false;
  var _isSendingImage = false;
  var _isTypingShared = false;
  String? _sendError;
  String? _lastMarkedMessageId;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_isTypingShared) {
      unawaited(
        _typingRepository
            ?.setTyping(conversationId: widget.conversationId, isTyping: false)
            .catchError((Object _) {}),
      );
    }
    _composerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
    final activity = ref.watch(chatActivityProvider(widget.conversationId));
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id;
    final title = widget.title?.trim().isNotEmpty == true
        ? widget.title!.trim()
        : 'Conversation';
    final currentActivity =
        activity.valueOrNull ?? const ConversationActivity();
    final peerIsOnline = currentActivity.onlineUserIds.any((id) {
      return id != currentUserId;
    });
    final peerIsTyping = currentActivity.typingUserIds.any((id) {
      return id != currentUserId;
    });

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _ThreadAvatar(title: title, avatarUrl: widget.avatarUrl),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            Text(
              peerIsOnline ? 'Online' : 'Offline',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (widget.conversationType == ConversationType.group)
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
        ],
      ),
      body: Column(
        children: [
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
                final messagesById = {
                  for (final message in messages) message.id: message,
                };
                _markReadAfterLoad(messages);
                _reconcileActiveMessageState(messagesById);
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet'));
                }

                final oldestToNewest = _messagesOldestToNewest(messages);
                final newestFirst = oldestToNewest.reversed.toList(
                  growable: false,
                );
                final latestOutgoingReadState = _latestOutgoingReadState(
                  messages: oldestToNewest,
                  readMarkers: data.readMarkers,
                  currentUserId: currentUserId,
                );

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: newestFirst.length,
                  itemBuilder: (context, index) {
                    final message = newestFirst[index];
                    return _MessageBubble(
                      message: message,
                      messagesById: messagesById,
                      isCurrentUser: message.senderId == currentUserId,
                      showReadReceipt:
                          latestOutgoingReadState.latestOutgoingMessageId ==
                              message.id &&
                          latestOutgoingReadState.isRead,
                      onReply: _startReply,
                      onEdit: _startEdit,
                      onDelete: _deleteMessage,
                      onPreviewImage: _previewImage,
                    );
                  },
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
            replyPreviewText: _replyingTo == null
                ? null
                : _replyPreviewBody(_replyingTo!),
            isEditing: _editingMessage != null,
            onChanged: _handleComposerChanged,
            onSend: _sendMessage,
            onPickImage: _pickAndSendImage,
            onCancelReply: _cancelReply,
            onCancelEdit: _cancelEdit,
          ),
        ],
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
          );
      await _setTyping(false);
      _composerController.clear();
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

  void _handleComposerChanged(String value) {
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

class _ThreadAvatar extends ConsumerWidget {
  const _ThreadAvatar({required this.title, required this.avatarUrl});

  final String title;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref.watch(avatarDisplayUrlProvider(avatarUrl));
    final image = displayUrl.valueOrNull == null
        ? null
        : NetworkImage(displayUrl.valueOrNull!);
    return CircleAvatar(
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
    required this.onEdit,
    required this.onDelete,
    required this.onPreviewImage,
  });

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final bool isCurrentUser;
  final bool showReadReceipt;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final Future<void> Function(ChatMessage message) onDelete;
  final Future<void> Function(ImageAttachment attachment) onPreviewImage;

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
    final canShowActions = !isRecalled;

    return Column(
      crossAxisAlignment: isCurrentUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
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
                margin: EdgeInsets.only(bottom: showReadReceipt ? 4 : 8),
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
                  textColor: textColor,
                  isRecalled: isRecalled,
                ),
              ),
            ),
          ),
        ),
        if (showReadReceipt)
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 8),
            child: Text(
              'Read',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  void _showActions(BuildContext context, ImageAttachment? imageAttachment) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onReply(message);
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
        );
      },
    );
  }
}

class _MessageContent extends StatelessWidget {
  const _MessageContent({
    required this.message,
    required this.messagesById,
    required this.imageAttachment,
    required this.textColor,
    required this.isRecalled,
  });

  final ChatMessage message;
  final Map<String, ChatMessage> messagesById;
  final ImageAttachment? imageAttachment;
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
    ];

    final attachment = imageAttachment;
    if (attachment != null) {
      content.add(_ImageMessageContent(attachment: attachment));
    } else {
      content.add(Text(message.body, style: TextStyle(color: textColor)));
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
    return preview.body;
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
    required this.replyPreviewText,
    required this.isEditing,
    required this.onChanged,
    required this.onSend,
    required this.onPickImage,
    required this.onCancelReply,
    required this.onCancelEdit,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isPickingImage;
  final bool isSendingImage;
  final String? errorText;
  final String? replyPreviewText;
  final bool isEditing;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImage;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isBusy = isSending || isSendingImage;

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
              Row(
                children: [
                  IconButton(
                    tooltip: 'Send image',
                    onPressed: isBusy || isEditing
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
    if (message.senderId == currentUserId) {
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
