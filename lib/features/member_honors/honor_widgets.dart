import 'package:flutter/material.dart';
import 'package:wecord/features/member_honors/honor_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A member's title next to their name: a small blue tag with the words a
/// moderator chose. The circle tag (a global badge) is green and comes after
/// it; the name's own color belongs to the member's role.
class MemberTitleChip extends StatelessWidget {
  const MemberTitleChip({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      label: tr('Title: {title}', {'title': title}),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(WeCordRadii.xs),
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.accentText,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// The honors of a member that may be shown to others: a flame for a streak
/// milestone and a trophy for last week's level. Only icons and a tooltip,
/// never a count of days.
class MemberHonorBadge extends StatelessWidget {
  const MemberHonorBadge({required this.flair, super.key});

  final MemberFlair flair;

  @override
  Widget build(BuildContext context) {
    if (!flair.hasHonor) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final label = flairHonorLabel(flair);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          key: ValueKey('honor-badge-${flair.userId}'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
          decoration: BoxDecoration(
            color: c.warningSoft,
            borderRadius: BorderRadius.circular(WeCordRadii.xs),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (flair.streakLevel != null)
                Icon(
                  Icons.local_fire_department,
                  size: 11,
                  color: c.warningText,
                ),
              if (flair.weeklyLevel != null)
                Icon(Icons.emoji_events, size: 11, color: c.warningText),
            ],
          ),
        ),
      ),
    );
  }
}
