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

part 'thread/state_attachments.dart';
part 'thread/state_composer.dart';
part 'thread/state_composer_menu.dart';
part 'thread/state_header.dart';
part 'thread/state_list.dart';
part 'thread/state_messages.dart';
part 'thread/state_send.dart';

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

const _bottomScrollThreshold = 48.0;

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
          if (message.expiresAt case final expiresAt? when !_isRecalled)
            extra(
              Align(
                alignment: outgoing
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: WallpaperPill(
                  child: DisappearingMark(expiresAt: expiresAt),
                ),
              ),
              0,
            ),
          if (message.reviewState case final reviewState?)
            extra(
              Align(
                alignment: outgoing
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: WallpaperPill(
                  child: MessageReviewMark(
                    state: reviewState,
                    isOwn: isCurrentUser,
                  ),
                ),
              ),
              0,
            ),
          if (showReadReceipt)
            Padding(
              padding: const EdgeInsets.only(right: 2, top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: const WallpaperPill(child: ChatReadReceipt()),
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
        if (message.expiresAt case final expiresAt? when !_isRecalled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DisappearingMark(expiresAt: expiresAt),
          ),
        if (message.reviewState case final reviewState?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageReviewMark(state: reviewState, isOwn: isCurrentUser),
          ),
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

  /// Whether the menu offers Transcribe: a sent voice message.
  bool get _canTranscribe =>
      !_isRecalled &&
      !_isPending &&
      !message.isViewOnce &&
      message.type == MessageType.voice &&
      message.voiceAttachment != null;

  /// Shows the voice message as text under its waveform, or hides it again.
  MessageAction _transcribeAction(BuildContext context) {
    final transcripts = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(transcriptsProvider.notifier);
    final shown = transcripts.isShown(message.id);
    final attachment = message.voiceAttachment!;
    return MessageAction(
      key: const ValueKey('message-transcribe'),
      icon: Icons.subtitles_outlined,
      label: shown ? tr('Hide transcript') : tr('Transcribe'),
      onSelected: () => shown
          ? transcripts.hide(message.id)
          : unawaited(
              transcripts.show(
                TranscribeRequest.forMessage(
                  messageId: message.id,
                  conversationId: message.conversationId,
                  attachment: attachment,
                ),
              ),
            ),
    );
  }

  /// What can be done with this message, in menu order.
  List<MessageAction> _actions(BuildContext context) {
    // View-once media is neither previewed nor forwarded.
    final imageAttachment = _isRecalled || message.isViewOnce
        ? null
        : message.imageAttachment;
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
          message.type != MessageType.sticker &&
          message.liveLocationCard == null &&
          !message.isViewOnce)
        MessageAction(
          slot: MessageActionSlot.forward,
          icon: Icons.shortcut_rounded,
          label: tr('Forward'),
          onSelected: () => onForward(message),
        ),
      if (_canTranslate(context)) _translateAction(context),
      if (_canTranscribe) _transcribeAction(context),
      if (canCompose &&
          isCurrentUser &&
          message.type == MessageType.text &&
          message.locationCard == null &&
          message.liveLocationCard == null)
        MessageAction(
          icon: Icons.edit_outlined,
          label: tr('Edit'),
          onSelected: () => onEdit(message),
        ),
      if (canCompose && !_isRecalled && message.type != MessageType.system)
        MessageAction(
          key: const ValueKey('message-create-task'),
          icon: Icons.add_task_rounded,
          label: tr('Create task'),
          onSelected: () =>
              unawaited(showCreateTaskFromMessage(context, message)),
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
      if (onRemind case final remind? when !_isPending && !_isRecalled)
        MessageAction(
          key: const ValueKey('message-remind'),
          icon: Icons.alarm_add_outlined,
          label: tr('Remind me'),
          onSelected: () => unawaited(remind(message)),
        ),
      if (onToggleSaved case final toggle? when !_isPending && !_isRecalled)
        MessageAction(
          key: const ValueKey('message-save'),
          icon: isSaved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          label: isSaved ? tr('Remove from Saved') : tr('Save for later'),
          onSelected: () => unawaited(toggle(message)),
        ),
      if (!_isPending && !_isRecalled && message.type != MessageType.system)
        selectMessageAction(context, message),
      if (imageAttachment != null)
        MessageAction(
          icon: Icons.visibility_outlined,
          label: tr('Preview'),
          onSelected: () => unawaited(onPreviewImage(imageAttachment)),
        ),
      if (imageAttachment != null && !_isPending)
        MessageAction(
          key: const ValueKey('message-copy-image-text'),
          icon: Icons.document_scanner_outlined,
          label: tr('Copy text from picture'),
          onSelected: () => unawaited(
            showImageTextSheet(
              context,
              circleId: circleId,
              file: PreviewFile.fromImageAttachment(
                imageAttachment,
                messageId: message.id,
                conversationId: message.conversationId,
              ),
            ),
          ),
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
    if (PatInfo.maybeFromAttachment(message.attachment) case final pat?) {
      return PatLine(message: message, pat: pat);
    }
    if (AutoModAlert.maybeFromJson(message.attachment) case final alert?) {
      return AutoModAlertCard(alert: alert);
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

    content.add(MessageTaskChip(message: message));

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
    required this.onSchedule,
    required this.onPickImage,
    required this.onPickFile,
    required this.onCreatePoll,
    this.voiceButton,
    this.voicePanel,
    this.onCreateChain,
    this.onContactCard,
    this.onSendLocation,
    this.onShareLiveLocation,
    required this.onInsertTime,
    required this.onChangeWallpaper,
    this.onShowEvents,
    required this.onPickSticker,
    required this.onPickGif,
    required this.onInsertEmoji,
    required this.gifAvailable,
    required this.isRecordingVoice,
    required this.voiceSecondsLeft,
    required this.isSendingVoice,
    required this.onStartVoiceRecording,
    required this.onCancelVoiceRecording,
    required this.onSendVoiceRecording,
    required this.onCancelReply,
    required this.onCancelEdit,
    required this.availableHeight,
    this.attachmentTray,
    this.aiButton,
    this.scheduledBanner,
  });

  /// The AI rewrite button (see [AiComposerButton]); on phones it only
  /// shows once there is a draft.
  final Widget? aiButton;

  /// The tray of files waiting to be sent, above the composer pill.
  final Widget? attachmentTray;

  /// The strip counting this conversation's scheduled messages.
  final Widget? scheduledBanner;

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

  /// Schedules the text in the field for later (long-press or right-click
  /// on the send button).
  final Future<void> Function() onSchedule;
  final Future<void> Function() onPickImage;
  final Future<void> Function() onPickFile;
  final Future<void> Function() onCreatePoll;

  /// Voice input (speak to type): the button next to the emoji button, and
  /// the panel above the composer while it listens. Null where the platform
  /// can't dictate or the person switched it off.
  final Widget? voiceButton;
  final Widget? voicePanel;

  /// Starts a group chain (接龙); null in direct chats.
  final Future<void> Function()? onCreateChain;

  /// Sends a contact card (a friend or a circle); null leaves it out.
  final Future<void> Function()? onContactCard;

  /// Sends a place from the map; live location only where the chat can
  /// share it (direct chats and groups).
  final Future<void> Function()? onSendLocation;
  final Future<void> Function()? onShareLiveLocation;
  final Future<void> Function() onInsertTime;

  /// Opens this chat's wallpaper picker (in the + menu of wide screens, whose
  /// header has no More menu).
  final VoidCallback onChangeWallpaper;

  /// Lists this chat's events and plans new ones; null where chats take
  /// no events.
  final Future<void> Function()? onShowEvents;
  final Future<void> Function() onPickSticker;
  final Future<void> Function() onPickGif;
  final Future<void> Function() onInsertEmoji;

  /// False once the server said GIF search isn't set up.
  final bool gifAvailable;
  final bool isRecordingVoice;

  /// Seconds left of the recording in its last stretch; null before.
  final ValueListenable<int?> voiceSecondsLeft;
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
                  if (onCreateChain != null)
                    GlassMenuEntry(
                      key: const ValueKey('composer-chain-entry'),
                      icon: Icons.format_list_numbered_rounded,
                      label: tr('Chain'),
                      onSelected: () => unawaited(onCreateChain!()),
                    ),
                  if (onContactCard != null)
                    GlassMenuEntry(
                      key: const ValueKey('composer-contact-card-entry'),
                      icon: Icons.contact_page_outlined,
                      label: tr('Contact card'),
                      onSelected: () => unawaited(onContactCard!()),
                    ),
                  if (onSendLocation != null)
                    GlassMenuEntry(
                      key: const ValueKey('composer-location-entry'),
                      icon: Icons.location_on_outlined,
                      label: tr('Location'),
                      onSelected: () => unawaited(onSendLocation!()),
                    ),
                  if (onShareLiveLocation != null)
                    GlassMenuEntry(
                      key: const ValueKey('composer-live-location-entry'),
                      icon: Icons.near_me_outlined,
                      label: tr('Share live location'),
                      onSelected: () => unawaited(onShareLiveLocation!()),
                    ),
                  GlassMenuEntry(
                    key: const ValueKey('composer-schedule-entry'),
                    icon: Icons.schedule_send_outlined,
                    label: tr('Schedule message'),
                    onSelected: () => unawaited(onSchedule()),
                  ),
                  GlassMenuEntry(
                    icon: Icons.schedule_rounded,
                    label: tr('Insert time'),
                    onSelected: () => unawaited(onInsertTime()),
                  ),
                  if (onShowEvents != null)
                    GlassMenuEntry(
                      icon: Icons.event_outlined,
                      label: tr('Events'),
                      onSelected: () => unawaited(onShowEvents!()),
                    ),
                  if (!compact)
                    GlassMenuEntry(
                      key: const ValueKey('composer-wallpaper-entry'),
                      icon: Icons.wallpaper_outlined,
                      label: tr('Wallpaper'),
                      onSelected: onChangeWallpaper,
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
                // Not read out every second: it is a quiet visual cue.
                ExcludeSemantics(
                  child: ValueListenableBuilder<int?>(
                    valueListenable: voiceSecondsLeft,
                    builder: (context, left, _) => left == null
                        ? const SizedBox.shrink()
                        : Text(
                            key: const ValueKey('voice-seconds-left'),
                            tr('{seconds}s left', {'seconds': left}),
                            style: TextStyle(
                              fontSize: 13,
                              color: c.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
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
    void schedule() {
      WeCordHaptics.light();
      unawaited(onSchedule());
    }

    // Long-press (touch) or right-click schedules instead of sending;
    // screen readers get the long press as an action, and the attach menu
    // has an entry for keyboards.
    Widget sendButton() => GestureDetector(
      excludeFromSemantics: true,
      onSecondaryTap: isEditing || isBusy ? null : schedule,
      child: WeCordIconButton(
        key: const ValueKey('composer-send-button'),
        tooltip: isEditing ? tr('Save edit') : tr('Send'),
        icon: isEditing ? Icons.check_rounded : Icons.arrow_upward_rounded,
        size: buttonSize,
        iconSize: 22,
        variant: WeCordButtonVariant.accent,
        onLongPress: isEditing || isBusy ? null : schedule,
        onPressed: isBusy || isSlowed
            ? null
            : () {
                WeCordHaptics.light();
                unawaited(onSend());
              },
      ),
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
            ?voiceButton,
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
            // Voice input takes the GIF button's place on phones (GIFs stay
            // in the Attach menu).
            voiceButton ?? gif,
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
              ?scheduledBanner,
              ?voicePanel,
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
