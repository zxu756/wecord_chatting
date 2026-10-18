import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
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
import 'package:wecord/features/chats/system_notice_text.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/swipe_to_reply.dart';
import 'package:wecord/features/chats/thread/message_sender.dart';
import 'package:wecord/features/chats/thread/thread_layout.dart';
import 'package:wecord/features/chats/thread/thread_text.dart';
import 'package:wecord/features/chain/chain_card.dart';
import 'package:wecord/features/chain/chain_create_sheet.dart';
import 'package:wecord/features/chain/chain_models.dart';
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
import 'package:wecord/features/chats/disappearing_messages.dart';
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
import 'package:wecord/features/chats/message_review_mark.dart';
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
import 'package:wecord/features/chats/quick_reaction.dart';
import 'package:wecord/features/chats/poll_message.dart';
import 'package:wecord/features/chats/polls_repository.dart';
import 'package:wecord/features/chats/role_mentions.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/features/chats/view_once.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward.dart';
import 'package:wecord/features/chats/selection/chat_selection.dart';
import 'package:wecord/features/contact_cards/contact_cards.dart';
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
import 'package:wecord/features/voice_input/voice_input_button.dart';
import 'package:wecord/features/voice_input/voice_input_panel.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/workspace/workspace_cards.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_panel.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/file_preview/file_preview_scope.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/image_text/image_text_sheet.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/pat/pat_avatar.dart';
import 'package:wecord/features/pat/pat_info.dart';
import 'package:wecord/features/pat/pat_line.dart';
import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/later_cards.dart' show laterPreview;
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_sheet.dart';
import 'package:wecord/features/later/when_sheet.dart';
import 'package:wecord/features/location/live_location_banner.dart';
import 'package:wecord/features/location/location_actions.dart';
import 'package:wecord/features/location/location_cards.dart';
import 'package:wecord/features/location/location_models.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/wallpapers/wallpaper_backdrop.dart';
import 'package:wecord/features/wallpapers/wallpaper_controller.dart';
import 'package:wecord/features/wallpapers/wallpaper_picker.dart';
import 'package:wecord/features/settings/settings_screen.dart';
import 'package:wecord/shared/l10n/error_text.dart';
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
import 'package:wecord/shared/ui/display_size_image.dart';
import 'package:wecord/shared/ui/ui.dart';

export 'package:wecord/features/chats/chat_thread_controller.dart'
    show ChatThreadData, chatThreadProvider;
export 'package:wecord/features/chats/thread/thread_text.dart'
    show composerHint, formatSlowmodeCountdown, formatThreadActivity;

part 'thread/banners.dart';
part 'thread/composer.dart';
part 'thread/composer_notices.dart';
part 'thread/message_bubble.dart';
part 'thread/message_content.dart';
part 'thread/state_attachments.dart';
part 'thread/state_composer.dart';
part 'thread/state_composer_menu.dart';
part 'thread/state_header.dart';
part 'thread/state_list.dart';
part 'thread/state_messages.dart';
part 'thread/state_send.dart';
part 'thread/thread_title_dialog.dart';

final chatActivityProvider = StreamProvider.autoDispose
    .family<ConversationActivity, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .conversationActivity(conversationId);
    });

/// Whether the current user may archive a thread: the thread's conversation
/// and its id. Answered with the chat's other capabilities in one request
/// where the repository can (see [canManageThreadOf]).
final canManageThreadProvider = FutureProvider.autoDispose
    .family<bool, ({String conversationId, String threadId})>((ref, thread) {
      return canManageThreadOf(
        ref.watch(chatsRepositoryProvider),
        threadConversationId: thread.conversationId,
        threadId: thread.threadId,
      );
    });

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
    this.menuOnly = false,
    this.primary = false,
  });

  /// Stays a button in the wide header; every other action moves into its
  /// More menu, so the title keeps the room (see the design language's
  /// header rule). Phones ignore it: they keep search, one primary action
  /// of their own choosing and More.
  final bool primary;

  /// Only in the More menu: wide headers have no room for another button
  /// (the title would be squeezed out) and reach it another way.
  final bool menuOnly;

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
    this.circleMemberIds,
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

  /// The ids of the circle's members, for a channel without a topic: its
  /// header then says "16 members · 4 online" like a group's.
  final Set<String>? circleMemberIds;

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

  /// Writes the drafts to the device when this screen goes away (they are
  /// otherwise written a moment after the typing stops).
  late final ComposerDraftsController _draftsController;
  var _isSending = false;
  var _isPickingImage = false;
  StreamSubscription<List<XFile>>? _pasteSubscription;
  var _isRecordingVoice = false;
  var _isSendingVoice = false;

  /// Ticks once a second while recording; stops the recording at
  /// [maxVoiceRecordingSeconds].
  Timer? _voiceTimer;
  var _voiceTicks = 0;
  DateTime? _voiceStartedAt;

  /// Seconds left of the recording once they are down to
  /// [voiceCountdownSeconds]; null before. Only the countdown listens, so
  /// the screen does not rebuild every second.
  final _voiceSecondsLeft = ValueNotifier<int?>(null);
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

  /// This chat is the user's note to self: no typing, no read receipts.
  var _isNoteToSelf = false;
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

  /// The list's entries in display order, for Shift-click ranges in
  /// selection mode.
  var _displayEntries = const <ChatMessage>[];

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
  ThreadLayout? _layout;
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

  /// The notes and lists panel beside the chat (wide layouts), and what it
  /// was last asked to show.
  var _workspaceOpen = false;
  WorkspaceRequest? _workspaceRequest;
  final _workspaceKey = GlobalKey<WorkspacePanelState>();

  List<ChatMessage>? _expirySource;

  List<ChatMessage>? _expiryResult;

  Timer? _expiryTimer;

  String? _lastDisappearingNoticeId;

  /// The newest message already spoken (or present when the chat opened).
  String? _announcedThroughId;

  /// Cmd+V in the composer: pictures and files on the pasteboard go to the
  /// tray; anything else pastes as text.
  late final _pasteFilesAction = _PasteFilesAction(
    read: () => ref.read(clipboardFilesProvider).read(),
    onFiles: (files) => unawaited(_addToTray(files)),
    canAttach: () => _canAttach,
  );

  /// The conversation's images and files (oldest first) for the viewer;
  /// set while the messages are shown.
  List<PreviewFile> Function() _galleryFiles = () => const [];

  @override
  void initState() {
    super.initState();
    ComposerFocusRegistry.attach(_composerFocus);
    _scrollController.addListener(_handleScroll);
    _activeConversationController = ref.read(
      activeConversationIdProvider.notifier,
    );
    _scheduleActiveConversationUpdate(widget.conversationId);
    // A note opened from the quick switcher asked for this chat's panel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final request = mounted ? ref.read(workspaceRequestProvider) : null;
      if (request != null && request.conversationId == widget.conversationId) {
        _showWorkspace(request);
      }
    });
    _draftsController = ref.read(composerDraftsProvider.notifier);
    unawaited(_restoreDraft());
    // Browsers hand pasted pictures and files over as events; macOS asks the
    // pasteboard when the text field is pasted into (see _pasteFilesAction).
    final clipboard = ref.read(clipboardFilesProvider);
    if (kIsWeb && clipboard.isSupported) {
      _pasteSubscription = clipboard.pasted.listen(_handlePastedFiles);
    }
  }

  @override
  void didUpdateWidget(covariant ChatThreadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _scheduleActiveConversationUpdate(widget.conversationId);
      // Each conversation keeps its own draft (saved as it was typed).
      unawaited(_draftsController.flush());
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
    _voiceTimer?.cancel();
    _voiceSecondsLeft.dispose();
    _typingTimer?.cancel();
    _expiryTimer?.cancel();
    _highlightTimer?.cancel();
    unawaited(_draftsController.flush());
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

  @override
  Widget build(BuildContext context) {
    // A scheduled message that went out shows up here; its list follows.
    ref.listen(
      chatThreadProvider(
        widget.conversationId,
      ).select((state) => state.value?.messages.lastOrNull?.id),
      (_, _) =>
          ref.invalidate(scheduledMessagesProvider(widget.conversationId)),
    );
    ref.listen(workspaceRequestProvider, (_, request) {
      if (request != null && request.conversationId == widget.conversationId) {
        _showWorkspace(request);
      }
    });
    // Dragging the panel shut closes it.
    ref.listen(panelLayoutProvider.select((layout) => layout.docsCollapsed), (
      _,
      collapsed,
    ) {
      if (collapsed && _workspaceOpen) {
        setState(() => _workspaceOpen = false);
      }
    });
    ref.listen(pendingMessageJumpProvider, (_, jump) {
      if (jump != null &&
          ref.read(chatThreadProvider(widget.conversationId)).hasValue) {
        _schedulePendingJump();
      }
    });
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
    final canCall =
        !isNoteToSelf &&
        (conversationType == ConversationType.direct ||
            conversationType == ConversationType.group);
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
                            semanticLabel: tr(
                              'Messages disappear after {time}',
                              {'time': disappearingLabel(disappearingSeconds)},
                            ),
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
        final selecting = ref.watch(
          chatSelectionProvider(
            widget.conversationId,
          ).select((state) => state.active),
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
                errorText(error),
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
            _displayEntries = display;
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
              nameOf: (message) => senderFor(
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
                  senderName: senderFor(
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
                  sender: senderFor(message, membersById),
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
                  onRemind: _remindAbout,
                  isSaved: savedIds.contains(message.id),
                  onToggleSaved: _toggleSaved,
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
                  sender: senderFor(
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
                      !isNoteToSelf &&
                      messageEndsAt(
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
                  onRemind: _remindAbout,
                  isSaved: savedIds.contains(message.id),
                  onToggleSaved: _toggleSaved,
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
              final highlightedRow = AnimatedContainer(
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
              final highlighted = MessageSelectionRow(
                conversationId: widget.conversationId,
                message: message,
                label: () => messageSpokenSummary(
                  message,
                  senderName: message.isSentBy(currentUserId)
                      ? tr('You')
                      : senderFor(message, membersById).name,
                ),
                entries: () => _displayEntries,
                child: highlightedRow,
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
                  : senderFor(
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
                messageEndsAt(
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
                savedIds.contains(message.id),
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

        final composerColumn = Column(
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
            if (canSend)
              TimePhraseSuggestion(
                controller: _composerController,
                horizontalPadding: desktop ? 24 : 16,
                onConverted: () =>
                    _handleComposerChanged(_composerController.text),
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
                    hint: isNoteToSelf
                        ? tr('Send something to your devices')
                        : composerHint(conversationType, title),
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
                        : replyPreviewBody(_replyingTo!, localized: true),
                    isEditing: _editingMessage != null,
                    onChanged: _handleComposerChanged,
                    onSend: _sendMessage,
                    onSchedule: _scheduleMessage,
                    scheduledBanner: ScheduledMessagesBanner(
                      conversationId: widget.conversationId,
                      onOpen: _openScheduledMessages,
                    ),
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
                      allowViewOnce: isDirectOrGroup,
                      onSend: _sendTray,
                      onAddMore: _showAddMoreMenu,
                    ),
                    onCreatePoll: _openPollComposer,
                    voiceButton: ref.watch(voiceInputAvailableProvider)
                        ? VoiceInputButton(
                            owner: widget.conversationId,
                            field: _composerController,
                            focus: _composerFocus,
                            size: desktop ? 36 : 40,
                            enabled:
                                !_isSending &&
                                !_isSendingVoice &&
                                !_isRecordingVoice,
                          )
                        : null,
                    voicePanel: ref.watch(voiceInputAvailableProvider)
                        ? VoiceInputPanel(owner: widget.conversationId)
                        : null,
                    onCreateChain: conversationType == ConversationType.direct
                        ? null
                        : _openChainComposer,
                    onContactCard: _openContactCardPicker,
                    onSendLocation: _sendLocation,
                    onShareLiveLocation:
                        conversationType == ConversationType.direct ||
                            conversationType == ConversationType.group
                        ? _shareLiveLocation
                        : null,
                    onChangeWallpaper: openWallpaper,
                    onInsertTime: _insertTime,
                    onShowEvents:
                        conversationType == ConversationType.direct ||
                            conversationType == ConversationType.group
                        ? _showEvents
                        : null,
                    onPickSticker: _pickAndSendSticker,
                    onPickGif: _pickAndSendGif,
                    onInsertEmoji: _pickAndInsertEmoji,
                    gifAvailable:
                        ref.watch(gifSearchAvailableProvider) != false,
                    isRecordingVoice: _isRecordingVoice,
                    voiceSecondsLeft: _voiceSecondsLeft,
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
        final composerArea = selecting
            ? ChatSelectionBar(
                environment: SelectionEnvironment(
                  conversationId: widget.conversationId,
                  conversationTitle: title,
                  currentUserId: currentUserId,
                  canModerate: canDeleteAsModerator,
                  senderName: (message) => message.isSentBy(currentUserId)
                      ? tr('You')
                      : senderFor(message, {
                          for (final member
                              in groupDetail?.members ?? const <GroupMember>[])
                            member.profile.id: member,
                        }).name,
                  onChanged: _refreshThread,
                ),
                desktop: desktop,
                bottomGap: composerBottomGap,
              )
            : composerColumn;
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

        // The wallpaper is painted once behind the list, not per message.
        final wallpaperArea = Stack(
          children: [
            Positioned.fill(child: ChatWallpaperBackdrop(edges: desktop)),
            Positioned.fill(child: messagesArea),
          ],
        );

        // Gives everything in the chat its wallpaper: bubbles, dates and the
        // typing line use their wallpaper surfaces while one is showing.
        Widget withWallpaper(Widget child) => ChatWallpaperHost(
          conversationId: widget.conversationId,
          child: child,
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
                    Positioned.fill(child: wallpaperArea),
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
          final desktopScaffold = Scaffold(
            backgroundColor: c.panel,
            body: showDocs
                ? ResizableSidePanelRow(
                    panel: ResizablePanel.docs,
                    placement: docsPlacement,
                    content: dropZone(chatColumn),
                    side: WorkspacePanel(
                      key: _workspaceKey,
                      conversationId: widget.conversationId,
                      title: title,
                      initialTab: _workspaceRequest?.tab ?? WorkspaceTab.notes,
                      initialNoteId: _workspaceRequest?.noteId,
                      initialListId: _workspaceRequest?.listId,
                      initialItemId: _workspaceRequest?.itemId,
                      onClose: () {
                        setState(() => _workspaceOpen = false);
                        unawaited(
                          ref
                              .read(panelLayoutProvider.notifier)
                              .setCollapsed(ResizablePanel.docs, true),
                        );
                      },
                      onOpenPage: () {
                        final request = _workspaceRequest;
                        setState(() => _workspaceOpen = false);
                        context.go(
                          workspaceLocation(
                            widget.conversationId,
                            tab: request?.tab ?? WorkspaceTab.notes,
                            noteId: request?.noteId,
                            listId: request?.listId,
                            itemId: request?.itemId,
                          ),
                          extra: title,
                        );
                      },
                    ),
                  )
                : profileUserId == null
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
          return withWallpaper(
            ChatSelectionKeyboard(
              conversationId: widget.conversationId,
              child: desktopScaffold,
            ),
          );
        }
        final phoneScaffold = dropZone(
          Scaffold(
            backgroundColor: c.panel,
            body: AnnotatedRegion<SystemUiOverlayStyle>(
              value: tokens.isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: Stack(
                children: [
                  Positioned.fill(child: wallpaperArea),
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
        return withWallpaper(
          ChatSelectionKeyboard(
            conversationId: widget.conversationId,
            child: phoneScaffold,
          ),
        );
      },
    );
  }
}

const _bottomScrollThreshold = 48.0;
