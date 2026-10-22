// Where kinds of group tab are registered.
//
// To add a kind (the group space of B6, a poll ...), write a
// `GroupTabKindContribution` in your feature's own file and add it to
// [groupTabKindExtensions] with one line. Its kind must also be a row of
// `conversation_tab_kinds` on the server ('space' already is; any other kind
// needs one `insert` in the package's migration, with target_type 'none' for a
// kind with no target).
//
// Group space (B6), once 8-2 is merged:
//   1. in that package, write
//        final spaceGroupTabKind = GroupTabKindContribution(
//          kind: GroupTabKinds.space, order: 650, label: () => tr('Space'),
//          icon: Icons.photo_library_outlined,
//          defaultTitle: () => tr('Space'),
//          open: (ctx, tab) => openGroupSpace(ctx.context, ctx.conversationId),
//        );
//   2. add `spaceGroupTabKind` to the list below.
// Nothing here imports that package; until it is merged a 'space' tab (none
// can be added) is simply left out of the strip.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds_builtin.dart';

/// Feature contributions to the kinds of tab. Append yours here.
final List<GroupTabKindContribution> groupTabKindExtensions = [
  // spaceGroupTabKind,
];

/// The kinds the app can open. Tests can override it.
final groupTabKindRegistryProvider = Provider<GroupTabKindRegistry>(
  (ref) => GroupTabKindRegistry([
    ...builtInGroupTabKinds,
    ...groupTabKindExtensions,
  ]),
);
