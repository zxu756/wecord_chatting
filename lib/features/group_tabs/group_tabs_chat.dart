// How group tabs plug into the chat page: the "Tabs" entry of the thread
// header's More menu (registered in header_actions_registrations.dart). The
// strip itself is drawn under the header by GroupTabStrip (group_tab_strip.dart,
// placed in thread/build_header.dart with the other strips).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/group_tabs/group_tabs_sheet.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "Tabs" in the More menu of groups and circle channels, after Summarize
/// (1200) and before the parent's own actions (1500). Phones open the list
/// from here; the strip under the header opens the tabs themselves.
final groupTabsHeaderAction = HeaderActionContribution(
  id: 'group-tabs',
  order: 1300,
  build: (ctx) =>
      (ctx.isGroup || ctx.isChannel) &&
          ctx.threadId == null &&
          !ctx.forumPost &&
          !ctx.isNoteToSelf
      ? ChatThreadAction(
          id: 'group-tabs',
          tooltip: tr('Tabs'),
          icon: Icons.tab_outlined,
          menuOnly: true,
          onPressed: () => unawaited(
            showGroupTabsSheet(
              ctx.context,
              conversationId: ctx.conversationId,
              title: ctx.title,
              circleId: ctx.circleId,
              canSend: ctx.canSend,
            ),
          ),
        )
      : null,
);
