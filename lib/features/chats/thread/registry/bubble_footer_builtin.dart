// The footer slot's own entries.
//
// Inside the bubble, after the content: 100 task chip, 200 "edited",
// 300 "published". Under the bubble: 100 link preview, 200 thread chip,
// 300 reactions, 400 disappearing mark, 500 review mark, 600 read receipt.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wecord/features/chats/disappearing_messages.dart';
import 'package:wecord/features/chats/link_preview_card.dart';
import 'package:wecord/features/chats/message_reactions.dart';
import 'package:wecord/features/chats/message_review_mark.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/thread/footer_widgets.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/circles/announcement_widgets.dart';
import 'package:wecord/features/workspace/workspace_cards.dart';
import 'package:wecord/shared/models/message.dart';

/// The built-in entries.
const List<BubbleFooterEntry> builtInBubbleFooterEntries = [
  // ---- inside the bubble ----
  BubbleFooterEntry.inside(id: 'task-chip', order: 100, build: _taskChip),
  BubbleFooterEntry.inside(id: 'edited', order: 200, build: _edited),
  BubbleFooterEntry.inside(id: 'published', order: 300, build: _published),
  // ---- under the bubble ----
  BubbleFooterEntry.below(
    id: 'link-preview',
    order: 100,
    build: _linkPreview,
    cardGap: 8,
    cardMaxWidth: 440,
  ),
  BubbleFooterEntry.below(id: 'thread-chip', order: 200, build: _threadChip),
  BubbleFooterEntry.below(id: 'reactions', order: 300, build: _reactions),
  BubbleFooterEntry.below(
    id: 'disappearing',
    order: 400,
    build: _disappearing,
    wrap: BubbleFooterWrap.pill,
    cardGap: 4,
  ),
  BubbleFooterEntry.below(
    id: 'review',
    order: 500,
    build: _review,
    wrap: BubbleFooterWrap.pill,
    cardGap: 4,
  ),
  BubbleFooterEntry.below(
    id: 'read-receipt',
    order: 600,
    build: _readReceipt,
    wrap: BubbleFooterWrap.receipt,
    cardGap: 4,
  ),
];

Iterable<Widget> _taskChip(BubbleFooterContext ctx) => [
  MessageTaskChip(message: ctx.message),
];

Iterable<Widget> _edited(BubbleFooterContext ctx) => [
  if (ctx.message.editedAt != null) ...[
    const SizedBox(height: 2),
    EditedMarker(color: ctx.textColor.withValues(alpha: 0.55)),
  ],
];

Iterable<Widget> _published(BubbleFooterContext ctx) => [
  if (ctx.message.isPublished) PublishedMarker(foregroundColor: ctx.textColor),
];

Widget? _linkPreview(BubbleFooterContext ctx) {
  final url = ctx.previewUrl;
  return url == null ? null : MessageLinkPreviewCard(url: url, bottomGap: 0);
}

Widget? _threadChip(BubbleFooterContext ctx) {
  final thread = ctx.message.threadSummary;
  final open = ctx.onOpenThread;
  if (thread == null || open == null) {
    return null;
  }
  return ThreadChip(
    messageId: ctx.message.id,
    summary: thread,
    onTap: () => unawaited(open(ctx.message)),
  );
}

Widget? _reactions(BubbleFooterContext ctx) {
  final reactions = ctx.isRecalled
      ? const <MessageReaction>[]
      : ctx.message.reactions;
  if (reactions.isEmpty) {
    return null;
  }
  return MessageReactionChips(
    reactions: ctx.message.reactions,
    onToggle: (emoji) => unawaited(ctx.onToggleReaction(ctx.message, emoji)),
    onShowReactors: (reaction) => ctx.onShowReactors(ctx.message, reaction),
  );
}

Widget? _disappearing(BubbleFooterContext ctx) {
  final expiresAt = ctx.message.expiresAt;
  if (expiresAt == null || ctx.isRecalled) {
    return null;
  }
  return DisappearingMark(expiresAt: expiresAt);
}

Widget? _review(BubbleFooterContext ctx) {
  final state = ctx.message.reviewState;
  if (state == null) {
    return null;
  }
  return MessageReviewMark(state: state, isOwn: ctx.isCurrentUser);
}

Widget? _readReceipt(BubbleFooterContext ctx) =>
    ctx.showReadReceipt ? const ChatReadReceipt() : null;
