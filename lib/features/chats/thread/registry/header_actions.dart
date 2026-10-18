// Extension point 4 of the chat page: the header's action buttons and its
// More menu.
//
// Every button in the thread header is a [ChatThreadAction]. The header shows
// the ones marked [ChatThreadAction.primary] as buttons on wide screens and
// puts every other action in its More menu; phones show search, one primary
// action and More. A feature adds an action by writing a
// [HeaderActionContribution] in its own file and listing it in
// `header_actions_registrations.dart`. See "Chat page extension points" in
// docs/design/wecord-design-language.md.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';

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
    this.id,
  });

  /// A stable name, e.g. `search`. The page looks a few actions up by it
  /// (search moves into the header on wide screens, and phones pick one
  /// primary action).
  final String? id;

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

/// What the page does for the built-in actions. A new feature does not need
/// these: it opens its own sheet or route from [HeaderActionContext.context].
class HeaderActionHost {
  const HeaderActionHost({
    required this.toggleMessageSearch,
    required this.showPinnedMessages,
    required this.showGroupDetails,
    required this.setThreadArchived,
    required this.requestSummary,
    required this.openDisappearing,
    required this.openWallpaper,
  });

  final VoidCallback toggleMessageSearch;
  final void Function(bool canManagePins) showPinnedMessages;
  final void Function(String title) showGroupDetails;
  final void Function(String threadId, bool archived) setThreadArchived;
  final VoidCallback requestSummary;
  final VoidCallback openDisappearing;
  final VoidCallback openWallpaper;
}

/// What a contribution can look at when the header is built.
class HeaderActionContext {
  const HeaderActionContext({
    required this.context,
    required this.ref,
    required this.host,
    required this.conversationId,
    required this.title,
    required this.conversationType,
    required this.circleId,
    required this.isNoteToSelf,
    required this.isDirectOrGroup,
    required this.canCall,
    required this.canSend,
    required this.canPinMessages,
    required this.groupDetail,
    required this.disappearingSeconds,
    required this.threadId,
    required this.canManageThread,
    required this.threadArchived,
    required this.forumPost,
    required this.workspaceOpen,
    required this.workspaceRequest,
    required this.desktopChrome,
  });

  /// The page's context, for navigation. Use [ref] to watch providers: the
  /// contributions run inside the page's build.
  final BuildContext context;
  final WidgetRef ref;
  final HeaderActionHost host;
  final String conversationId;
  final String title;
  final ConversationType? conversationType;
  final String? circleId;
  final bool isNoteToSelf;

  /// A direct chat or a group (not a channel or a thread).
  final bool isDirectOrGroup;

  /// Calls and events apply: a direct chat or a group that is not the note
  /// to self.
  final bool canCall;
  final bool canSend;
  final bool canPinMessages;
  final GroupDetail? groupDetail;
  final int? disappearingSeconds;
  final String? threadId;
  final bool canManageThread;
  final bool threadArchived;

  /// The page is a forum post.
  final bool forumPost;
  final bool workspaceOpen;
  final WorkspaceRequest? workspaceRequest;

  /// The desktop header (wide screens), which has room for more buttons.
  final bool desktopChrome;

  bool get isDirect => conversationType == ConversationType.direct;
  bool get isGroup => conversationType == ConversationType.group;
  bool get isChannel => conversationType == ConversationType.channel;
}

/// One feature's action in the header.
class HeaderActionContribution {
  const HeaderActionContribution({
    required this.id,
    required this.order,
    required this.build,
  });

  /// Unique and stable, e.g. `search` or `group-details`.
  final String id;

  /// Where the action sits among the others, ascending. The built-in actions
  /// use 100, 200, ...; the page's own extra actions (circles pass theirs)
  /// come at [HeaderActionRegistry.extraActionsOrder], so anything above that
  /// goes after them.
  final int order;

  /// The action, or null when it does not apply to this chat.
  final ChatThreadAction? Function(HeaderActionContext ctx) build;
}

/// The header's actions, collected in `order`.
class HeaderActionRegistry {
  HeaderActionRegistry(Iterable<HeaderActionContribution> contributions)
    : _contributions = _sorted(contributions);

  /// The position of the actions a parent passes to the page
  /// (`ChatThreadScreen.extraActions`): after the built-in ones, before the
  /// events button.
  static const extraActionsOrder = 1500;

  final List<HeaderActionContribution> _contributions;

  /// Every action for [ctx], with [extras] where the parent's own go.
  List<ChatThreadAction> actionsFor(
    HeaderActionContext ctx, {
    List<ChatThreadAction> extras = const [],
  }) {
    final before = <ChatThreadAction>[];
    final after = <ChatThreadAction>[];
    for (final contribution in _contributions) {
      final action = contribution.build(ctx);
      if (action == null) {
        continue;
      }
      (contribution.order < extraActionsOrder ? before : after).add(action);
    }
    return [...before, ...extras, ...after];
  }

  /// The ids in order (for tests).
  List<String> get ids => [for (final c in _contributions) c.id];

  static List<HeaderActionContribution> _sorted(
    Iterable<HeaderActionContribution> contributions,
  ) {
    final list = contributions.toList();
    assert(
      list.map((c) => c.id).toSet().length == list.length,
      'Two header action contributions share an id',
    );
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byOrder = a.$2.order.compareTo(b.$2.order);
        return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
      });
    return [for (final (_, contribution) in indexed) contribution];
  }
}
