import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/ai/ai_catch_up.dart';
import 'package:wecord/features/ai/ai_composer_button.dart';
import 'package:wecord/features/ai/ai_rewrite_sheet.dart';
import 'package:wecord/features/ai/ai_translation.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/swipe_to_reply.dart';
import 'package:wecord/features/chats/automod_alert_card.dart';
import 'package:wecord/features/chats/chat_profile_panel.dart';
import 'package:wecord/features/chats/chat_thread_header.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/composer_shortcuts.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/file_message.dart';
import 'package:wecord/features/chats/global_message_search_screen.dart';
import 'package:wecord/features/chats/gif_search.dart';
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/chats/mention_picker.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/chats/message_forward_sheet.dart';
import 'package:wecord/features/chats/message_list_view.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/chats/message_semantics.dart';
import 'package:wecord/features/chats/offline/connectivity_banner.dart';
import 'package:wecord/features/chats/media_send/album_fold.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/media_send/chat_drop_zone.dart';
import 'package:wecord/features/chats/media_send/clipboard_files.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_prepare.dart';
import 'package:wecord/features/chats/media_send/media_tray.dart';
import 'package:wecord/features/chats/media_send/send_failure.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/chats/offline/outbox_provider.dart';
import 'package:wecord/features/chats/pending_message.dart';
import 'package:wecord/features/chats/pinned_messages_sheet.dart';
import 'package:wecord/features/chats/poll_composer_sheet.dart';
import 'package:wecord/features/chats/poll_message.dart';
import 'package:wecord/features/chats/role_mentions.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/circles/announcement_repository.dart';
import 'package:wecord/features/circles/announcement_widgets.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_bot_widgets.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/voice/direct_call_view.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/file_preview/file_preview_scope.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/layout/panel_layout.dart';
import 'package:wecord/shared/layout/resizable_panels.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

export 'package:wecord/features/chats/chat_thread_controller.dart'
    show ChatThreadData, chatThreadProvider;

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

/// Whether the current user may delete others' messages in a conversation.
final canModerateMessagesProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .canModerateMessages(conversationId);
    });

final chatConversationSummaryProvider = FutureProvider.autoDispose
    .family<ConversationSummary?, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .getConversationSummary(conversationId);
    });

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

/// A group's announcement, as a soft card under the header.
class _AnnouncementStrip extends StatelessWidget {
  const _AnnouncementStrip({required this.announcement});

  final String announcement;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: double.infinity,
      margin: chatUsesDesktopChrome(context)
          ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
          : EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.campaign_outlined, size: 18, color: c.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              announcement,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The search field that opens under the header (phones and narrow panes).
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.onOpenFullSearch,
    this.resultLabel,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  /// Opens message search (filters, other scopes) for this conversation.
  final VoidCallback? onOpenFullSearch;
  final String? resultLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final desktop = chatUsesDesktopChrome(context);
    final field = Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        color: desktop ? c.raised : context.tokens.glass.solidFill,
        borderRadius: BorderRadius.circular(22),
        border: desktop ? null : Border.all(color: c.lineSoft),
        boxShadow: desktop ? null : context.tokens.shadows.hairline,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: c.subtle),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              textInputAction: onOpenFullSearch == null
                  ? null
                  : TextInputAction.search,
              onSubmitted: onOpenFullSearch == null
                  ? null
                  : (_) => onOpenFullSearch!(),
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: tr('Search messages'),
                hintStyle: TextStyle(fontSize: 15, color: c.subtle),
              ),
            ),
          ),
          if (resultLabel case final label?)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
          if (onOpenFullSearch case final open?)
            WeCordIconButton(
              key: const ValueKey('chat-search-open-full'),
              tooltip: tr('Search with filters'),
              icon: Icons.manage_search_rounded,
              size: 32,
              iconSize: 19,
              variant: WeCordButtonVariant.ghost,
              onPressed: open,
            ),
          WeCordIconButton(
            tooltip: tr('Close search'),
            icon: Icons.close_rounded,
            size: 32,
            iconSize: 18,
            variant: WeCordButtonVariant.ghost,
            onPressed: onClose,
          ),
        ],
      ),
    );
    return desktop
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: field,
          )
        : field;
  }
}

/// "3 new messages" floating over the bottom of the list.
class _JumpPill extends StatelessWidget {
  const _JumpPill({
    required this.tooltip,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: label,
      builder: (context, states) => WeCordGlass(
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward_rounded, size: 17, color: c.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ],
        ),
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
    this.timedOutUntil,
    this.slowmodeSeconds,
    this.topic,
    this.forumPost = false,
    this.onBack,
    this.isAnnouncementChannel = false,
    super.key,
  });

  final String conversationId;

  /// An announcement channel: its messages can be published to the
  /// channels following it.
  final bool isAnnouncementChannel;
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

  /// When the current user's circle timeout ends; the read-only notice
  /// says so instead of blaming permissions.
  final DateTime? timedOutUntil;

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
  final _catchUpController = AiCatchUpController();

  /// Focus of the message box; the jump-to-message-box shortcut uses it.
  final _composerFocus = FocusNode(debugLabel: 'message box');
  final _scrollController = ScrollController();
  Timer? _typingTimer;
  ChatsRepository? _typingRepository;
  VoiceMessageRecorder? _voiceMessageRecorder;
  late final StateController<String?> _activeConversationController;
  var _isSending = false;
  var _isPickingImage = false;
  StreamSubscription<List<XFile>>? _pasteSubscription;
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

  /// `@here` and the roles the current user may mention here, and who
  /// `@here` reaches (members online now), refreshed on every build.
  var _mentionTargets = const MentionTargets();
  List<String>? _hereUserIds;

  /// The custom emoji name typed after a `:`, while suggestions show.
  String? _emojiQuery;
  final _emojiDraft = CustomEmojiDraft();

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
  final _messageIdsByKey = <Key, String>{};

  /// The list items built last, by message, with what they were built
  /// from (see the list's item builder).
  final _itemCache = <String, (Object, Widget)>{};

  /// The message the list is built around (see [MessageListView]); null
  /// for the default (the newest in chats, the first in forum posts).
  String? _anchorId;

  /// Whether a chat keeps its newest message in view as messages arrive
  /// (the reader is at the bottom of the conversation's latest messages).
  var _following = true;

  /// The reader's read position when the chat opened, until the message
  /// it points at is loaded and the NEW divider placed.
  ConversationReadMarker? _initialReadMarker;
  var _dividerPending = false;
  var _forumStartRequested = false;
  ChatThreadData? _threadData;
  _ThreadLayout? _layout;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  var _isJumpScheduled = false;

  /// When the server last refused a message for slowmode, the time it said
  /// the next one is allowed.
  DateTime? _slowmodeRetryAt;

  /// The end of the current slowmode wait, refreshed on every build.
  DateTime? _slowmodeUntil;

  /// A restored draft's reply, picked up once the messages load.
  String? _pendingDraftReplyId;

  /// Measured heights of the floating header (phones) and composer, which
  /// the message list keeps clear of.
  double? _topInset;
  double? _bottomInset;

  /// The desktop profile panel was opened while there wasn't room for it.
  var _profileForced = false;

  @override
  void initState() {
    super.initState();
    ComposerFocusRegistry.attach(_composerFocus);
    _scrollController.addListener(_handleScroll);
    _activeConversationController = ref.read(
      activeConversationIdProvider.notifier,
    );
    _scheduleActiveConversationUpdate(widget.conversationId);
    unawaited(_restoreDraft());
    // Browsers hand pasted pictures and files over as events; macOS asks the
    // pasteboard when the text field is pasted into (see _pasteFilesAction).
    final clipboard = ref.read(clipboardFilesProvider);
    if (kIsWeb && clipboard.isSupported) {
      _pasteSubscription = clipboard.pasted.listen(_handlePastedFiles);
    }
  }

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

  @override
  void didUpdateWidget(covariant ChatThreadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _scheduleActiveConversationUpdate(widget.conversationId);
      // Each conversation keeps its own draft (saved as it was typed).
      _composerController.clear();
      _mentionDraft.clear();
      _emojiDraft.clear();
      _replyingTo = null;
      _editingMessage = null;
      _pendingDraftReplyId = null;
      _isMentioning = false;
      _mentionQuery = '';
      _emojiQuery = null;
      _slashQuery = null;
      _sendError = null;
      unawaited(_restoreDraft());
      _hasCapturedReadPosition = false;
      _newMessageDividerId = null;
      _isAtBottom = true;
      _latestMessageId = null;
      _latestSeenMessageId = null;
      _unseenMessageCount = 0;
      _newRepliesDismissed = false;
      _messageKeys.clear();
      _messageIdsByKey.clear();
      _itemCache.clear();
      _anchorId = null;
      _following = true;
      _initialReadMarker = null;
      _dividerPending = false;
      _forumStartRequested = false;
      _threadData = null;
      _layout = null;
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
    ComposerFocusRegistry.detach(_composerFocus);
    _composerFocus.dispose();
    unawaited(_pasteSubscription?.cancel());
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
    _catchUpController.dispose();
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
            child: Text(tr('Close')),
          ),
        ],
      ),
    );
  }

  void _showGroupDetails(String title) {
    showWeCordSheet<void>(
      context,
      detents: GroupDetailSheet.detents,
      initialDetent: GroupDetailSheet.initialDetent,
      builder: (context, scrollController) {
        return GroupDetailSheet(
          conversationId: widget.conversationId,
          title: title,
          scrollController: scrollController,
        );
      },
    );
  }

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

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingMessageJumpProvider, (_, jump) {
      if (jump != null &&
          ref.read(chatThreadProvider(widget.conversationId)).hasValue) {
        _schedulePendingJump();
      }
    });
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
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
    _voiceMessageRecorder = ref.watch(voiceMessageRecorderProvider);
    final conversationSummary = ref
        .watch(chatConversationSummaryProvider(widget.conversationId))
        .value;
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id;
    final title = widget.title?.trim().isNotEmpty == true
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
        (ref.watch(canManageThreadProvider(threadId)).value ?? false);
    final threadArchived = conversationSummary?.threadArchivedAt != null;
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
        ? _slowmodeEnd(
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
              _directPeerId(thread.value?.readMarkers, currentUserId)
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
      canEnd: (message) =>
          canSend &&
          (canModeratePolls ||
              (currentUserId != null && message.senderId == currentUserId)),
    );

    final searchAction = ChatThreadAction(
      tooltip: tr('Search messages'),
      icon: Icons.search,
      onPressed: _toggleMessageSearch,
    );
    final pinnedAction = ChatThreadAction(
      tooltip: tr('Pinned messages'),
      icon: Icons.push_pin_outlined,
      onPressed: () => _showPinnedMessages(canPinMessages),
    );
    final canCall =
        conversationType == ConversationType.direct ||
        conversationType == ConversationType.group;
    final callAction = canCall
        ? ChatThreadAction(
            tooltip: tr('Start voice call'),
            icon: Icons.call_outlined,
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
            onPressed: () => startDirectCall(
              context,
              ref,
              conversationId: widget.conversationId,
              name: title,
              video: true,
            ),
          )
        : null;
    final groupDetailsAction = conversationType == ConversationType.group
        ? ChatThreadAction(
            tooltip: tr('Group details'),
            icon: Icons.group_outlined,
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
            onPressed: () => _setThreadArchived(threadId, !threadArchived),
          )
        : null;
    final summarizeAction = ref.watch(aiAvailableProvider(circleId))
        ? ChatThreadAction(
            tooltip: tr('Summarize'),
            icon: Icons.auto_awesome_outlined,
            onPressed: _catchUpController.requestSummary,
          )
        : null;
    // Search comes first: phones keep it next to the primary action.
    final appBarActions = [
      searchAction,
      ?callAction,
      ?videoCallAction,
      pinnedAction,
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

    // Measured here rather than from the screen, so a thread panel in the
    // wide circle layout also gets the compact header.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = isCompactWidth(constraints.maxWidth);
        // Desktop puts the search field in the header when there is room.
        final inlineSearch = desktop && constraints.maxWidth >= 760;
        // Direct chats on desktop can show the other person's profile, in
        // a resizable panel that closes first when the window gets narrow.
        final profileUserId =
            desktop && conversationType == ConversationType.direct
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
        final profileAction = profileUserId == null
            ? null
            : ChatThreadAction(
                tooltip: showProfile ? tr('Hide profile') : tr('Show profile'),
                icon: Icons.view_sidebar_outlined,
                selectedIcon: Icons.view_sidebar_rounded,
                isSelected: showProfile,
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
          ?profileAction,
        ];
        // Small phones keep more of the name.
        final headerAvatarSize = desktop
            ? 34.0
            : constraints.maxWidth < 380
            ? 34.0
            : 40.0;
        final headerAvatar = isThread
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
        final subtitle = topic != null
            ? Text(
                topic,
                key: const ValueKey('chat-thread-subtitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Text(
                isThread
                    ? _threadSubtitle(conversationSummary)
                    : [
                        peerPresence?.label ??
                            (peerIsOnline ? tr('Online') : tr('Offline')),
                        if (conversationType == ConversationType.direct)
                          ?activeCustomStatus(
                            conversationSummary?.directCustomStatus,
                          )?.label,
                      ].join(' · '),
                key: const ValueKey('chat-thread-subtitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
        final searchResultCount = _messageSearchQuery.trim().isEmpty
            ? null
            : thread.value == null
            ? null
            : ref
                  .read(chatsRepositoryProvider)
                  .searchThreadMessages(
                    thread.value!.messages,
                    _messageSearchQuery,
                  )
                  .length;
        final resultLabel = searchResultCount == null
            ? null
            : searchResultCount == 1
            ? tr('1 result')
            : tr('{count} results', {'count': searchResultCount});
        final header = ChatThreadHeader(
          desktop: desktop,
          compact: compact,
          onBack: widget.onBack,
          avatar: headerAvatar,
          channelIcon: desktop && isChannel ? Icons.tag_rounded : null,
          title: title,
          subtitle: subtitle,
          onSubtitleTap: topic == null ? null : () => _showTopic(title, topic),
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
        final topInset = desktop
            ? 0.0
            : _topInset ?? MediaQuery.paddingOf(context).top + 64;
        final bottomInset = _bottomInset ?? 76 + composerBottomGap;

        final messagesArea = thread.when(
          loading: () => Center(
            child: CircularProgressIndicator(strokeWidth: 2.5, color: c.muted),
          ),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.toString(),
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
              for (final member
                  in groupDetail?.members ?? const <GroupMember>[])
                member.profile.id: member,
            };
            _announceIncoming(
              fullOldestToNewest,
              currentUserId,
              detached: data.hasNewer,
              nameOf: (message) => _senderFor(
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
                  senderName: _senderFor(
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
                  sender: _senderFor(message, membersById),
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
                  sender: _senderFor(
                    message,
                    membersById,
                    fallbackProfile: isCurrentUser ? ownProfile : null,
                  ),
                  // Direct chats name the other person in the title.
                  showSenderName: showSenders && !isCurrentUser,
                  isFollowUp: followUpIds.contains(message.id),
                  hasFollowUp:
                      newerMessage != null &&
                      followUpIds.contains(newerMessage.id),
                  showReadReceipt:
                      pendingEntry == null &&
                      _endsWith(
                        message,
                        latestOutgoingReadState.latestOutgoingMessageId,
                      ) &&
                      latestOutgoingReadState.isRead,
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
              final highlighted = AnimatedContainer(
                duration: WeCordMotion.durationOf(
                  context,
                  const Duration(milliseconds: 300),
                ),
                decoration: BoxDecoration(
                  color: message.id == _highlightedMessageId
                      ? c.accent.withValues(alpha: 0.12)
                      : c.accent.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(
                    cards ? 0 : WeCordRadii.md,
                  ),
                ),
                child: framed,
              );
              final showDay =
                  dayStartIds.contains(message.id) &&
                  message.id != openingPostId;
              final showNew = message.id == _newMessageDividerId;
              return KeyedSubtree(
                key: _keyForMessage(message.id),
                child: showDay || showNew
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDay)
                            ChatDaySeparator(time: message.createdAt),
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
                  : _senderFor(
                      message,
                      membersById,
                      fallbackProfile: message.isSentBy(currentUserId)
                          ? ownProfile
                          : null,
                    );
              final newer = index + 1 < display.length
                  ? display[index + 1]
                  : null;
              final signature = (
                message,
                messagesById[message.replyToMessageId],
                pendingEntry,
                followUpIds.contains(message.id),
                newer != null && followUpIds.contains(newer.id),
                _endsWith(
                      message,
                      latestOutgoingReadState.latestOutgoingMessageId,
                    ) &&
                    latestOutgoingReadState.isRead,
                (sender?.name, sender?.avatarUrl, sender?.roleColor),
                (desktop, cards, showSenders, canSend, canStartThreads, touch),
                (
                  canPinMessages,
                  canModeratePolls,
                  canDeleteAsModerator(message),
                  canPublish(message),
                ),
                _circleId,
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

        final composerArea = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (typingIds.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(desktop ? 34 : 22, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChatTypingIndicator(name: typingName),
                ),
              ),
            if (!canSend)
              _ReadOnlyComposerNotice(
                timedOutUntil: widget.timedOutUntil,
                desktop: desktop,
                bottomGap: composerBottomGap,
              )
            else
              _SlowmodeGate(
                until: _slowmodeUntil,
                builder: (context, slowmodeRemaining) => Actions(
                  actions: {
                    if (!kIsWeb && ref.read(clipboardFilesProvider).isSupported)
                      PasteTextIntent: _pasteFilesAction,
                  },
                  child: _Composer(
                    focusNode: _composerFocus,
                    desktop: desktop,
                    bottomGap: composerBottomGap,
                    hint: composerHint(conversationType, title),
                    slowmodeSeconds: slowmodeSeconds,
                    slowmodeRemainingSeconds: slowmodeRemaining,
                    controller: _composerController,
                    isSending: _isSending,
                    isPickingImage: _isPickingImage,
                    errorText: _sendError,
                    mentionCandidates: _mentionCandidates(groupDetail),
                    onSelectMention: _insertMention,
                    specialMentionCandidates: _specialMentionCandidates(),
                    onSelectSpecialMention: _insertSpecialMention,
                    emojiCandidates: _emojiCandidates(),
                    onSelectEmoji: _insertCustomEmoji,
                    slashCommands: _slashCandidates(),
                    botSlashCommands: _botSlashCandidates(),
                    highlightedSlashIndex: _slashIndex,
                    onSelectSlashCommand: _selectSlashCommand,
                    onSelectBotSlashCommand: _selectBotSlashCommand,
                    onComposerKey: _handleComposerKey,
                    replyPreviewText: _replyingTo == null
                        ? null
                        : _replyPreviewBody(_replyingTo!, localized: true),
                    isEditing: _editingMessage != null,
                    onChanged: _handleComposerChanged,
                    onSend: _sendMessage,
                    onPickImage: _pickPhotosAndVideos,
                    onPickFile: _pickFilesForTray,
                    aiButton: AiComposerButton(
                      circleId: circleId,
                      size: desktop ? 36 : 40,
                      onPressed: _isSending || _isSendingVoice
                          ? null
                          : _openAiRewrite,
                    ),
                    attachmentTray: MediaTray(
                      conversationId: widget.conversationId,
                      desktop: desktop,
                      sendEnabled: slowmodeRemaining <= 0,
                      onSend: _sendTray,
                      onAddMore: _showAddMoreMenu,
                    ),
                    onCreatePoll: _openPollComposer,
                    onPickSticker: _pickAndSendSticker,
                    onPickGif: _pickAndSendGif,
                    onInsertEmoji: _pickAndInsertEmoji,
                    gifAvailable:
                        ref.watch(gifSearchAvailableProvider) != false,
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
              ),
          ],
        );
        final floatingComposer = MeasureSize(
          onChange: (size) {
            if (mounted && size.height != _bottomInset) {
              setState(() => _bottomInset = size.height);
            }
          },
          // Lists in the suggestions popover would otherwise pad for the
          // status bar.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: composerArea,
          ),
        );

        // Files dropped anywhere on the chat go to the tray (macOS and the
        // web), unless the reader cannot send here or something sits over
        // the chat.
        Widget dropZone(Widget child) => ChatDropZone(
          enabled: canSend && ModalRoute.of(context)?.isCurrent != false,
          onFiles: (files) => unawaited(_addToTray(files)),
          child: child,
        );

        if (desktop) {
          final chatColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              ...banners,
              catchUpBanner,
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: messagesArea),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: floatingComposer,
                    ),
                  ],
                ),
              ),
            ],
          );
          return Scaffold(
            backgroundColor: c.panel,
            body: profileUserId == null
                ? dropZone(chatColumn)
                : ResizableSidePanelRow(
                    panel: ResizablePanel.profile,
                    placement: profilePlacement,
                    content: dropZone(chatColumn),
                    side: ChatProfilePanel(
                      userId: profileUserId,
                      name: title,
                      avatarUrl: avatarUrl,
                      presence: presenceColor,
                    ),
                  ),
          );
        }
        return dropZone(
          Scaffold(
            backgroundColor: c.panel,
            body: AnnotatedRegion<SystemUiOverlayStyle>(
              value: tokens.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: Stack(
                children: [
                  Positioned.fill(child: messagesArea),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: MeasureSize(
                      onChange: (size) {
                        if (mounted && size.height != _topInset) {
                          setState(() => _topInset = size.height);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          for (final banner in banners)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                              child: banner,
                            ),
                          catchUpBanner,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: floatingComposer,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    _newMessageDividerId = _firstUnreadMessageId(
      messages: oldestToNewest,
      readMarkers: [marker],
      currentUserId: currentUserId,
    );
  }

  /// The layout of the loaded messages: sorted, searched, grouped. Worked
  /// out again only when they (or the search, the NEW divider or the
  /// outbox) change, not on every build.
  _ThreadLayout _layoutFor(
    ChatThreadData data, {
    required List<OutboxEntry> pending,
    required String? currentUserId,
  }) {
    _threadData = data;
    final previous = _layout;
    if (previous != null &&
        identical(previous.messages, data.messages) &&
        identical(previous.readMarkers, data.readMarkers) &&
        identical(previous.pending, pending) &&
        previous.query == _messageSearchQuery &&
        previous.dividerId == _newMessageDividerId &&
        previous.currentUserId == currentUserId) {
      return previous;
    }
    final layout = _ThreadLayout.build(
      messages: data.messages,
      readMarkers: data.readMarkers,
      pending: pending,
      query: _messageSearchQuery,
      dividerId: _newMessageDividerId,
      currentUserId: currentUserId,
      forumPost: widget.forumPost,
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

  /// Whether [id] is [message] or, for an album, its last message.
  static bool _endsWith(ChatMessage message, String? id) {
    if (id == null) {
      return false;
    }
    return message.id == id || message.album?.last.id == id;
  }

  Future<void> _retryPending(OutboxEntry entry) async {
    final outbox = ref.read(outboxProvider.notifier);
    if (entry.media != null) {
      await outbox.retryMedia(entry);
    } else {
      await outbox.retry(entry.clientId);
    }
  }

  /// Long-pressing a failed message offers to delete it.
  Future<void> _discardPending(OutboxEntry entry) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Delete unsent message?')),
        content: Text(tr("It hasn't been sent and will be removed.")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('pending-discard-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      final outbox = ref.read(outboxProvider.notifier);
      if (entry.media != null) {
        outbox.discardMedia(entry);
      } else {
        outbox.discard(entry.clientId);
      }
    }
  }

  /// The newest message already spoken (or present when the chat opened).
  String? _announcedThroughId;

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
        if (parseBotSlashCommand(body, _slashContext) case (
          final command,
          final options,
        )) {
          await _runSlashAction(() => _invokeBotCommand(command, options));
          return;
        }
        messageBody = body;
    }

    if (_isSlowedDown) {
      return;
    }

    final outbox = ref.read(outboxProvider.notifier);
    if (outbox.isAvailable) {
      await _sendThroughOutbox(outbox, messageBody, composerText: body);
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
      // Mentions point into the body as sent, after emoji become tokens.
      final encodedBody = _encodeCustomEmoji(messageBody);
      await ref
          .read(chatsRepositoryProvider)
          .sendTextMessage(
            conversationId: widget.conversationId,
            body: encodedBody,
            replyToMessageId: replyingTo?.id,
            replyPreview: replyPreview,
            mentions: _mentionsForBody(encodedBody),
          );
      await _setTyping(false);
      _composerController.clear();
      _mentionDraft.clear();
      _emojiDraft.clear();
      _emojiQuery = null;
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _replyingTo = null;
      _pendingDraftReplyId = null;
      if (mounted) {
        _saveDraft();
      }
      _refreshThread();
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not send message. Try again.');
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

  /// Sends through the outbox: the message shows as sending at once and
  /// the composer is free again; when the network fails it is sent again
  /// later. A refusal (slowmode, AutoMod) puts the text back.
  Future<void> _sendThroughOutbox(
    OutboxNotifier outbox,
    String messageBody, {
    required String composerText,
  }) async {
    final replyingTo = _replyingTo;
    final replyPreview = replyingTo == null
        ? null
        : _replyPreviewForMessage(replyingTo);
    // Mentions point into the body as sent, after emoji become tokens.
    final encodedBody = _encodeCustomEmoji(messageBody);
    final entry = outbox.enqueue(
      conversationId: widget.conversationId,
      body: encodedBody,
      replyToMessageId: replyingTo?.id,
      replyPreview: replyPreview,
      mentions: _mentionsForBody(encodedBody),
    );
    if (entry == null) {
      return;
    }
    _composerController.clear();
    _mentionDraft.clear();
    _emojiDraft.clear();
    setState(() {
      _emojiQuery = null;
      _isMentioning = false;
      _mentionQuery = '';
      _slashQuery = null;
      _replyingTo = null;
      _pendingDraftReplyId = null;
      _sendError = null;
    });
    _saveDraft();
    unawaited(_setTyping(false));
    if (!_isAtBottom || _threadData?.hasNewer == true) {
      _jumpToLatest();
    }
    final result = await outbox.sendNow(entry.clientId);
    if (!mounted) {
      return;
    }
    if (result case OutboxRefused(:final error)) {
      outbox.discard(entry.clientId);
      if (_composerController.text.isEmpty) {
        _composerController.value = TextEditingValue(
          text: composerText,
          selection: TextSelection.collapsed(offset: composerText.length),
        );
        if (replyingTo != null && _editingMessage == null) {
          _replyingTo = replyingTo;
        }
        _saveDraft();
      }
      switch (error) {
        case SlowmodeException():
          _waitOutSlowmode(error);
        case SendRefusedException():
          _showSendRefusal(error);
        default:
          setState(() {
            _sendError = tr('Could not send message. Try again.');
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
          .editMessage(messageId: message.id, body: _encodeCustomEmoji(body));
      await _setTyping(false);
      _composerController.clear();
      _emojiDraft.clear();
      _emojiQuery = null;
      _editingMessage = null;
      unawaited(_restoreDraft());
      _refreshThread(messageId: message.id);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not save edit. Try again.');
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

  /// AutoMod or the circle's rules refused the message: says why.
  void _showSendRefusal(SendRefusedException error) {
    if (mounted) {
      setState(() => _sendError = error.toString());
    }
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

  MediaTrayController get _tray =>
      ref.read(mediaTrayProvider(widget.conversationId).notifier);

  /// Whether files can be added to the tray now: the composer is there and
  /// not busy with an edit or a slowmode wait.
  bool get _canAttach =>
      mounted &&
      _editingMessage == null &&
      !_isRecordingVoice &&
      !_isSlowedDown;

  /// Puts files (picked, dropped or pasted) in the tray above the
  /// composer.
  Future<void> _addToTray(List<XFile> files) async {
    if (files.isEmpty || !_canAttach) {
      return;
    }
    setState(() => _sendError = null);
    await _tray.add(files);
  }

  void _handlePastedFiles(List<XFile> files) {
    // Only the chat in front takes a paste, and not while a dialog or the
    // file viewer is open.
    if (ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    unawaited(_addToTray(files));
  }

  /// Cmd+V in the composer: pictures and files on the pasteboard go to the
  /// tray; anything else pastes as text.
  late final _pasteFilesAction = _PasteFilesAction(
    read: () => ref.read(clipboardFilesProvider).read(),
    onFiles: (files) => unawaited(_addToTray(files)),
    canAttach: () => _canAttach,
  );

  Future<void> _pickPhotosAndVideos() async {
    if (_isPickingImage || _isSending || !_canAttach) {
      return;
    }
    setState(() {
      _isPickingImage = true;
      _sendError = null;
    });
    try {
      final room = ref.read(mediaTrayProvider(widget.conversationId)).room;
      if (room <= 0) {
        return;
      }
      final files = await ref
          .read(chatMediaPickerProvider)
          .pickPhotosAndVideos(limit: room);
      await _addToTray(files);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not open your photos. Try again. {error}', {
            'error': error,
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _pickFilesForTray() async {
    if (_isPickingImage || _isSending || !_canAttach) {
      return;
    }
    setState(() {
      _isPickingImage = true;
      _sendError = null;
    });
    try {
      final files = await ref.read(chatMediaPickerProvider).pickFiles();
      await _addToTray(files);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not open the files. Try again. {error}', {
            'error': error,
          });
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  /// The tray's "add more": the same two choices as the attach menu.
  void _showAddMoreMenu(BuildContext anchorContext) {
    showGlassMenu(
      anchorContext,
      anchor: globalRectOf(anchorContext),
      width: 232,
      entries: [
        GlassMenuEntry(
          icon: Icons.image_outlined,
          label: tr('Photos and videos'),
          onSelected: () => unawaited(_pickPhotosAndVideos()),
        ),
        GlassMenuEntry(
          icon: Icons.attach_file_rounded,
          label: tr('Files'),
          onSelected: () => unawaited(_pickFilesForTray()),
        ),
      ],
    );
  }

  /// Sends what the tray holds: photos are scaled and cleaned, everything
  /// is copied to the pending media store, and the attachments appear in
  /// the chat at once as one album, uploading with progress rings. They go
  /// out through the outbox, so they are tried again after a failure and
  /// survive closing the app (where files are kept on disk).
  Future<void> _sendTray() async {
    final tray = ref.read(mediaTrayProvider(widget.conversationId));
    if (!tray.canSend || _isSlowedDown || _editingMessage != null) {
      return;
    }
    final outbox = ref.read(outboxProvider.notifier);
    if (!outbox.isAvailable) {
      setState(() {
        _sendError = tr('Could not send message. Try again.');
      });
      return;
    }
    final controller = _tray;
    controller.setPreparing((0, tray.items.length));
    setState(() => _sendError = null);
    try {
      final items = await prepareDrafts(
        tray.items,
        original: tray.original,
        onProgress: (done, total) => controller.setPreparing((done, total)),
      );
      if (!mounted) {
        return;
      }
      final replyingTo = _replyingTo;
      final entries = await outbox.enqueueMedia(
        conversationId: widget.conversationId,
        items: items,
        caption: tray.caption.trim(),
        replyToMessageId: replyingTo?.id,
        replyPreview: replyingTo == null
            ? null
            : _replyPreviewForMessage(replyingTo),
      );
      if (!mounted) {
        return;
      }
      if (entries.isEmpty) {
        controller.setPreparing(null);
        setState(() => _sendError = tr('Could not send message. Try again.'));
        return;
      }
      controller.clear();
      setState(() {
        _replyingTo = null;
        _pendingDraftReplyId = null;
      });
      _saveDraft();
      if (!_isAtBottom || _threadData?.hasNewer == true) {
        _jumpToLatest();
      }
      unawaited(outbox.startSending());
    } catch (error) {
      controller.setPreparing(null);
      if (mounted) {
        setState(() {
          _sendError = tr('Could not prepare the files. Try again. {error}', {
            'error': error,
          });
        });
      }
    }
  }

  /// Sends the GIF picked from the picker as a message holding its link,
  /// which chats show as the GIF.
  Future<void> _pickAndSendGif() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    if (ref.read(gifSearchAvailableProvider) == false) {
      _showSnackBar(tr("GIF search isn't set up on this server yet."));
      return;
    }
    final gif = await showGifPicker(context);
    if (gif == null || !mounted) {
      return;
    }
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(chatsRepositoryProvider)
          .sendTextMessage(
            conversationId: widget.conversationId,
            body: gif.url,
          );
      _refreshThread();
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() => _sendError = tr('Could not send GIF. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
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
      _refreshThread();
    }
  }

  Future<void> _votePoll(ChatMessage message, List<String> optionIds) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .votePoll(messageId: message.id, optionIds: optionIds);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not record your vote. Try again.'));
      rethrow;
    }
  }

  Future<void> _endPoll(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('End poll')),
        content: Text(tr('End this poll now? Nobody can vote after it ends.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('poll-end-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('End poll')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(chatsRepositoryProvider).endPoll(messageId: message.id);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not end the poll. Try again.'));
    }
  }

  void _showPollVoters(ChatMessage message) {
    showWeCordSheet<void>(
      context,
      title: tr('Votes'),
      builder: (context, _) => PollVotersSheet(message: message),
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
          _sendError = tr(
            'Could not start recording. Check microphone access.',
          );
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
      _refreshThread();
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not send voice message. Try again.');
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

  /// Picks an emoji and puts it in the composer at the cursor.
  Future<void> _pickAndInsertEmoji() async {
    final emoji = await showEmojiReactionPicker(
      context,
      title: tr('Insert emoji'),
    );
    if (emoji == null || !mounted) {
      return;
    }
    final value = _composerController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final text = value.text.replaceRange(selection.start, selection.end, emoji);
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
    _handleComposerChanged(text);
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

  Future<void> _pickAndSendSticker() async {
    if (_isSlowedDown || _isSending || _editingMessage != null) {
      return;
    }
    final sticker = await showStickerPicker(context, circleId: _circleId);
    if (sticker == null || !mounted) {
      return;
    }
    setState(() {
      _isSending = true;
      _sendError = null;
    });
    try {
      await ref
          .read(chatsRepositoryProvider)
          .sendSticker(
            conversationId: widget.conversationId,
            stickerId: sticker.id,
          );
      _refreshThread();
    } on SlowmodeException catch (error) {
      _waitOutSlowmode(error);
    } on SendRefusedException catch (error) {
      _showSendRefusal(error);
    } catch (_) {
      if (mounted) {
        setState(() => _sendError = tr('Could not send sticker. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
    final commands = _slashCandidates();
    final botCommands = _botSlashCandidates();
    final count = commands.length + botCommands.length;
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
      if (index < commands.length) {
        _selectSlashCommand(commands[index]);
      } else {
        _selectBotSlashCommand(botCommands[index - commands.length]);
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
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.id;
    // Someone else's message (as a moderator, or a webhook's creator) is
    // deleted only after confirming.
    if (!message.isSentBy(currentUserId)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(tr('Delete message')),
          content: Text(
            tr('Delete this message for everyone? This cannot be undone.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              key: const ValueKey('message-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Delete')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    try {
      // An album goes as a whole.
      for (final item in message.album ?? [message]) {
        if (!isPendingMessageId(item.id)) {
          await ref
              .read(chatsRepositoryProvider)
              .recallMessage(messageId: item.id);
        }
      }
      _refreshThread(messageId: message.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not delete message. Try again.');
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
      _refreshThread(messageId: message.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sendError = tr('Could not update reaction. Try again.');
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
      _refreshThread(messageId: message.id);
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    } on PinnedMessageLimitException {
      _showSnackBar(
        tr('This conversation already has {count} pinned messages.', {
          'count': maxPinnedMessagesPerConversation,
        }),
      );
    } catch (_) {
      _showSnackBar(
        message.isPinned
            ? tr('Could not unpin message. Try again.')
            : tr('Could not pin message. Try again.'),
      );
    }
  }

  Future<void> _publishMessage(ChatMessage message) async {
    try {
      final delivered = await ref
          .read(announcementRepositoryProvider)
          .publish(message.id);
      _refreshThread(messageId: message.id);
      _showSnackBar(switch (delivered) {
        0 => tr('Published. No channels follow this one yet.'),
        1 => tr('Published to 1 channel.'),
        _ => tr('Published to {count} channels.', {'count': delivered}),
      });
    } catch (_) {
      _showSnackBar(tr('Could not publish the message. Try again.'));
    }
  }

  Future<void> _removeEmbed(ChatMessage message) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .setMessageSuppressEmbeds(messageId: message.id, suppress: true);
      _refreshThread(messageId: message.id);
    } catch (_) {
      _showSnackBar(tr('Could not remove the link preview. Try again.'));
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
      _refreshThread(messageId: message.id);
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
      _showSnackBar(tr('Could not create thread. Try again.'));
    }
  }

  Future<void> _setThreadArchived(String threadId, bool archived) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .setThreadArchived(threadId: threadId, archived: archived);
      ref.invalidate(chatConversationSummaryProvider(widget.conversationId));
      ref.invalidate(conversationsProvider);
      _showSnackBar(
        archived ? tr('Thread archived.') : tr('Thread unarchived.'),
      );
    } catch (_) {
      _showSnackBar(
        archived
            ? tr('Could not archive thread. Try again.')
            : tr('Could not unarchive thread. Try again.'),
      );
    }
  }

  Future<void> _unpinFromList(String messageId) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .unpinMessage(messageId: messageId);
      _refreshThread(messageId: messageId);
      ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    } catch (_) {
      _showSnackBar(tr('Could not unpin message. Try again.'));
    }
  }

  Future<void> _showPinnedMessages(bool canManagePins) async {
    ref.invalidate(pinnedMessagesProvider(widget.conversationId));
    final messageId = await showWeCordSheet<String>(
      context,
      title: tr('Pinned messages'),
      builder: (context, _) {
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

  /// Message search for this conversation (and its circle, and
  /// everywhere), starting with what is in the search field.
  void _openFullSearch() {
    final summary = ref
        .read(chatConversationSummaryProvider(widget.conversationId))
        .value;
    var title = (widget.title ?? summary?.title)?.trim();
    if (title != null && title.startsWith('# ')) {
      title = title.substring(2);
    }
    openPage(
      context,
      GlobalMessageSearchScreen.location(
        conversationId: widget.conversationId,
        conversationTitle: title == null || title.isEmpty ? null : title,
        conversationType: widget.conversationType ?? summary?.type,
        circleId: summary?.circleId ?? _circleId,
        query: _searchController.text,
      ),
    );
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
    showWeCordSheet<void>(
      context,
      title: tr('Reacted with {emoji}', {
        'emoji': reactionLabel(reaction, ref.read(usableEmojisByIdProvider)),
      }),
      builder: (context, _) {
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

  void _showForwardSheet(ChatMessage message) {
    if (message.recalledAt != null) {
      return;
    }
    showWeCordSheet<void>(
      context,
      title: tr('Forward to'),
      builder: (context, _) => MessageForwardSheet(message: message),
    );
  }

  void _cancelReply() {
    setState(() {
      _replyingTo = null;
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

  /// The conversation's images and files (oldest first) for the viewer;
  /// set while the messages are shown.
  List<PreviewFile> Function() _galleryFiles = () => const [];

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

/// The composer's placeholder: "Message #general" in a channel, "Message
/// @Ada" in a direct chat and "Message Weekend crew" in a group or thread;
/// plain "Message" while the name is unknown.
String composerHint(ConversationType? type, String title) {
  var name = title.trim();
  if (type == ConversationType.channel) {
    // Channel routes pass "# general".
    name = name.replaceFirst(RegExp(r'^#\s*'), '');
  }
  if (name.isEmpty || name == tr('Conversation')) {
    return tr('Message');
  }
  return switch (type) {
    ConversationType.channel => tr('Message #{name}', {'name': name}),
    ConversationType.direct => tr('Message @{name}', {'name': name}),
    _ => tr('Message {name}', {'name': name}),
  };
}

/// "in #channel" (or "in Group") under a thread's title.
String _threadSubtitle(ConversationSummary? summary) {
  final parentTitle = summary?.parentTitle?.trim();
  if (parentTitle == null || parentTitle.isEmpty) {
    return tr('Thread');
  }
  final archived = summary?.threadArchivedAt != null;
  final args = {'parent': parentTitle};
  return switch ((summary?.circleId != null, archived)) {
    (true, true) => tr('in #{parent} · Archived', args),
    (true, false) => tr('in #{parent}', args),
    (false, true) => tr('in {parent} · Archived', args),
    (false, false) => tr('in {parent}', args),
  };
}

String _suggestedTitleFor(ChatMessage message) {
  return switch (message.type) {
    MessageType.text => suggestedThreadTitle(
      plainTextFromMarkdown(message.body),
    ),
    MessageType.image => tr('Image'),
    MessageType.voice => tr('Voice message'),
    MessageType.file =>
      message.fileAttachment?.isVideo == true ? tr('Video') : tr('File'),
    MessageType.system => tr('Thread'),
    MessageType.poll => suggestedThreadTitle(message.body),
    MessageType.sticker => tr('Sticker'),
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
      setState(() => _errorText = tr('Thread title is required.'));
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Create thread')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: ConversationThread.maxTitleLength,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: tr('Thread title'),
          errorText: _errorText,
        ),
        onSubmitted: (_) => _create(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(onPressed: _create, child: Text(tr('Create'))),
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
    final unread = summary.unreadCount > 0;
    final replies = switch (summary.replyCount) {
      0 => tr('No replies yet'),
      1 => tr('1 reply'),
      final count => tr('{count} replies', {'count': count}),
    };
    final lastReplyAt = summary.lastReplyAt;
    final detail = summary.replyCount > 0 && lastReplyAt != null
        ? '$replies · ${formatThreadActivity(lastReplyAt)}'
        : replies;
    final c = context.tokens.colors;
    return WeCordPressable(
      key: ValueKey('thread-chip-$messageId'),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      pressedScale: 0.98,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          decoration: BoxDecoration(
            color: hovered ? c.raised : c.well,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 15, color: c.subtle),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  summary.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: unread || summary.replyCount > 0
                        ? c.accentText
                        : c.subtle,
                  ),
                ),
              ),
              if (unread) ...[
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('thread-chip-unread'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// How long ago a thread was last active: "just now", "5m ago", "3h ago",
/// then the date.
String formatThreadActivity(DateTime value, {DateTime? now}) {
  final current = (now ?? DateTime.now()).toUtc();
  final difference = current.difference(value.toUtc());
  if (difference.inMinutes < 1) {
    return tr('just now');
  }
  if (difference.inHours < 1) {
    return tr('{minutes}m ago', {'minutes': difference.inMinutes});
  }
  if (difference.inDays < 1) {
    return tr('{hours}h ago', {'hours': difference.inHours});
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
  Map<String, GroupMember> membersById, {
  Profile? fallbackProfile,
}) {
  // Webhook messages show the webhook, never its creator's profile.
  if (message.webhookName case final webhookName?) {
    return _MessageSender(
      name: webhookName,
      avatarUrl: message.webhookAvatarUrl,
      isBot: true,
    );
  }
  final member = membersById[message.senderId];
  final profile = message.sender ?? member?.profile ?? fallbackProfile;
  final nickname = (message.senderNickname ?? member?.nickname)?.trim() ?? '';
  final label = nickname.isNotEmpty
      ? nickname
      : profile?.displayLabel.trim() ?? '';
  return _MessageSender(
    name: label.isNotEmpty
        ? label
        : profile?.username.trim().isNotEmpty == true
        ? profile!.username
        : tr('Unknown member'),
    avatarUrl: message.senderCircleAvatarUrl ?? profile?.avatarUrl,
    roleColor: message.senderRoleColor,
    userId: message.senderId,
  );
}

class _MessageSender {
  const _MessageSender({
    required this.name,
    this.avatarUrl,
    this.roleColor,
    this.isBot = false,
    this.userId,
  });

  final String name;
  final String? avatarUrl;

  /// The member behind the name (not set for webhooks), whose circle tag
  /// shows next to it.
  final String? userId;

  /// A webhook, marked with a BOT tag.
  final bool isBot;

  /// The sender's highest coloured circle role, as 0xRRGGBB.
  final int? roleColor;
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
  });

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
  final _MessageSender? sender;

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
          _EditedMarker(color: c.muted),
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
            message.interaction == null &&
            firstLinkInMarkdown(message.body, mentions: message.mentions) ==
                null,
      MessageType.image => message.album == null,
      MessageType.system || MessageType.sticker => true,
    };
  }

  /// What a screen reader can do with the message, besides reading it.
  List<MessageSemanticAction> _semanticActions(BuildContext context) {
    return [
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
    final content = _messageContent(isRecalled, textColor);
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

  Widget _messageContent(bool isRecalled, Color textColor) {
    return _MessageContent(
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
    return Container(
      padding: media
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: outgoing ? c.ink : c.raised,
        borderRadius: lifted
            ? BorderRadius.circular(WeCordRadii.bubble + 2)
            : chatBubbleRadius(
                outgoing: outgoing,
                joinsAbove: isFollowUp,
                joinsBelow: hasFollowUp,
              ),
        boxShadow: lifted ? tokens.shadows.menu : null,
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
    final reactions = _isRecalled
        ? const <MessageReaction>[]
        : message.reactions;
    final previewUrl = _previewUrl;
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
            child: visual,
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
          if (previewUrl != null)
            extra(MessageLinkPreviewCard(url: previewUrl, bottomGap: 0), 0),
          if (message.threadSummary case final thread?
              when onOpenThread != null)
            extra(
              _ThreadChip(
                messageId: message.id,
                summary: thread,
                onTap: () => unawaited(onOpenThread!(message)),
              ),
              0,
            ),
          if (reactions.isNotEmpty) extra(_reactionChips(), 0),
          if (showReadReceipt)
            Padding(
              padding: const EdgeInsets.only(right: 2, top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: const ChatReadReceipt(),
              ),
            ),
        ];
        return Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sender != null && showSenderName && !isFollowUp)
                Padding(
                  padding: EdgeInsets.only(left: indent + 6, bottom: 3),
                  child: Row(
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showAvatar) ...[
                    SizedBox(
                      width: avatarSize,
                      child: hasFollowUp
                          ? null
                          : ChatAvatar(
                              key: ValueKey('message-avatar-${message.id}'),
                              name: sender.name,
                              avatarUrl: sender.avatarUrl,
                              size: avatarSize,
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
    final reactions = _isRecalled
        ? const <MessageReaction>[]
        : message.reactions;
    final previewUrl = _previewUrl;
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
        if (previewUrl != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: MessageLinkPreviewCard(url: previewUrl, bottomGap: 0),
          ),
        ],
        if (message.threadSummary case final thread?
            when onOpenThread != null) ...[
          const SizedBox(height: 6),
          _ThreadChip(
            messageId: message.id,
            summary: thread,
            onTap: () => unawaited(onOpenThread!(message)),
          ),
        ],
        if (reactions.isNotEmpty) ...[
          const SizedBox(height: 6),
          _reactionChips(),
        ],
        if (showReadReceipt)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: ChatReadReceipt(),
          ),
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
              : ChatAvatar(
                  key: lifted ? null : ValueKey('message-avatar-${message.id}'),
                  name: sender?.name ?? '?',
                  avatarUrl: sender?.avatarUrl,
                  size: avatarSize,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(child: body),
      ],
    );

    final tint = mentionsMe
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
          color: tint,
          padding: EdgeInsets.fromLTRB(
            side,
            density.space(isFollowUp ? 2 : 10),
            side,
            density.space(hasFollowUp ? 2 : 6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              row(context),
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

  bool _hasVisiblePreview(BuildContext context) {
    final url = _previewUrl;
    if (url == null) {
      return false;
    }
    return ProviderScope.containerOf(
          context,
          listen: false,
        ).read(linkPreviewProvider(url)).value !=
        null;
  }

  /// Whether the menu offers Translate: a text message, and AI available.
  bool _canTranslate(BuildContext context) {
    return !_isRecalled &&
        message.type == MessageType.text &&
        message.body.trim().isNotEmpty &&
        !_isPending &&
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(aiAvailableProvider(circleId));
  }

  /// Translate to the app's language, or hide the translation again.
  MessageAction _translateAction(BuildContext context) {
    final translations = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(aiTranslationsProvider.notifier);
    final shown = translations.isShown(message.id);
    return MessageAction(
      key: const ValueKey('message-translate'),
      icon: Icons.translate_rounded,
      label: shown ? tr('Show original') : tr('Translate'),
      onSelected: () => shown
          ? translations.hide(message.id)
          : unawaited(
              translations.translate(
                message.id,
                message.body,
                conversationId: message.conversationId,
              ),
            ),
    );
  }

  /// What can be done with this message, in menu order.
  List<MessageAction> _actions(BuildContext context) {
    final imageAttachment = _isRecalled ? null : message.imageAttachment;
    return [
      if (canCompose)
        MessageAction(
          slot: MessageActionSlot.reply,
          icon: Icons.reply_rounded,
          label: tr('Reply'),
          onSelected: () => onReply(message),
        ),
      if (message.type == MessageType.text)
        MessageAction(
          slot: MessageActionSlot.copy,
          icon: Icons.copy_rounded,
          label: tr('Copy'),
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: message.body))),
        ),
      // A poll's votes belong to the original, so polls are not
      // forwarded; stickers belong to circles the recipients may not be
      // in.
      if (message.type != MessageType.poll &&
          message.type != MessageType.sticker)
        MessageAction(
          slot: MessageActionSlot.forward,
          icon: Icons.shortcut_rounded,
          label: tr('Forward'),
          onSelected: () => onForward(message),
        ),
      if (_canTranslate(context)) _translateAction(context),
      if (canCompose && isCurrentUser && message.type == MessageType.text)
        MessageAction(
          icon: Icons.edit_outlined,
          label: tr('Edit'),
          onSelected: () => onEdit(message),
        ),
      if (canPin)
        MessageAction(
          icon: message.isPinned
              ? Icons.push_pin_rounded
              : Icons.push_pin_outlined,
          label: message.isPinned ? tr('Unpin') : tr('Pin'),
          onSelected: () => unawaited(onTogglePin(message)),
        ),
      if (onOpenThread != null &&
          (message.threadSummary != null ||
              (canStartThread && message.type != MessageType.system)))
        MessageAction(
          icon: Icons.forum_outlined,
          label: message.threadSummary == null
              ? tr('Create thread')
              : tr('Open thread'),
          onSelected: () => unawaited(onOpenThread!(message)),
        ),
      if (imageAttachment != null)
        MessageAction(
          icon: Icons.visibility_outlined,
          label: tr('Preview'),
          onSelected: () => unawaited(onPreviewImage(imageAttachment)),
        ),
      if (onPublish case final publish?)
        MessageAction(
          key: const ValueKey('message-publish'),
          icon: Icons.campaign_outlined,
          label: tr('Publish'),
          onSelected: () => unawaited(publish(message)),
        ),
      if (canCompose && isCurrentUser && _hasVisiblePreview(context))
        MessageAction(
          icon: Icons.link_off_rounded,
          label: tr('Remove embed'),
          onSelected: () => unawaited(onRemoveEmbed(message)),
        ),
      if (isCurrentUser)
        MessageAction(
          icon: Icons.delete_outline_rounded,
          label: tr('Delete'),
          destructive: true,
          onSelected: () => unawaited(onDelete(message)),
        )
      else if (canModerate)
        MessageAction(
          key: const ValueKey('message-moderator-delete'),
          icon: Icons.delete_outline_rounded,
          label: tr('Delete message'),
          destructive: true,
          onSelected: () => unawaited(onDelete(message)),
        ),
    ];
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

/// The small "edited" after a message's text.
class _EditedMarker extends StatelessWidget {
  const _EditedMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      tr('edited'),
      style: TextStyle(
        fontSize: 11.5,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: color,
      ),
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
    if (AutoModAlert.maybeFromJson(message.attachment) case final alert?) {
      return AutoModAlertCard(alert: alert);
    }
    final c = context.tokens.colors;
    final pinnedMessageId = message.pinnedMessageId;
    final icon = pinnedMessageId != null
        ? Icons.push_pin_rounded
        : message.attachment?['kind'] == 'call'
        ? Icons.call_rounded
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
              message.body,
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
      if (message.replyPreview != null) ...[
        _QuotedReplyPreview(
          senderName: message.replyPreview!.senderName,
          body: _displayBodyForReplyPreview(message.replyPreview!),
          foregroundColor: textColor,
          cards: cards,
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

    if (message.album != null || MessageMediaGroup.isTile(message)) {
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

    if (message.editedAt != null) {
      content.add(const SizedBox(height: 2));
      content.add(_EditedMarker(color: textColor.withValues(alpha: 0.55)));
    }

    if (message.isPublished) {
      content.add(PublishedMarker(foregroundColor: textColor));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: content,
    );
  }

  String _displayBodyForReplyPreview(ReplyPreview preview) {
    final referencedMessage = messagesById[preview.messageId];
    // The server empties the quote when the original is deleted.
    if (referencedMessage?.recalledAt != null || preview.body.isEmpty) {
      return tr('Message deleted');
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
  });

  final String senderName;
  final String body;
  final Color foregroundColor;
  final bool cards;

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
            maxLines: 2,
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
    if (!cards) {
      return quote;
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
            child: quote,
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
                child: MotionSafeImage.network(
                  url,
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.focusNode,
    required this.desktop,
    required this.bottomGap,
    required this.hint,
    required this.slowmodeSeconds,
    required this.slowmodeRemainingSeconds,
    required this.controller,
    required this.isSending,
    required this.isPickingImage,
    required this.errorText,
    required this.mentionCandidates,
    required this.onSelectMention,
    required this.specialMentionCandidates,
    required this.onSelectSpecialMention,
    required this.emojiCandidates,
    required this.onSelectEmoji,
    required this.slashCommands,
    this.botSlashCommands = const [],
    required this.highlightedSlashIndex,
    required this.onSelectSlashCommand,
    this.onSelectBotSlashCommand,
    required this.onComposerKey,
    required this.replyPreviewText,
    required this.isEditing,
    required this.onChanged,
    required this.onSend,
    required this.onPickImage,
    required this.onPickFile,
    required this.onCreatePoll,
    required this.onPickSticker,
    required this.onPickGif,
    required this.onInsertEmoji,
    required this.gifAvailable,
    required this.isRecordingVoice,
    required this.isSendingVoice,
    required this.onStartVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onSendVoiceRecording,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.availableHeight,
    this.attachmentTray,
    this.aiButton,
  });

  /// The AI rewrite button (see [AiComposerButton]); on phones it only
  /// shows once there is a draft.
  final Widget? aiButton;

  /// The tray of files waiting to be sent, above the composer pill.
  final Widget? attachmentTray;

  /// Focus of the text field.
  final FocusNode focusNode;

  /// Desktop sizes: a 22 radius pill, a send button that is always there.
  final bool desktop;

  /// Space under the pill (the home indicator on phones).
  final double bottomGap;
  final String hint;
  final TextEditingController controller;
  final bool isSending;
  final bool isPickingImage;
  final String? errorText;
  final List<GroupMember> mentionCandidates;
  final ValueChanged<GroupMember> onSelectMention;

  /// `@here` and roles offered above the members.
  final List<SpecialMention> specialMentionCandidates;
  final ValueChanged<SpecialMention> onSelectSpecialMention;

  /// Custom emoji offered while `:name` is typed.
  final List<CircleEmoji> emojiCandidates;
  final ValueChanged<CircleEmoji> onSelectEmoji;

  /// The commands offered while one is typed after a leading `/`.
  final List<SlashCommand> slashCommands;

  /// Circle bots' commands, offered after [slashCommands].
  final List<BotSlashCommand> botSlashCommands;
  final int highlightedSlashIndex;
  final ValueChanged<SlashCommand> onSelectSlashCommand;
  final ValueChanged<BotSlashCommand>? onSelectBotSlashCommand;

  /// Sees the text field's key presses first (arrow keys and Enter in the
  /// command list).
  final FocusOnKeyEventCallback onComposerKey;
  final String? replyPreviewText;
  final bool isEditing;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSend;
  final Future<void> Function() onPickImage;
  final Future<void> Function() onPickFile;
  final Future<void> Function() onCreatePoll;
  final Future<void> Function() onPickSticker;
  final Future<void> Function() onPickGif;
  final Future<void> Function() onInsertEmoji;

  /// False once the server said GIF search isn't set up.
  final bool gifAvailable;
  final bool isRecordingVoice;
  final bool isSendingVoice;
  final Future<void> Function() onStartVoiceRecording;
  final Future<void> Function() onCancelVoiceRecording;
  final Future<void> Function() onSendVoiceRecording;
  final VoidCallback onCancelReply;
  final VoidCallback onCancelEdit;

  /// Height of the thread above the keyboard, header included.
  final double availableHeight;

  /// The channel's slowmode for the current user (0 when off) and how long
  /// they still wait before their next message.
  final int slowmodeSeconds;
  final int slowmodeRemainingSeconds;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final isBusy = isSending || isSendingVoice;
    // Edits are not new messages, so slowmode leaves them alone.
    final isSlowed = slowmodeRemainingSeconds > 0 && !isEditing;
    final compact = isCompactWidth(MediaQuery.sizeOf(context).width);
    final buttonSize = desktop ? 40.0 : 44.0;
    final canAttach = !isBusy && !isEditing && !isRecordingVoice && !isSlowed;
    final hasSuggestions =
        slashCommands.isNotEmpty ||
        botSlashCommands.isNotEmpty ||
        emojiCandidates.isNotEmpty ||
        specialMentionCandidates.isNotEmpty ||
        mentionCandidates.isNotEmpty;

    final attach = Builder(
      builder: (buttonContext) => WeCordIconButton(
        key: const ValueKey('composer-attach-button'),
        tooltip: tr('Attach'),
        icon: Icons.add_rounded,
        size: buttonSize,
        iconSize: 24,
        onPressed: canAttach
            ? () => showGlassMenu(
                buttonContext,
                anchor: globalRectOf(buttonContext),
                width: 232,
                entries: [
                  GlassMenuEntry(
                    icon: Icons.image_outlined,
                    label: tr('Photos and videos'),
                    onSelected: () => unawaited(onPickImage()),
                  ),
                  GlassMenuEntry(
                    icon: Icons.attach_file_rounded,
                    label: tr('Files'),
                    onSelected: () => unawaited(onPickFile()),
                  ),
                  GlassMenuEntry(
                    icon: Icons.poll_outlined,
                    label: tr('Create poll'),
                    onSelected: () => unawaited(onCreatePoll()),
                  ),
                  GlassMenuEntry(
                    icon: Icons.sticky_note_2_outlined,
                    label: tr('Send sticker'),
                    onSelected: () => unawaited(onPickSticker()),
                  ),
                  // Wider screens have a GIF button of their own.
                  if (compact)
                    GlassMenuEntry(
                      icon: Icons.gif_box_outlined,
                      label: tr('Send GIF'),
                      onSelected: gifAvailable
                          ? () => unawaited(onPickGif())
                          : null,
                    ),
                ],
              )
            : null,
      ),
    );

    final field = isRecordingVoice
        ? Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              children: [
                const ExcludeSemantics(child: _RecordingDot()),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Recording...'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
          )
        : Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: onComposerKey,
            child: TextField(
              key: const ValueKey('chat-composer-field'),
              focusNode: focusNode,
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              style: TextStyle(
                fontSize: desktop ? 15 : 16,
                height: 1.35,
                color: c.ink,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintMaxLines: 1,
                // The composer is glass over scrolling messages: muted keeps
                // 4.5:1 there where subtle would not.
                hintStyle: TextStyle(
                  fontSize: desktop ? 15 : 16,
                  color: c.muted,
                ),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: onChanged,
              onSubmitted: (_) {
                unawaited(onSend());
              },
            ),
          );

    final gif = _GifButton(
      size: desktop ? 36 : 40,
      tooltip: gifAvailable
          ? tr('Send GIF')
          : tr("GIF search isn't set up on this server yet."),
      onPressed: !gifAvailable || isBusy || isEditing || isSlowed
          ? null
          : () => unawaited(onPickGif()),
    );
    final emoji = WeCordIconButton(
      key: const ValueKey('composer-emoji-button'),
      tooltip: tr('Insert emoji'),
      icon: Icons.sentiment_satisfied_alt_rounded,
      size: desktop ? 36 : 40,
      iconSize: 22,
      variant: WeCordButtonVariant.ghost,
      onPressed: isRecordingVoice ? null : () => unawaited(onInsertEmoji()),
    );
    Widget sendButton() => WeCordIconButton(
      key: const ValueKey('composer-send-button'),
      tooltip: isEditing ? tr('Save edit') : tr('Send'),
      icon: isEditing ? Icons.check_rounded : Icons.arrow_upward_rounded,
      size: buttonSize,
      iconSize: 22,
      variant: WeCordButtonVariant.accent,
      onPressed: isBusy || isSlowed
          ? null
          : () {
              WeCordHaptics.light();
              unawaited(onSend());
            },
    );
    final mic = WeCordIconButton(
      key: const ValueKey('composer-mic-button'),
      tooltip: tr('Record voice message'),
      icon: Icons.mic_none_rounded,
      size: desktop ? 36 : buttonSize,
      iconSize: 22,
      variant: desktop ? WeCordButtonVariant.ghost : WeCordButtonVariant.accent,
      onPressed: isBusy || isEditing || isSlowed
          ? null
          : () {
              WeCordHaptics.medium();
              unawaited(onStartVoiceRecording());
            },
    );
    final sending = isSending
        ? Container(
            width: buttonSize,
            height: buttonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.onAccent,
              ),
            ),
          )
        : null;

    final trailing = isRecordingVoice
        ? <Widget>[
            WeCordIconButton(
              tooltip: tr('Cancel voice message'),
              icon: Icons.close_rounded,
              size: desktop ? 36 : 40,
              variant: WeCordButtonVariant.ghost,
              onPressed: isSendingVoice
                  ? null
                  : () => unawaited(onCancelVoiceRecording()),
            ),
            const SizedBox(width: 2),
            isSendingVoice
                ? Container(
                    width: buttonSize,
                    height: buttonSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onAccent,
                      ),
                    ),
                  )
                : WeCordIconButton(
                    tooltip: tr('Send voice message'),
                    icon: Icons.arrow_upward_rounded,
                    size: buttonSize,
                    iconSize: 22,
                    variant: WeCordButtonVariant.accent,
                    onPressed: () {
                      WeCordHaptics.light();
                      unawaited(onSendVoiceRecording());
                    },
                  ),
          ]
        : desktop
        ? <Widget>[
            ?aiButton,
            gif,
            emoji,
            mic,
            const SizedBox(width: 2),
            sending ?? sendButton(),
          ]
        : <Widget>[
            if (aiButton case final ai?)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) =>
                    value.text.trim().isEmpty ? const SizedBox.shrink() : ai,
              ),
            emoji,
            gif,
            const SizedBox(width: 2),
            // Phones show the microphone until there is something to send.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (sending != null) {
                  return sending;
                }
                final hasText = value.text.trim().isNotEmpty;
                return hasText || isEditing ? sendButton() : mic;
              },
            ),
          ];

    final pill = WeCordGlass(
      key: const ValueKey('chat-composer'),
      borderRadius: BorderRadius.circular(desktop ? 22 : WeCordRadii.xxl),
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          attach,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: buttonSize),
                child: Align(alignment: Alignment.centerLeft, child: field),
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 10,
        0,
        desktop ? 24 : 10,
        bottomGap,
      ),
      // On short screens with the keyboard up, banners and suggestions
      // scroll above the text field instead of pushing the messages out.
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight * 0.5),
        child: SingleChildScrollView(
          reverse: true,
          clipBehavior: Clip.none,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (errorText != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                    decoration: BoxDecoration(
                      color: c.dangerSoft,
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                    ),
                    // A live region: the error is read out as it appears.
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.dangerText,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (hasSuggestions) ...[
                WeCordGlass(
                  key: const ValueKey('composer-suggestions'),
                  elevation: GlassElevation.menu,
                  borderRadius: BorderRadius.circular(WeCordRadii.xl),
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (slashCommands.isNotEmpty ||
                          botSlashCommands.isNotEmpty)
                        SlashCommandList(
                          commands: slashCommands,
                          botCommands: botSlashCommands,
                          onSelectBot: onSelectBotSlashCommand,
                          highlightedIndex: highlightedSlashIndex,
                          onSelect: onSelectSlashCommand,
                          maxHeight: math.min(240, availableHeight * 0.3),
                          framed: false,
                        ),
                      if (emojiCandidates.isNotEmpty)
                        CustomEmojiCandidateList(
                          candidates: emojiCandidates,
                          onSelect: onSelectEmoji,
                          maxHeight: math.min(220, availableHeight * 0.3),
                          framed: false,
                        ),
                      if (specialMentionCandidates.isNotEmpty)
                        SpecialMentionCandidateList(
                          candidates: specialMentionCandidates,
                          onSelect: onSelectSpecialMention,
                          maxHeight: math.min(150, availableHeight * 0.2),
                          framed: false,
                        ),
                      if (mentionCandidates.isNotEmpty)
                        MentionCandidateList(
                          candidates: mentionCandidates,
                          onSelect: onSelectMention,
                          maxHeight: math.min(180, availableHeight * 0.25),
                          framed: false,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (replyPreviewText != null) ...[
                _ComposerModeBanner(
                  icon: Icons.reply_rounded,
                  text: tr('Replying to {message}', {
                    'message': replyPreviewText,
                  }),
                  tooltip: tr('Cancel reply'),
                  onPressed: onCancelReply,
                ),
                const SizedBox(height: 6),
              ],
              if (isEditing) ...[
                _ComposerModeBanner(
                  icon: Icons.edit_outlined,
                  text: tr('Editing message'),
                  tooltip: tr('Cancel edit'),
                  onPressed: onCancelEdit,
                ),
                const SizedBox(height: 6),
              ],
              if (slowmodeSeconds > 0) ...[
                _SlowmodeBanner(remainingSeconds: slowmodeRemainingSeconds),
                const SizedBox(height: 6),
              ],
              if (attachmentTray != null) ...[
                attachmentTray!,
                const SizedBox(height: 6),
              ],
              pill,
            ],
          ),
        ),
      ),
    );
  }
}

/// The GIF button: the word in a round ghost button.
class _GifButton extends StatelessWidget {
  const _GifButton({
    required this.size,
    required this.tooltip,
    required this.onPressed,
  });

  final double size;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: const ValueKey('composer-gif-button'),
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      shape: const CircleBorder(),
      pressedScale: 0.92,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedOpacity(
          duration: WeCordMotion.quick,
          opacity: onPressed == null ? 0.4 : 1,
          child: SizedBox.square(
            dimension: math.max(size, WeCordSizes.touchTarget),
            child: Center(
              child: AnimatedContainer(
                duration: WeCordMotion.quick,
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hovered && onPressed != null
                      ? c.raised
                      : c.raised.withValues(alpha: 0),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  'GIF',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: c.ink,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The red dot while a voice message records.
class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: c.danger,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: c.danger.withValues(alpha: 0.35), blurRadius: 6),
        ],
      ),
    );
  }
}

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
    final c = context.tokens.colors;
    final style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: c.muted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        key: const ValueKey('composer-slowmode'),
        children: [
          Icon(Icons.timer_outlined, size: 15, color: c.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              tr('Slowmode is enabled'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (remainingSeconds > 0)
            Text(
              formatSlowmodeCountdown(remainingSeconds),
              key: const ValueKey('composer-slowmode-countdown'),
              style: style.copyWith(
                color: c.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
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
  const _ReadOnlyComposerNotice({
    required this.desktop,
    required this.bottomGap,
    this.timedOutUntil,
  });

  final DateTime? timedOutUntil;
  final bool desktop;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        desktop ? 24 : 10,
        0,
        desktop ? 24 : 10,
        bottomGap,
      ),
      child: WeCordGlass(
        key: const ValueKey('chat-read-only-notice'),
        borderRadius: BorderRadius.circular(desktop ? 22 : WeCordRadii.xxl),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(
              timedOutUntil == null
                  ? Icons.lock_outline_rounded
                  : Icons.timer_outlined,
              size: 18,
              color: c.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(switch (timedOutUntil) {
                final until? => tr(
                  "You're timed out until {time}. "
                  'You can read, but not send messages or react.',
                  {'time': formatTimeoutEnd(until)},
                ),
                null => tr(
                  "You don't have permission to send messages in this "
                  'channel',
                ),
              }, style: TextStyle(fontSize: 14, height: 1.4, color: c.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replying to or editing a message: a glass strip over the composer.
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
    final c = context.tokens.colors;
    return WeCordGlass(
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: c.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          WeCordIconButton(
            tooltip: tooltip,
            icon: Icons.close_rounded,
            size: 32,
            iconSize: 18,
            variant: WeCordButtonVariant.ghost,
            onPressed: onPressed,
          ),
        ],
      ),
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

/// The quoted text of a reply to [message]. What is sent stays English, as
/// every reader sees it; the composer shows it [localized].
String _replyPreviewBody(ChatMessage message, {bool localized = false}) {
  String label(String english) => localized ? tr(english) : english;
  if (message.recalledAt != null) {
    return label('Message');
  }
  return switch (message.type) {
    MessageType.text =>
      message.body.trim().isEmpty
          ? label('Message')
          : plainTextFromMarkdown(message.body.trim()),
    MessageType.system =>
      message.body.trim().isEmpty ? label('Message') : message.body.trim(),
    MessageType.image => label('Image'),
    MessageType.file => label('File'),
    MessageType.voice => label('Voice message'),
    MessageType.poll => pollPreviewText(message.body),
    MessageType.sticker => stickerPreviewText(message.body),
  };
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

/// The loaded messages laid out for the list (see
/// `_ChatThreadScreenState._layoutFor`).
/// Pastes pictures and files from the macOS pasteboard into the tray. When
/// the pasteboard holds none (plain text), the text field's own paste runs.
class _PasteFilesAction extends ContextAction<PasteTextIntent> {
  _PasteFilesAction({
    required this.read,
    required this.onFiles,
    required this.canAttach,
  });

  final Future<List<XFile>> Function() read;
  final void Function(List<XFile> files) onFiles;
  final bool Function() canAttach;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    unawaited(_paste(intent));
    return null;
  }

  Future<void> _paste(PasteTextIntent intent) async {
    final files = canAttach() ? await read() : const <XFile>[];
    if (files.isNotEmpty) {
      onFiles(files);
      return;
    }
    callingAction?.invoke(intent);
  }
}

class _ThreadLayout {
  _ThreadLayout._({
    required this.messages,
    required this.readMarkers,
    required this.pending,
    required this.query,
    required this.dividerId,
    required this.currentUserId,
    required this.fullOldestToNewest,
    required this.messagesById,
    required this.display,
    required this.displayIndex,
    required this.pendingById,
    required this.followUpIds,
    required this.dayStartIds,
    required this.openingPostId,
    required this.openingPostReplyCount,
    required this.latestOutgoingReadState,
  });

  factory _ThreadLayout.build({
    required List<ChatMessage> messages,
    required List<ConversationReadMarker> readMarkers,
    required List<OutboxEntry> pending,
    required String query,
    required String? dividerId,
    required String? currentUserId,
    required bool forumPost,
    required List<ChatMessage> Function(List<ChatMessage>, String) search,
  }) {
    final searching = query.trim().isNotEmpty;
    final fullOldestToNewest = _isOldestFirst(messages)
        ? messages
        : _messagesOldestToNewest(messages);
    final messagesById = {
      for (final message in fullOldestToNewest) message.id: message,
    };
    final visible = searching
        ? _messagesOldestToNewest(search(fullOldestToNewest, query))
        : fullOldestToNewest;
    // Messages still in the outbox follow the loaded ones, unless the
    // stored copy already arrived.
    final storedClientIds = {
      for (final message in fullOldestToNewest) ?message.clientId,
    };
    final pendingById = <String, OutboxEntry>{};
    final pendingMessages = <ChatMessage>[];
    if (!searching && currentUserId != null) {
      for (final entry in pending) {
        if (storedClientIds.contains(entry.clientId)) {
          continue;
        }
        pendingById[entry.pendingMessageId] = entry;
        pendingMessages.add(entry.toPendingMessage(currentUserId));
      }
    }
    final unfolded = pendingMessages.isEmpty
        ? visible
        : [...visible, ...pendingMessages];
    // Pictures sent together show as one album bubble. (Not while
    // searching: a result is a single message.)
    final folded = searching
        ? FoldedAlbums(messages: unfolded, headOf: const {})
        : foldAlbums(unfolded);
    final display = folded.messages;
    final displayIndex = {
      for (final (index, message) in display.indexed) message.id: index,
    };
    // The rest of an album is found where its first message is.
    for (final MapEntry(key: siblingId, value: headId)
        in folded.headOf.entries) {
      displayIndex[siblingId] = displayIndex[headId]!;
    }
    // Grouping compares neighbours, which search results are not.
    final followUpIds = !searching
        ? _followUpMessageIds(display, newMessageDividerId: dividerId)
        : <String>{};
    // The first message of each day gets a day separator.
    final dayStartIds = <String>{
      if (!searching)
        for (final (index, message) in display.indexed)
          if (index == 0 ||
              !_isSameLocalDay(display[index - 1].createdAt, message.createdAt))
            message.id,
    };
    // A forum post opens with its first message; replies start their own
    // group under it.
    final openingPostId = forumPost
        ? fullOldestToNewest
              .where((message) => message.type != MessageType.system)
              .firstOrNull
              ?.id
        : null;
    var openingPostReplyCount = 0;
    if (openingPostId != null) {
      final index = displayIndex[openingPostId];
      if (index != null && index + 1 < display.length) {
        followUpIds.remove(display[index + 1].id);
      }
      openingPostReplyCount = fullOldestToNewest
          .where(
            (other) =>
                other.id != openingPostId &&
                other.type != MessageType.system &&
                other.recalledAt == null,
          )
          .length;
    }
    return _ThreadLayout._(
      messages: messages,
      readMarkers: readMarkers,
      pending: pending,
      query: query,
      dividerId: dividerId,
      currentUserId: currentUserId,
      fullOldestToNewest: fullOldestToNewest,
      messagesById: messagesById,
      display: display,
      displayIndex: displayIndex,
      pendingById: pendingById,
      followUpIds: followUpIds,
      dayStartIds: dayStartIds,
      openingPostId: openingPostId,
      openingPostReplyCount: openingPostReplyCount,
      latestOutgoingReadState: _latestOutgoingReadState(
        messages: fullOldestToNewest,
        readMarkers: readMarkers,
        currentUserId: currentUserId,
      ),
    );
  }

  // What it was built from.
  final List<ChatMessage> messages;
  final List<ConversationReadMarker> readMarkers;
  final List<OutboxEntry> pending;
  final String query;
  final String? dividerId;
  final String? currentUserId;

  /// Every loaded message, oldest first.
  final List<ChatMessage> fullOldestToNewest;
  final Map<String, ChatMessage> messagesById;

  /// What the list shows, oldest first: the search results, or the loaded
  /// messages and then the ones still sending.
  final List<ChatMessage> display;
  final Map<String, int> displayIndex;

  /// Outbox entries by the id their message shows under.
  final Map<String, OutboxEntry> pendingById;

  /// The outbox entry that [message]'s bubble shows the status of: its own,
  /// or for an album the first of its attachments that failed, else the
  /// first still sending.
  OutboxEntry? pendingEntryFor(ChatMessage message) {
    final album = message.album;
    if (album == null) {
      return pendingById[message.id];
    }
    OutboxEntry? sending;
    for (final item in album) {
      final entry = pendingById[item.id];
      if (entry == null) {
        continue;
      }
      if (entry.state == OutboxState.failed) {
        return entry;
      }
      sending ??= entry;
    }
    return sending;
  }

  final Set<String> followUpIds;
  final Set<String> dayStartIds;
  final String? openingPostId;
  final int openingPostReplyCount;
  final _LatestOutgoingReadState latestOutgoingReadState;
}

bool _isOldestFirst(List<ChatMessage> messages) {
  for (var index = 1; index < messages.length; index++) {
    final previous = messages[index - 1];
    final message = messages[index];
    final byTime = previous.createdAt.compareTo(message.createdAt);
    if (byTime > 0 || (byTime == 0 && previous.id.compareTo(message.id) > 0)) {
      return false;
    }
  }
  return true;
}
