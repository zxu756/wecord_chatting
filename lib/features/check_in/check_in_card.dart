import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/check_in/check_in_actions.dart';
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_page.dart';
import 'package:wecord/features/check_in/check_in_repository.dart';
import 'package:wecord/features/check_in/check_in_widgets.dart';
import 'package:wecord/features/forms/form_widgets.dart' show FormBar;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A check-in in a chat, in the "well" style of chains, forms and polls: the
/// title, "Today 18/30", the caller's own run and a Check in button. It
/// follows the check-in live (no message per check-in); tapping it opens the
/// page with today's list.
class CheckInCardView extends ConsumerWidget {
  const CheckInCardView({required this.card, super.key});

  final CheckInCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final async = ref.watch(checkInProvider(card.checkInId));
    final check = async.value;
    final title = check?.title.isNotEmpty == true ? check!.title : card.title;

    void open() => unawaited(openCheckIn(context, checkInId: card.checkInId));

    Widget body() {
      if (check == null) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: async.hasError
              ? WeCordPressable(
                  onPressed: () =>
                      ref.invalidate(checkInProvider(card.checkInId)),
                  semanticLabel: tr('Try again'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  ),
                  builder: (context, states) => Text(
                    tr("Couldn't load this check-in. Tap to try again."),
                    style: TextStyle(fontSize: 13.5, color: c.muted),
                  ),
                )
              : Text(
                  tr('Loading…'),
                  style: TextStyle(fontSize: 13.5, color: c.muted),
                ),
        );
      }
      final Widget action;
      if (check.closed) {
        action = const SizedBox.shrink();
      } else if (check.myCheckedIn) {
        action = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: c.successText),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                tr('Checked in today'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: c.successText,
                ),
              ),
            ),
          ],
        );
      } else {
        action = WeCordButton(
          key: ValueKey('check-in-do-${card.checkInId}'),
          label: tr('Check in'),
          variant: WeCordButtonVariant.accent,
          size: WeCordButtonSize.small,
          onPressed: () => unawaited(quickCheckIn(context, ref, check)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (check.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                check.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, height: 1.35, color: c.muted),
              ),
            ),
          const SizedBox(height: 10),
          FormBar(fraction: check.todayFraction),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  checkInTodayText(check),
                  key: ValueKey('check-in-count-${card.checkInId}'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                checkInMyStreakText(check),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: check.myStreak > 0
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: check.myStreak > 0 ? c.successText : c.subtle,
                ),
              ),
              action,
            ],
          ),
        ],
      );
    }

    final summary = check == null
        ? title
        : [
            title,
            checkInTodayText(check),
            if (check.closed) tr('Closed') else checkInMyStreakText(check),
            if (check.myCheckedIn && !check.closed) tr('Checked in today'),
          ].join(', ');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, minWidth: 240),
      child: WeCordPressable(
        key: ValueKey('check-in-card-${card.checkInId}'),
        onPressed: check == null ? null : open,
        semanticLabel: tr('Daily check-in: {summary}', {'summary': summary}),
        hint: tr('Opens the check-in'),
        mergeSemantics: false,
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(
              color: states.contains(WidgetState.hovered) ? c.line : c.lineSoft,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CheckInIconTile(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Daily check-in'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.subtle,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (check?.closed ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CheckInPill(text: tr('Closed'), closed: true),
                  ),
                ),
              body(),
            ],
          ),
        ),
      ),
    );
  }
}
