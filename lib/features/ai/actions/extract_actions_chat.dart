// How "Extract to-dos" (roadmap F4) plugs into the chat page:
// [extractActionsSelectionButton] is a button of the selection bar (select
// messages, then "Extract to-dos"), registered in
// chats/selection/selection_registrations.dart. It opens
// [showExtractActionsSheet]; nothing is created until the person confirms each
// item there. (The message menu has no entry of its own: for one message
// "Create task" is already there, and the menu is long enough.)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wecord/features/ai/actions/extract_actions_sheet.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/selection/selection_registry.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// "To-dos" in the selection bar: reads the ticked messages for tasks and
/// events.
final extractActionsSelectionButton = SelectionBarContribution(
  id: 'extract-actions',
  order: 100,
  build: (ctx) {
    if (!ctx.container.read(aiAvailableProvider(null))) {
      return null;
    }
    final readable = [
      for (final message in ctx.messages)
        if (canExtractFrom(message)) message,
    ];
    final tooMany = readable.length > maxExtractMessages;
    return SelectionBarEntry(
      key: const ValueKey('selection-extract-actions'),
      icon: Icons.checklist_rounded,
      label: tr('Extract to-dos'),
      hint: tooMany
          ? tr('Pick up to {count} messages.', {'count': maxExtractMessages})
          : null,
      onPressed: readable.isEmpty || tooMany
          ? null
          : () => unawaited(() async {
              final created = await showExtractActionsSheet(
                ctx.context,
                conversationId: ctx.environment.conversationId,
                messages: readable,
              );
              if (created == true) {
                ctx.leaveSelection();
              }
            }()),
    );
  },
);
