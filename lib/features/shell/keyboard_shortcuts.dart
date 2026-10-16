import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_shortcuts.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/shell/quick_switcher.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

/// An app-wide shortcut.
enum AppShortcut { quickSwitcher, shortcutsHelp, previous, next, focusComposer }

/// Whether Cmd (rather than Ctrl) is the shortcut key here.
bool get usesCommandKey =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// The app-wide shortcut [event] triggers, given the modifiers held. Ctrl
/// and Cmd both work, so a Mac keyboard on another system still does.
AppShortcut? appShortcutFor(
  KeyEvent event, {
  required bool control,
  required bool meta,
  required bool alt,
  required bool shift,
}) {
  if (event is! KeyDownEvent) {
    return null;
  }
  final key = event.logicalKey;
  final primary = control || meta;
  if (primary && !alt && key == LogicalKeyboardKey.keyK) {
    return AppShortcut.quickSwitcher;
  }
  if (primary && !alt && key == LogicalKeyboardKey.slash) {
    return AppShortcut.shortcutsHelp;
  }
  // Past a long message list, straight to the message box.
  if (primary && !alt && !shift && key == LogicalKeyboardKey.keyJ) {
    return AppShortcut.focusComposer;
  }
  if (alt && !primary && !shift) {
    if (key == LogicalKeyboardKey.arrowUp) {
      return AppShortcut.previous;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return AppShortcut.next;
    }
  }
  return null;
}

/// The conversations Alt+Up / Alt+Down step through from [activeId]: the
/// circle's channels in sidebar order, or the direct messages.
({List<ConversationSummary> list, int index}) adjacentConversations({
  required String? activeId,
  required List<ConversationSummary> conversations,
  CircleDetail? circle,
}) {
  final active = conversations
      .where((conversation) => conversation.id == activeId)
      .firstOrNull;
  // A thread steps from its channel.
  final anchorId = active?.isThread == true
      ? active!.parentConversationId
      : activeId;
  if (circle != null) {
    final layout = CircleChannelLayout.fromChannels(
      categories: circle.categories,
      channels: circle.channels,
    );
    final channels = [
      for (final channel in [
        ...layout.uncategorized,
        for (final category in layout.categories)
          ...layout.channelsIn(category.id),
      ])
        if (!channel.isVoice)
          ConversationSummary(
            id: channel.conversationId,
            type: ConversationType.channel,
            unreadCount: 0,
            title: channel.name,
            circleId: channel.circleId,
          ),
    ];
    return (
      list: channels,
      index: channels.indexWhere((channel) => channel.id == anchorId),
    );
  }
  final directMessages = [
    for (final conversation in conversations)
      if (conversation.isDirectMessage) conversation,
  ];
  return (
    list: directMessages,
    index: directMessages.indexWhere(
      (conversation) => conversation.id == anchorId,
    ),
  );
}

/// Listens for the app-wide shortcuts while the signed-in app is on
/// screen: Ctrl/Cmd+K quick switcher, Ctrl/Cmd+/ the list of shortcuts and
/// Alt+Up / Alt+Down the previous or next channel or conversation.
class AppKeyboardShortcuts extends ConsumerStatefulWidget {
  const AppKeyboardShortcuts({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppKeyboardShortcuts> createState() =>
      _AppKeyboardShortcutsState();
}

class _AppKeyboardShortcutsState extends ConsumerState<AppKeyboardShortcuts> {
  var _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (!mounted || _dialogOpen) {
      return false;
    }
    // Not over sheets, dialogs or pages pushed above the app frame.
    if (ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final shortcut = appShortcutFor(
      event,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
    );
    switch (shortcut) {
      case AppShortcut.quickSwitcher:
        unawaited(_whileDialogOpen(() => showQuickSwitcher(context)));
      case AppShortcut.shortcutsHelp:
        unawaited(_whileDialogOpen(() => showKeyboardShortcutsHelp(context)));
      case AppShortcut.previous:
        unawaited(_step(-1));
      case AppShortcut.next:
        unawaited(_step(1));
      case AppShortcut.focusComposer:
        // Without a chat open the key goes on to whatever has focus.
        return ComposerFocusRegistry.focus();
      case null:
        return false;
    }
    return true;
  }

  Future<void> _whileDialogOpen(Future<void> Function() show) async {
    _dialogOpen = true;
    try {
      await show();
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _step(int step) async {
    final uri = GoRouter.of(context).routerDelegate.currentConfiguration.uri;
    final activeId =
        ref.read(activeConversationIdProvider) ?? uri.queryParameters['c'];
    final conversations =
        ref.read(conversationsProvider).value ?? const <ConversationSummary>[];
    final active = conversations
        .where((conversation) => conversation.id == activeId)
        .firstOrNull;
    final segments = uri.pathSegments;
    final circleId =
        active?.circleId ??
        (segments.length >= 2 && '/${segments.first}' == CircleRoutes.path
            ? segments[1]
            : null);
    CircleDetail? circle;
    if (circleId != null) {
      try {
        circle = await ref.read(circleDetailProvider(circleId).future);
      } catch (_) {
        return;
      }
    }
    final (:list, :index) = adjacentConversations(
      activeId: activeId,
      conversations: conversations,
      circle: circle,
    );
    if (list.isEmpty || !mounted) {
      return;
    }
    final target = index < 0 ? (step > 0 ? 0 : list.length - 1) : index + step;
    if (target < 0 || target >= list.length) {
      return;
    }
    openConversation(context, list[target]);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The keys of a shortcut, as shown in the help.
List<String> _keys(AppShortcut? shortcut, {String? single}) {
  final primary = usesCommandKey ? 'Cmd' : 'Ctrl';
  final alt = usesCommandKey ? 'Option' : 'Alt';
  return switch (shortcut) {
    AppShortcut.quickSwitcher => [primary, 'K'],
    AppShortcut.shortcutsHelp => [primary, '/'],
    AppShortcut.previous => [alt, '↑'],
    AppShortcut.next => [alt, '↓'],
    AppShortcut.focusComposer => [primary, 'J'],
    null => [?single],
  };
}

/// The keyboard shortcuts with their keys, for the help and settings.
List<(List<String>, String)> keyboardShortcutRows() {
  return <(List<String>, String)>[
    (_keys(AppShortcut.quickSwitcher), tr('Find or jump to a conversation')),
    (_keys(AppShortcut.previous), tr('Previous channel or conversation')),
    (_keys(AppShortcut.next), tr('Next channel or conversation')),
    (
      _keys(null, single: 'Esc'),
      tr('Cancel a reply or edit, or mark the conversation read'),
    ),
    (
      _keys(null, single: '↑'),
      tr('Edit your last message (in an empty message field)'),
    ),
    (_keys(AppShortcut.focusComposer), tr('Jump to the message box')),
    (['Shift', 'F10'], tr('Open the menu of the message in focus')),
    (_keys(AppShortcut.shortcutsHelp), tr('Show keyboard shortcuts')),
  ];
}

/// Lists the keyboard shortcuts.
Future<void> showKeyboardShortcutsHelp(BuildContext context) {
  final rows = keyboardShortcutRows();
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        key: const ValueKey('keyboard-shortcuts'),
        scrollable: true,
        title: Text(tr('Keyboard shortcuts')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (keys, label) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.tokens.colors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      for (final (index, key) in keys.indexed) ...[
                        if (index > 0) const SizedBox(width: 4),
                        _KeyCap(key),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          WeCordButton(
            label: tr('Close'),
            variant: WeCordButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.xs),
        border: Border.all(color: c.line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.ink,
        ),
      ),
    );
  }
}
