import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Ask members to confirm" in a group's details: while on, the announcement
/// shows "12/30 confirmed" and every member gets a Confirm button.
class AnnouncementAckToggle extends StatelessWidget {
  const AnnouncementAckToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SettingsGroup(
      color: c.well,
      children: [
        SettingsRow.toggle(
          key: const ValueKey('announcement-requires-ack'),
          icon: Icons.fact_check_outlined,
          title: tr('Ask members to confirm'),
          subtitle: tr(
            'Members tap Confirm; you see who has. Changing the announcement asks again.',
          ),
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Words for a refused call.
String announcementAckProblemText(Object error) {
  final problem = error is UrgentException
      ? error.problem
      : UrgentProblem.other;
  return switch (problem) {
    UrgentProblem.emptyAnnouncement => tr(
      'Write an announcement before asking for confirmations.',
    ),
    UrgentProblem.rateLimited => tr(
      'You reminded the group a short while ago. Try again later.',
    ),
    UrgentProblem.nobodyToRemind => tr('Everyone has confirmed.'),
    UrgentProblem.unavailable => tr('You can not do this in this group.'),
    _ => tr('Something went wrong. Try again.'),
  };
}

/// Under the announcement at the top of a group: "Confirmed 12/30", a
/// Confirm button for who has not, and "Details" for the owner and admins.
/// Nothing when the announcement does not ask for a confirmation.
class AnnouncementAckBar extends ConsumerStatefulWidget {
  const AnnouncementAckBar({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<AnnouncementAckBar> createState() => _AnnouncementAckBarState();
}

class _AnnouncementAckBarState extends ConsumerState<AnnouncementAckBar> {
  var _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(urgentRepositoryProvider)
          .acknowledgeAnnouncement(widget.conversationId);
      ref
        ..invalidate(announcementAckStateProvider(widget.conversationId))
        ..invalidate(pendingAnnouncementAcksProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(announcementAckProblemText(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref
        .watch(announcementAckStateProvider(widget.conversationId))
        .value;
    if (state == null || !state.requiresAck) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    return Padding(
      key: const ValueKey('announcement-ack-bar'),
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            tr('Confirmed {acked}/{total}', {
              'acked': state.acked,
              'total': state.total,
            }),
            key: const ValueKey('announcement-ack-count'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.accentText,
            ),
          ),
          if (state.iAcked)
            Text(
              tr('You confirmed'),
              style: TextStyle(fontSize: 13, color: c.ink),
            )
          else
            WeCordButton(
              key: const ValueKey('announcement-ack-confirm'),
              label: tr('Confirm'),
              size: WeCordButtonSize.small,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_confirm()),
            ),
          if (state.canManage)
            WeCordButton(
              key: const ValueKey('announcement-ack-details'),
              label: tr('Who confirmed'),
              size: WeCordButtonSize.small,
              variant: WeCordButtonVariant.secondary,
              onPressed: () => unawaited(
                showAnnouncementAckSheet(context, widget.conversationId),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the owner's list: who confirmed, who did not, and "Remind the ones
/// who have not".
Future<void> showAnnouncementAckSheet(
  BuildContext context,
  String conversationId,
) {
  return showWeCordSheet<void>(
    context,
    title: tr('Confirmations'),
    builder: (context, _) =>
        AnnouncementAckSheet(conversationId: conversationId),
  );
}

/// The content of the confirmations sheet.
class AnnouncementAckSheet extends ConsumerStatefulWidget {
  const AnnouncementAckSheet({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<AnnouncementAckSheet> createState() =>
      _AnnouncementAckSheetState();
}

class _AnnouncementAckSheetState extends ConsumerState<AnnouncementAckSheet> {
  var _showConfirmed = false;
  var _reminding = false;
  var _reminded = false;

  Future<void> _remind() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _reminding = true);
    try {
      final asked = await ref
          .read(urgentRepositoryProvider)
          .remindUnconfirmed(widget.conversationId);
      ref.invalidate(announcementAckStateProvider(widget.conversationId));
      if (!mounted) {
        return;
      }
      setState(() => _reminded = true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            asked == 1
                ? tr('Reminded 1 person')
                : tr('Reminded {count} people', {'count': asked}),
          ),
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(announcementAckProblemText(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _reminding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final members = ref.watch(
      announcementAckMembersProvider(widget.conversationId),
    );
    final state =
        ref.watch(announcementAckStateProvider(widget.conversationId)).value ??
        AnnouncementAckState.none;
    final localizations = MaterialLocalizations.of(context);
    final next = state.nextReminderAt;
    final tooSoon = next != null && next.isAfter(clock.now());
    final canRemind = !_reminded && !tooSoon && state.waiting > 0;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: members.when(
          loading: () => const SheetSpinner(),
          error: (error, stackTrace) => SheetNote(
            text: tr('Could not load the confirmations.'),
            error: true,
          ),
          data: (all) {
            final confirmed = [
              for (final m in all)
                if (m.confirmed) m,
            ];
            final waiting = [
              for (final m in all)
                if (!m.confirmed) m,
            ];
            final shown = _showConfirmed ? confirmed : waiting;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      WeCordSegmented<bool>(
                        semanticLabel: tr('Confirmations'),
                        expand: true,
                        selected: _showConfirmed,
                        onChanged: (value) =>
                            setState(() => _showConfirmed = value),
                        segments: [
                          WeCordSegment(
                            key: const ValueKey('ack-tab-waiting'),
                            value: false,
                            label: '${tr('Waiting')} ${waiting.length}',
                          ),
                          WeCordSegment(
                            key: const ValueKey('ack-tab-confirmed'),
                            value: true,
                            label: '${tr('Confirmed')} ${confirmed.length}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 14,
                          ),
                          child: Text(
                            _showConfirmed
                                ? tr('Nobody has confirmed yet.')
                                : tr('Everyone has confirmed.'),
                            style: TextStyle(fontSize: 13.5, color: c.subtle),
                          ),
                        ),
                      for (final member in shown)
                        SheetListRow(
                          key: ValueKey('ack-member-${member.userId}'),
                          leading: ProfileAvatar(
                            name: member.name,
                            avatarUrl: member.avatarUrl,
                            size: 40,
                          ),
                          title: member.name,
                          trailing: member.ackedAt == null
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    describeWhen(
                                      localizations,
                                      member.ackedAt!.toLocal(),
                                      clock.now(),
                                      alwaysUse24HourFormat:
                                          MediaQuery.alwaysUse24HourFormatOf(
                                            context,
                                          ),
                                    ),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: c.muted,
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WeCordButton(
                        key: const ValueKey('announcement-ack-remind'),
                        label: _reminded
                            ? tr('Reminder sent')
                            : tr('Remind the ones who have not'),
                        icon: _reminded
                            ? Icons.check_rounded
                            : Icons.notifications_active_outlined,
                        expand: true,
                        loading: _reminding,
                        onPressed: canRemind
                            ? () => unawaited(_remind())
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tooSoon && !_reminded
                            ? tr('You can remind again {time}.', {
                                'time': describeWhen(
                                  localizations,
                                  next.toLocal(),
                                  clock.now(),
                                  alwaysUse24HourFormat:
                                      MediaQuery.alwaysUse24HourFormatOf(
                                        context,
                                      ),
                                ),
                              })
                            : tr(
                                'Sends a notification to the members who have not confirmed. You can remind once every 6 hours.',
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: c.subtle),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
