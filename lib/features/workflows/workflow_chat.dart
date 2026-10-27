// How workflows plug into the chat page: the "Workflows" entry of a group
// chat's More menu for its owner and admins (registered in
// header_actions_registrations.dart). Circles open theirs from the circle
// settings.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/workflows/workflow_list_page.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Workflows" in the More menu of a group chat the person manages, after
/// Tabs (1300) and before the parent's own actions (1500).
final workflowHeaderAction = HeaderActionContribution(
  id: 'workflows',
  order: 1350,
  build: (ctx) =>
      ctx.isGroup &&
          ctx.threadId == null &&
          !ctx.forumPost &&
          ctx.groupDetail?.canManageGroup == true
      ? ChatThreadAction(
          id: 'workflows',
          tooltip: tr('Workflows'),
          icon: Icons.bolt_rounded,
          menuOnly: true,
          onPressed: () => unawaited(
            openWorkflows(ctx.context, WorkflowScope.group(ctx.conversationId)),
          ),
        )
      : null,
);
