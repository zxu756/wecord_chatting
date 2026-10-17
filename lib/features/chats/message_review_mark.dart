import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The quiet line under a message that the circle's AI guard is checking or
/// holds back: "Checking…" while the AI looks, "Held for review" once it
/// flagged the message. Only the author and moderators ever see these
/// messages; when the message is released the line is simply gone.
class MessageReviewMark extends StatelessWidget {
  const MessageReviewMark({
    required this.state,
    required this.isOwn,
    super.key,
  });

  final MessageReviewState state;

  /// Whether the viewer wrote the message (a moderator sees the same state
  /// on other people's messages).
  final bool isOwn;

  /// What the line says.
  String get label => switch (state) {
    MessageReviewState.checking => tr('Checking…'),
    MessageReviewState.held => tr('Held for review'),
    MessageReviewState.removed =>
      isOwn ? tr('Removed by a moderator') : tr('Removed'),
  };

  /// What a screen reader adds: who can see the message.
  String get hint => switch (state) {
    MessageReviewState.checking => tr(
      'Only you and moderators can see this until it is checked.',
    ),
    MessageReviewState.held =>
      isOwn
          ? tr(
              'Only you and moderators can see this until a moderator approves.',
            )
          : tr('Only moderators and its author can see this.'),
    MessageReviewState.removed => tr('Only you and moderators can see this.'),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tint = state == MessageReviewState.checking
        ? c.subtle
        : c.warningText;
    return Semantics(
      container: true,
      label: label,
      hint: hint,
      child: ExcludeSemantics(
        child: Row(
          key: ValueKey('message-review-${state.name}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (state) {
                MessageReviewState.checking => Icons.schedule_rounded,
                MessageReviewState.held => Icons.shield_outlined,
                MessageReviewState.removed => Icons.delete_outline_rounded,
              },
              size: 12,
              color: tint,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
