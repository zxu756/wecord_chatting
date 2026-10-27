// Where kinds of group tab are registered.
//
// To add a kind (the group space of B6, a poll ...), write a
// `GroupTabKindContribution` in your feature's own file and add it to
// [groupTabKindExtensions] with one line. Its kind must also be a row of
// `conversation_tab_kinds` on the server ('space' already is; any other kind
// needs one `insert` in the package's migration, with target_type 'none' for a
// kind with no target).
//
// Group space (B6): `spaceGroupTabKind` (group_tab_kind_space.dart) opens the
// space of the group and is listed below.
// Featured posts (B8): `featuredPostsGroupTabKind`
// (group_tab_kind_featured_posts.dart) opens a circle's featured posts.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_kind_featured_posts.dart';
import 'package:wecord/features/group_tabs/group_tab_kind_space.dart';
import 'package:wecord/features/group_tabs/group_tab_kind_whiteboard.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds_builtin.dart';

/// Feature contributions to the kinds of tab. Append yours here.
final List<GroupTabKindContribution> groupTabKindExtensions = [
  spaceGroupTabKind,
  featuredPostsGroupTabKind,
  whiteboardGroupTabKind,
];

/// The kinds the app can open. Tests can override it.
final groupTabKindRegistryProvider = Provider<GroupTabKindRegistry>(
  (ref) => GroupTabKindRegistry([
    ...builtInGroupTabKinds,
    ...groupTabKindExtensions,
  ]),
);
