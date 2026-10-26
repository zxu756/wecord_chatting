import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/check_in/check_in_actions.dart';
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_repository.dart';
import 'package:wecord/features/check_in/check_in_widgets.dart';
import 'package:wecord/features/forms/form_widgets.dart'
    show FormBar, FormNote, FormPageFrame;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the page of [checkInId]: today's list, the caller's days and runs.
Future<void> openCheckIn(BuildContext context, {required String checkInId}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => CheckInPage(checkInId: checkInId),
    ),
  );
}

/// One earlier day's list: (check-in id, 'YYYY-MM-DD').
typedef CheckInDayKey = ({String id, String day});

final checkInDayProvider = FutureProvider.autoDispose
    .family<CheckInDay, CheckInDayKey>((ref, key) {
      return ref
          .watch(checkInRepositoryProvider)
          .day(key.id, checkInDateFrom(key.day)!);
    });

class CheckInPage extends ConsumerStatefulWidget {
  const CheckInPage({required this.checkInId, super.key});

  final String checkInId;

  @override
  ConsumerState<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends ConsumerState<CheckInPage> {
  /// How many days back the list is looking (0 is today).
  var _back = 0;
  var _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(checkInDetailProvider(widget.checkInId));
    final detail = async.value;
    final check = detail?.snapshot;
    return FormPageFrame(
      pageKey: const ValueKey('check-in-page'),
      title: check?.title.isNotEmpty == true
          ? check!.title
          : tr('Daily check-in'),
      subtitle: check == null ? null : checkInTodayText(check),
      bottom: check == null || check.closed ? null : _bottomBar(check),
      child: detail == null
          ? async.hasError
                ? FormNote(
                    icon: Icons.error_outline_rounded,
                    text: tr("This check-in isn't available any more."),
                    action: WeCordButton(
                      label: tr('Try again'),
                      variant: WeCordButtonVariant.secondary,
                      onPressed: () => ref.invalidate(
                        checkInDetailProvider(widget.checkInId),
                      ),
                    ),
                  )
                : const Center(child: CircularProgressIndicator())
          : _content(context, detail),
    );
  }

  Widget _bottomBar(CheckInSnapshot check) {
    if (check.myCheckedIn) {
      return WeCordButton(
        key: const ValueKey('check-in-edit'),
        label: tr('Add a note or picture'),
        icon: Icons.edit_outlined,
        variant: WeCordButtonVariant.secondary,
        size: WeCordButtonSize.large,
        expand: true,
        onPressed: _busy
            ? null
            : () => unawaited(showCheckInNoteSheet(context, check: check)),
      );
    }
    return Row(
      children: [
        Expanded(
          child: WeCordButton(
            key: const ValueKey('check-in-now'),
            label: tr('Check in'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            loading: _busy,
            onPressed: _busy
                ? null
                : () =>
                      unawaited(_run(() => quickCheckIn(context, ref, check))),
          ),
        ),
        const SizedBox(width: 8),
        WeCordIconButton(
          key: const ValueKey('check-in-with-note'),
          tooltip: tr('Check in with a note or picture'),
          icon: Icons.edit_note_rounded,
          size: 48,
          variant: WeCordButtonVariant.secondary,
          onPressed: _busy
              ? null
              : () => unawaited(showCheckInNoteSheet(context, check: check)),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, CheckInDetail detail) {
    final c = context.tokens.colors;
    final check = detail.snapshot;
    final me = ref.watch(authRepositoryProvider).currentUser?.id;
    final day = check.today.subtract(Duration(days: _back));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(checkInDetailProvider(widget.checkInId));
        await ref.read(checkInDetailProvider(widget.checkInId).future);
      },
      child: ListView(
        key: const ValueKey('check-in-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _Summary(check: check),
          if (check.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                check.description,
                style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
              ),
            ),
          if (check.myCheckedIn && !check.closed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: WeCordButton(
                  key: const ValueKey('check-in-undo'),
                  label: tr("Take today's check-in back"),
                  icon: Icons.undo_rounded,
                  variant: WeCordButtonVariant.ghost,
                  size: WeCordButtonSize.small,
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _run(() => undoCheckIn(context, ref, check)),
                        ),
                ),
              ),
            ),
          SettingsSectionHeader(tr('Your last 5 weeks')),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: CheckInCalendar(today: check.today, days: detail.myDays),
          ),
          if (detail.leaders.isNotEmpty) ...[
            SettingsSectionHeader(tr('Longest streaks')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Column(
                children: [
                  for (final leader in detail.leaders)
                    _LeaderRow(leader: leader),
                ],
              ),
            ),
          ],
          _DayHeader(
            day: day,
            today: check.today,
            canGoBack: _back < 60,
            onBack: () => setState(() => _back += 1),
            onForward: _back == 0 ? null : () => setState(() => _back -= 1),
          ),
          if (_back == 0)
            _EntryList(
              entries: detail.entries,
              viewerEntryUserId: me,
              emptyText: tr('Nobody has checked in yet today.'),
            )
          else
            ref
                .watch(
                  checkInDayProvider((
                    id: widget.checkInId,
                    day: checkInDateText(day),
                  )),
                )
                .when(
                  data: (data) => _EntryList(
                    entries: data.entries,
                    viewerEntryUserId: me,
                    emptyText: tr('Nobody checked in that day.'),
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr("That day couldn't load. Try again."),
                      style: TextStyle(fontSize: 14, color: c.muted),
                    ),
                  ),
                ),
          if (check.canManage) ...[
            SettingsSectionHeader(tr('Manage')),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('check-in-close'),
                  icon: check.closed
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline_rounded,
                  title: check.closed
                      ? tr('Reopen this check-in')
                      : tr('Close this check-in'),
                  subtitle: check.closed
                      ? null
                      : tr('Nobody can check in after it closes.'),
                  onTap: _busy
                      ? null
                      : () => unawaited(
                          _run(
                            () => setCheckInClosed(
                              context,
                              ref,
                              check,
                              closed: !check.closed,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.check});

  final CheckInSnapshot check;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CheckInIconTile(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  checkInTodayText(check),
                  key: const ValueKey('check-in-page-count'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ),
              if (check.closed)
                CheckInPill(text: tr('Closed'), closed: true)
              else if (check.myCheckedIn)
                CheckInPill(
                  text: tr('Checked in today'),
                  icon: Icons.check_rounded,
                  hot: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
          FormBar(fraction: check.todayFraction),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '${check.myStreak}',
                  label: tr('Current streak'),
                  hot: check.myStreak > 0,
                ),
              ),
              Expanded(
                child: _Stat(
                  value: '${check.myBestStreak}',
                  label: tr('Best streak'),
                ),
              ),
              Expanded(
                child: _Stat(
                  value: '${check.myTotalDays}',
                  label: tr('Days checked in'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            check.remindMinute == null
                ? tr('A new day starts at midnight in {zone}.', {
                    'zone': check.timeZone,
                  })
                : tr(
                    'A new day starts at midnight in {zone}. Reminder at {time}.',
                    {
                      'zone': check.timeZone,
                      'time': _minuteText(context, check.remindMinute!),
                    },
                  ),
            style: TextStyle(fontSize: 12.5, height: 1.35, color: c.subtle),
          ),
        ],
      ),
    );
  }
}

String _minuteText(BuildContext context, int minute) {
  return TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.hot = false});

  final String value;
  final String label;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: hot ? c.successText : c.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.subtle),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.leader});

  final CheckInLeader leader;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              leader.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CheckInPill(
            text: checkInStreakText(leader.streak),
            icon: Icons.local_fire_department_outlined,
            hot: true,
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.today,
    required this.canGoBack,
    required this.onBack,
    required this.onForward,
  });

  final DateTime day;
  final DateTime today;
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final diff = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(day.year, day.month, day.day)).inDays;
    final label = diff == 0
        ? tr('Today')
        : diff == 1
        ? tr('Yesterday')
        : MaterialLocalizations.of(context).formatMediumDate(day);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Row(
        children: [
          WeCordIconButton(
            key: const ValueKey('check-in-day-back'),
            tooltip: tr('Earlier day'),
            icon: Icons.chevron_left_rounded,
            variant: WeCordButtonVariant.ghost,
            onPressed: canGoBack ? onBack : null,
          ),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                label,
                key: const ValueKey('check-in-day-label'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.ink,
                ),
              ),
            ),
          ),
          WeCordIconButton(
            key: const ValueKey('check-in-day-forward'),
            tooltip: tr('Later day'),
            icon: Icons.chevron_right_rounded,
            variant: WeCordButtonVariant.ghost,
            onPressed: onForward,
          ),
        ],
      ),
    );
  }
}

class _EntryList extends ConsumerWidget {
  const _EntryList({
    required this.entries,
    required this.viewerEntryUserId,
    required this.emptyText,
  });

  final List<CheckInEntry> entries;
  final String? viewerEntryUserId;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, color: c.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in entries)
          CheckInEntryRow(
            key: ValueKey('check-in-entry-${entry.id}'),
            entry: entry,
            mine: entry.userId == viewerEntryUserId,
            onOpenPicture: (image) =>
                unawaited(showCheckInPicture(context, image)),
          ),
      ],
    );
  }
}
