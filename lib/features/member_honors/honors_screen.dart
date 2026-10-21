import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart'
    show circleDetailProvider;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/member_honors/honor_models.dart';
import 'package:wecord/features/member_honors/honor_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the Honors page of a circle (circle menu → Honors).
void openMemberHonors(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => MemberHonorsScreen(circleId: circleId),
    ),
  );
}

/// Honors for being around: the days you were active, never how much you
/// wrote. Shows your own streak and week (nobody else's numbers), the
/// honors you earned, and last week's board of names (only when 5 or more
/// people are on it). Members can stay out; moderators can switch honors
/// off for the whole circle.
class MemberHonorsScreen extends ConsumerStatefulWidget {
  const MemberHonorsScreen({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<MemberHonorsScreen> createState() => _MemberHonorsScreenState();
}

class _MemberHonorsScreenState extends ConsumerState<MemberHonorsScreen> {
  var _busy = false;

  void _refresh() {
    ref
      ..invalidate(circleHonorsProvider(widget.circleId))
      ..invalidate(circleMemberFlairProvider(widget.circleId));
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not change that. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setParticipation(bool on) async {
    if (!on) {
      final confirmed = await confirmCircleAction(
        context,
        title: tr('Stay out of honors?'),
        message: tr(
          'Nothing will be counted for you in this circle and the honors you '
          'earned here are removed. You can take part again any time.',
        ),
        confirmLabel: tr('Stay out'),
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    await _run(
      () => ref
          .read(memberHonorsRepositoryProvider)
          .setParticipation(widget.circleId, on: on),
    );
  }

  Future<void> _setCircleHonors(bool on) async {
    if (!on) {
      final confirmed = await confirmCircleAction(
        context,
        title: tr('Turn honors off for this circle?'),
        message: tr(
          'Everything worked out so far is deleted and nothing new is '
          'counted. Titles stay.',
        ),
        confirmLabel: tr('Turn off'),
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    await _run(
      () => ref
          .read(memberHonorsRepositoryProvider)
          .setCircleHonors(widget.circleId, on: on),
    );
  }

  @override
  Widget build(BuildContext context) {
    final honors = ref.watch(circleHonorsProvider(widget.circleId));
    final detail = ref.watch(circleDetailProvider(widget.circleId)).value;
    return CirclePageScaffold(
      title: tr('Honors'),
      subtitle: detail?.circle.name,
      body: honors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => CircleEmptyState(
          icon: Icons.emoji_events_outlined,
          title: tr('Could not load honors.'),
          message: errorText(error),
          action: WeCordButton(label: tr('Try again'), onPressed: _refresh),
        ),
        data: (data) => data == null
            ? CircleEmptyState(
                icon: Icons.lock_outline,
                title: tr('Honors are not available.'),
              )
            : ListView(
                padding: circlePagePadding(context),
                children: _sections(context, data, detail),
              ),
      ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    CircleHonors data,
    CircleDetail? detail,
  ) {
    final c = context.tokens.colors;
    return [
      const SizedBox(height: 8),
      CircleCard(
        key: const ValueKey('honors-intro'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThingAvatar(
              icon: Icons.emoji_events_outlined,
              size: 40,
              color: c.warningSoft,
              foregroundColor: c.warningText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr(
                  'Honors are for being around, not for posting the most. '
                  'They count the days you were active, never your messages. '
                  'Other members only see which honors you earned.',
                ),
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.45),
              ),
            ),
          ],
        ),
      ),
      if (!data.enabled)
        _Note(
          key: const ValueKey('honors-off'),
          icon: Icons.toggle_off_outlined,
          text: tr('Honors are turned off in this circle.'),
        )
      else if (!data.eligible)
        _Note(
          key: const ValueKey('honors-small'),
          icon: Icons.group_outlined,
          text: tr(
            'Honors start once this circle has 5 members. With fewer people, '
            'any honor would point at one person.',
          ),
        ),
      if (data.isRunning) ...[
        SettingsSectionHeader(tr('Your part')),
        SettingsGroup(
          children: [
            SettingsRow.toggle(
              key: const ValueKey('honors-participate'),
              icon: Icons.person_outline,
              title: tr('Take part in honors'),
              subtitle: tr(
                'When you stay out, nothing is counted for you here.',
              ),
              value: data.participating,
              onChanged: _busy ? null : _setParticipation,
            ),
          ],
        ),
        if (data.participating && data.mine != null)
          ..._mine(context, data.mine!),
        if (data.board case final board?) ..._board(context, board, detail),
      ],
      if (data.canManage) ...[
        SettingsSectionHeader(tr('For moderators')),
        SettingsGroup(
          children: [
            SettingsRow.toggle(
              key: const ValueKey('honors-circle-switch'),
              icon: Icons.emoji_events_outlined,
              title: tr('Honors in this circle'),
              subtitle: tr(
                'Weekly levels and streaks for members who take part.',
              ),
              value: data.enabled,
              onChanged: _busy ? null : _setCircleHonors,
            ),
          ],
        ),
      ],
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _mine(BuildContext context, MyHonors mine) {
    final c = context.tokens.colors;
    String days(int n) => tr('{count} days', {'count': n});
    final streak = mine.streak >= 100 ? tr('100+ days') : days(mine.streak);
    final best = mine.bestStreak >= 100
        ? tr('100+ days')
        : days(mine.bestStreak);
    return [
      SettingsSectionHeader(tr('Your days')),
      CircleCard(
        key: const ValueKey('honors-mine'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatRow(
              label: tr('Current streak'),
              value: streak,
              valueKey: const ValueKey('honors-streak'),
            ),
            _StatRow(label: tr('Best streak'), value: best),
            _StatRow(
              label: tr('Active this week'),
              value: tr('{count} of 7', {'count': mine.weekDays}),
              valueKey: const ValueKey('honors-week'),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Only you see these numbers. Days are counted in UTC and '
                'updated each night.',
              ),
              style: TextStyle(fontSize: 12.5, color: c.subtle, height: 1.4),
            ),
          ],
        ),
      ),
      SettingsSectionHeader(tr('Honors you earned')),
      if (mine.honors.isEmpty)
        _Note(
          key: const ValueKey('honors-none'),
          icon: Icons.hourglass_empty,
          text: tr(
            'Nothing yet. Be active on 3 days of a week, or keep a 7-day '
            'streak, to earn your first.',
          ),
        )
      else
        CircleCard(
          key: const ValueKey('honors-earned'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final honor in mine.honors) _EarnedRow(honor: honor),
            ],
          ),
        ),
    ];
  }

  List<Widget> _board(
    BuildContext context,
    HonorBoard board,
    CircleDetail? detail,
  ) {
    final c = context.tokens.colors;
    final byId = {
      for (final member in detail?.members ?? const <CircleMember>[])
        member.profile.id: member,
    };
    final start = board.weekStart;
    final weekLabel = start == null
        ? null
        : tr('Week of {date}', {
            'date': MaterialLocalizations.of(context).formatMediumDate(start),
          });
    return [
      SettingsSectionHeader(tr('Last week')),
      if (!board.published)
        _Note(
          key: const ValueKey('honors-board-hidden'),
          icon: Icons.visibility_off_outlined,
          text: tr(
            'The board shows once at least 5 members have a place on it, so '
            'it never points at a few people.',
          ),
        )
      else
        CircleCard(
          key: const ValueKey('honors-board'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (weekLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    weekLabel,
                    style: TextStyle(fontSize: 12.5, color: c.subtle),
                  ),
                ),
              for (final level in const [3, 2, 1])
                ..._boardLevel(context, level, [
                  for (final entry in board.entries)
                    if (entry.level == level && byId[entry.userId] != null)
                      byId[entry.userId]!,
                ]),
            ],
          ),
        ),
    ];
  }

  List<Widget> _boardLevel(
    BuildContext context,
    int level,
    List<CircleMember> members,
  ) {
    if (members.isEmpty) {
      return const [];
    }
    final c = context.tokens.colors;
    members.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Semantics(
          header: true,
          child: Text(
            '${weeklyLevelLabel(level)} · ${weeklyLevelRule(level)}',
            key: ValueKey('honors-level-$level'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
        ),
      ),
      for (final member in members)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            key: ValueKey('honors-board-${member.profile.id}'),
            children: [
              CircleNetworkAvatar(
                name: member.displayName,
                url: member.profile.avatarUrl,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  member.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, color: c.ink),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CircleCard(
        color: c.well,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: c.subtle),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 14, color: c.muted, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14.5, color: c.muted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              key: valueKey,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EarnedRow extends StatelessWidget {
  const _EarnedRow({required this.honor});

  final EarnedHonor honor;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(honor.periodStart);
    final detail = switch (honor.kind) {
      HonorKind.weekly => tr('Week of {date}', {'date': date}),
      HonorKind.streak => date,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            honor.kind == HonorKind.streak
                ? Icons.local_fire_department
                : Icons.emoji_events,
            size: 20,
            color: c.warningText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  honor.label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                Text(detail, style: TextStyle(fontSize: 12.5, color: c.subtle)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
