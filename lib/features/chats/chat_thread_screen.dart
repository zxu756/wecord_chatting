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
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/swipe_to_reply.dart';
import 'package:wecord/features/chats/thread/footer_widgets.dart';
import 'package:wecord/features/chats/thread/message_sender.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_registrations.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_registrations.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/features/chats/thread/thread_layout.dart';
import 'package:wecord/features/chats/thread/thread_text.dart';
import 'package:wecord/features/chain/chain_card.dart';
import 'package:wecord/features/chain/chain_create_sheet.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chats/automod_alert_card.dart';
import 'package:wecord/features/chats/chat_profile_panel.dart';
import 'package:wecord/features/chats/chat_thread_header.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
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
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/notes/note_models.dart' show NoteMeta;
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
export 'package:wecord/features/chats/thread/registry/header_actions.dart'
    show ChatThreadAction;

part 'thread/banners.dart';
part 'thread/build_composer.dart';
part 'thread/build_header.dart';
part 'thread/build_messages.dart';
part 'thread/composer.dart';
part 'thread/composer_notices.dart';
part 'thread/drop_zone.dart';
part 'thread/message_bubble.dart';
part 'thread/message_content.dart';
part 'thread/selection_mode.dart';
part 'thread/state_attachments.dart';
part 'thread/state_composer.dart';
part 'thread/state_composer_menu.dart';
part 'thread/state_header.dart';
part 'thread/state_list.dart';
part 'thread/state_messages.dart';
part 'thread/state_send.dart';
part 'thread/thread_facts.dart';
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
    final f = _gatherFacts(context);
    final h = _headerActionsFor(context, f);

    // Measured here rather than from the screen, so a thread panel in the
    // wide circle layout also gets the compact header.
    return LayoutBuilder(
      builder: (context, constraints) {
        final l = _resolveLayout(context, constraints, f, h);
        final header = _buildHeader(context, f, h, l);
        final (:catchUpBanner, :banners) = _buildBanners(context, f, h, l);
        final topInset = f.desktop
            ? 0.0
            : _topInset ?? MediaQuery.paddingOf(context).top + 64;
        final bottomInset = _bottomInset ?? 76 + f.composerBottomGap;
        final messagesArea = _buildMessagesArea(
          context,
          f,
          l,
          topInset: topInset,
          bottomInset: bottomInset,
        );
        final composerArea = _buildComposerArea(context, f, h, l);
        final _ThreadFacts(
          :title,
          :avatarUrl,
          :canSend,
          :tokens,
          :c,
          :desktop,
          :presenceColor,
        ) = f;
        final _ThreadLayoutFacts(
          :docsPlacement,
          :showDocs,
          :profileUserId,
          :profilePlacement,
        ) = l;
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

        Widget dropZone(Widget child) => _dropZone(context, canSend, child);

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
