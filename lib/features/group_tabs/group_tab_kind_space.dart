// The group space (B6) as a kind of tab: opens the space of the group. Groups
// only (a circle channel has no group space), so it can only be added where
// there is no circle. Registered in group_tab_kinds_registrations.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/group_space/group_space_screen.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';

final spaceGroupTabKind = GroupTabKindContribution(
  kind: GroupTabKinds.space,
  order: 650,
  label: () => tr('Group space'),
  icon: Icons.folder_special_outlined,
  defaultTitle: () => tr('Group space'),
  canAdd: (ctx) => ctx.circleId == null,
  open: (ctx, tab) =>
      unawaited(ctx.context.push(GroupSpaceScreen.pathFor(ctx.conversationId))),
);
