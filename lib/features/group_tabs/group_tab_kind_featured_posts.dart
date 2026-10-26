// The circle's featured posts (B8) as a kind of tab: opens the posts the
// moderators marked as 精华. Needs a circle channel (a group chat has no
// circle). Registered in group_tab_kinds_registrations.dart.
import 'package:flutter/material.dart';
import 'package:wecord/features/chats/conversation_navigation.dart'
    show openPage;
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

final featuredPostsGroupTabKind = GroupTabKindContribution(
  kind: GroupTabKinds.featuredPosts,
  order: 660,
  label: () => tr('Featured posts'),
  icon: Icons.star_outline_rounded,
  defaultTitle: () => tr('Featured posts'),
  canAdd: (ctx) => ctx.circleId != null,
  open: (ctx, tab) {
    final circleId = tab.circleId ?? ctx.circleId;
    if (circleId != null) {
      openPage(ctx.context, circlePostsPath(circleId, featured: true));
    }
  },
);
