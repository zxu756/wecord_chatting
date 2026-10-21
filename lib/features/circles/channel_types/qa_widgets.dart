import 'package:flutter/material.dart';
import 'package:wecord/features/circles/channel_types/qa_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Solved" on a question's card in a Q&A channel. Green, never red: a solved
/// question needs nobody.
class QaSolvedBadge extends StatelessWidget {
  const QaSolvedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final label = tr('Solved');
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Row(
          key: const ValueKey('qa-solved-badge'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: c.successText),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: c.successText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Accepted answer" under the answer the asker picked.
class QaAcceptedAnswerMark extends StatelessWidget {
  const QaAcceptedAnswerMark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final label = tr('Accepted answer');
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('qa-accepted-answer'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: ShapeDecoration(
            color: c.successSoft,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: c.successText),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: c.successText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// All / Unsolved / Solved above a Q&A channel's questions.
class QaStatusBar extends StatelessWidget {
  const QaStatusBar({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final QaStatusFilter selected;
  final ValueChanged<QaStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchInput(context);
    return SizedBox(
      height: touch ? 62 : 44,
      child: ListView(
        key: const ValueKey('qa-status-filters'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final status in QaStatusFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: WeCordChip(
                  key: ValueKey('qa-status-${status.value}'),
                  label: status.label,
                  height: 32,
                  selected: status == selected,
                  icon: status == selected ? Icons.check_rounded : null,
                  onPressed: () => onChanged(status),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
