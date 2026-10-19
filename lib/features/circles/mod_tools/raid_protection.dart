import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart'
    show messageReviewCountProvider;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "15:30" today, otherwise "10/21 15:30".
String raidTimeLabel(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay ? time : '${local.month}/${local.day} $time';
}

/// Runs a safety action and tells the moderator how it went.
Future<bool> _runSafety(
  BuildContext context,
  WidgetRef ref,
  String circleId,
  Future<void> Function(ModToolsRepository repository) action, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action(ref.read(modToolsRepositoryProvider));
    ref
      ..invalidate(circleSecurityProvider(circleId))
      ..invalidate(pendingJoinRequestsProvider(circleId))
      ..invalidate(joinRequestCountProvider(circleId))
      ..invalidate(messageReviewCountProvider(circleId));
    messenger?.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on Object {
    ref.invalidate(circleSecurityProvider(circleId));
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not do that. Try again.'))),
    );
    return false;
  }
}

/// The banner on top of the Review page while a lockdown or a pause of
/// invites is on: what is on, until when, and the one button that undoes
/// it. Nothing for moderators who cannot read the state, and nothing while
/// all is quiet.
class RaidStatusBanner extends ConsumerWidget {
  const RaidStatusBanner({required this.circleId, this.now, super.key});

  final String circleId;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(circleSecurityProvider(circleId)).value;
    if (security == null || !security.active) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final current = (now ?? DateTime.now)();
    final lockdown = security.lockdown;
    final String title;
    final String message;
    if (lockdown != null) {
      title = lockdown.automatic
          ? tr('Raid protection locked this circle')
          : tr('Joining is locked down');
      final counts = lockdown.automatic && (lockdown.joins ?? 0) > 0
          ? tr('{count} people joined or asked to join within 10 minutes.', {
              'count': lockdown.joins,
            })
          : null;
      final until = tr(
        'Until {time}. Invites are paused and new people need approval; '
        'nobody was removed.',
        {'time': raidTimeLabel(lockdown.until, now: current)},
      );
      message = [?counts, until].join(' ');
    } else {
      title = tr('Invites are paused');
      message = tr('Until {time}. Invite links and adding friends are off.', {
        'time': raidTimeLabel(security.invitesPausedUntil!, now: current),
      });
    }
    return Padding(
      padding: circlePagePadding(context).copyWith(bottom: 0),
      child: Container(
        key: const ValueKey('raid-banner'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: lockdown != null ? c.dangerSoft : c.warningSoft,
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  lockdown != null
                      ? Icons.lock_outline
                      : Icons.pause_circle_outline,
                  size: 22,
                  color: lockdown != null ? c.dangerText : c.warningText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: lockdown != null
                                ? c.dangerText
                                : c.warningText,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: WeCordButton(
                key: ValueKey(
                  lockdown != null
                      ? 'raid-end-lockdown'
                      : 'raid-resume-invites',
                ),
                label: lockdown != null
                    ? tr('End lockdown')
                    : tr('Resume invites'),
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(
                  _runSafety(
                    context,
                    ref,
                    circleId,
                    (repository) => lockdown != null
                        ? repository.endLockdown(circleId)
                        : repository.resumeInvites(circleId),
                    done: lockdown != null
                        ? tr('Lockdown ended.')
                        : tr('Invites are on again.'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openRaidProtectionScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => RaidProtectionScreen(circleId: circleId),
    ),
  );
}

/// Circle settings → Raid protection: what is on right now, the quick
/// actions, and (for those who manage the circle) when the circle locks
/// itself.
class RaidProtectionScreen extends ConsumerWidget {
  const RaidProtectionScreen({required this.circleId, this.now, super.key});

  final String circleId;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(circleSecurityProvider(circleId));
    return CirclePageScaffold(
      title: tr('Raid protection'),
      body: security.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: Icons.error_outline,
          title: tr('Could not load the safety settings.'),
          action: WeCordButton(
            label: tr('Try again'),
            onPressed: () => ref.invalidate(circleSecurityProvider(circleId)),
          ),
        ),
        data: (security) =>
            _RaidBody(circleId: circleId, security: security, now: now),
      ),
    );
  }
}

const _thresholdChoices = [5, 10, 20, 50, 100];

class _RaidBody extends ConsumerStatefulWidget {
  const _RaidBody({required this.circleId, required this.security, this.now});

  final String circleId;
  final CircleSecurity security;
  final DateTime Function()? now;

  @override
  ConsumerState<_RaidBody> createState() => _RaidBodyState();
}

class _RaidBodyState extends ConsumerState<_RaidBody> {
  late var _enabled = widget.security.raidEnabled;
  late var _threshold = widget.security.raidThreshold;
  late var _hours = widget.security.raidLockHours;
  var _saving = false;

  bool get _changed =>
      _enabled != widget.security.raidEnabled ||
      _threshold != widget.security.raidThreshold ||
      _hours != widget.security.raidLockHours;

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await _runSafety(
      context,
      ref,
      widget.circleId,
      (repository) => repository.saveRaidSettings(
        widget.circleId,
        enabled: _enabled,
        threshold: _threshold,
        lockHours: _hours,
      ),
      done: tr('Raid protection saved.'),
    );
    if (mounted) {
      setState(() => _saving = false);
      if (saved) {
        Navigator.of(context).maybePop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final security = widget.security;
    final now = (widget.now ?? DateTime.now)();
    final lockdown = security.lockdown;
    final choices = {..._thresholdChoices, security.raidThreshold}.toList()
      ..sort();
    Future<void> act(
      Future<void> Function(ModToolsRepository repository) action,
      String done,
    ) async {
      await _runSafety(context, ref, widget.circleId, action, done: done);
    }

    return ListView(
      padding: circlePagePadding(context),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
          child: Text(
            tr(
              'A lockdown pauses invites and makes new people ask to join. '
              'It never removes anyone, and you can end it any time.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        if (security.recentJoins > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
            child: Text(
              tr(
                'Last 10 minutes: {joins} joined or asked to join, {fresh} with a new account.',
                {
                  'joins': security.recentJoins,
                  'fresh': security.recentNewAccounts,
                },
              ),
              key: const ValueKey('raid-recent'),
              style: TextStyle(fontSize: 13.5, color: c.subtle),
            ),
          ),
        SettingsGroup(
          header: tr('Right now'),
          separatorIndent: 14,
          children: [
            if (lockdown != null)
              SettingsRow(
                key: const ValueKey('raid-end'),
                icon: Icons.lock_open_rounded,
                tone: SettingsTone.danger,
                title: tr('End lockdown'),
                subtitle: tr('Locked until {time}', {
                  'time': raidTimeLabel(lockdown.until, now: now),
                }),
                onTap: () => unawaited(
                  act(
                    (r) => r.endLockdown(widget.circleId),
                    tr('Lockdown ended.'),
                  ),
                ),
              )
            else ...[
              SettingsRow(
                key: const ValueKey('raid-lock-1'),
                icon: Icons.lock_outline,
                tone: SettingsTone.danger,
                title: tr('Lock down joining for 1 hour'),
                subtitle: tr('Pause invites, ask new people to apply'),
                onTap: () => unawaited(
                  act(
                    (r) => r.startLockdown(widget.circleId, 1),
                    tr('Joining is locked down.'),
                  ),
                ),
              ),
              SettingsRow(
                key: const ValueKey('raid-lock-24'),
                icon: Icons.lock_outline,
                tone: SettingsTone.danger,
                title: tr('Lock down joining for 24 hours'),
                onTap: () => unawaited(
                  act(
                    (r) => r.startLockdown(widget.circleId, 24),
                    tr('Joining is locked down.'),
                  ),
                ),
              ),
            ],
            if (security.invitesPaused && lockdown == null)
              SettingsRow(
                key: const ValueKey('raid-resume'),
                icon: Icons.play_circle_outline,
                tone: SettingsTone.warning,
                title: tr('Resume invites'),
                subtitle: tr('Paused until {time}', {
                  'time': raidTimeLabel(security.invitesPausedUntil!, now: now),
                }),
                onTap: () => unawaited(
                  act(
                    (r) => r.resumeInvites(widget.circleId),
                    tr('Invites are on again.'),
                  ),
                ),
              )
            else if (!security.invitesPaused) ...[
              SettingsRow(
                key: const ValueKey('raid-pause-1'),
                icon: Icons.pause_circle_outline,
                tone: SettingsTone.warning,
                title: tr('Pause invites for 1 hour'),
                subtitle: tr('Invite links and adding friends'),
                onTap: () => unawaited(
                  act(
                    (r) => r.pauseInvites(widget.circleId, 1),
                    tr('Invites are paused.'),
                  ),
                ),
              ),
              SettingsRow(
                key: const ValueKey('raid-pause-24'),
                icon: Icons.pause_circle_outline,
                tone: SettingsTone.warning,
                title: tr('Pause invites for 24 hours'),
                onTap: () => unawaited(
                  act(
                    (r) => r.pauseInvites(widget.circleId, 24),
                    tr('Invites are paused.'),
                  ),
                ),
              ),
            ],
          ],
        ),
        SettingsSectionHeader(tr('Automatic protection')),
        SettingsGroup(
          separatorIndent: 14,
          children: [
            SettingsRow.toggle(
              key: const ValueKey('raid-enabled'),
              title: tr('Lock down by itself'),
              subtitle: tr(
                'When a burst of people join or ask to join within 10 minutes.',
              ),
              value: _enabled,
              onChanged: security.canManage
                  ? (on) => setState(() => _enabled = on)
                  : null,
            ),
          ],
        ),
        if (_enabled) ...[
          const SizedBox(height: 12),
          SettingsGroup(
            header: tr('Lock down at'),
            footer: tr(
              'Joins or requests within 10 minutes. Half as many brand-new '
              'accounts (at least 5) also count.',
            ),
            separatorIndent: 14,
            children: [
              for (final choice in choices)
                SettingsRow(
                  key: ValueKey('raid-threshold-$choice'),
                  title: tr('{count} people', {'count': choice}),
                  showChevron: false,
                  trailing: _threshold == choice
                      ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
                      : null,
                  onTap: security.canManage
                      ? () => setState(() => _threshold = choice)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            header: tr('Stays locked for'),
            separatorIndent: 14,
            children: [
              for (final hours in const [1, 24])
                SettingsRow(
                  key: ValueKey('raid-hours-$hours'),
                  title: hours == 1 ? tr('1 hour') : tr('24 hours'),
                  showChevron: false,
                  trailing: _hours == hours
                      ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
                      : null,
                  onTap: security.canManage
                      ? () => setState(() => _hours = hours)
                      : null,
                ),
            ],
          ),
        ],
        if (security.canManage) ...[
          const SizedBox(height: 16),
          WeCordButton(
            key: const ValueKey('raid-save'),
            label: tr('Save'),
            expand: true,
            loading: _saving,
            onPressed: _saving || !_changed ? null : () => unawaited(_save()),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
            child: Text(
              tr('Only members who can manage the circle change these.'),
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// The circle menu's "Safety actions": the quick ones, in a dialog.
Future<void> showCircleSafetyActions(BuildContext context, String circleId) {
  return showCircleDialog<void>(
    context,
    builder: (dialogContext) => _SafetyActionsDialog(circleId: circleId),
  );
}

class _SafetyActionsDialog extends ConsumerWidget {
  const _SafetyActionsDialog({required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(circleSecurityProvider(circleId));
    final c = context.tokens.colors;

    Future<void> act(
      Future<void> Function(ModToolsRepository repository) action,
      String done,
    ) async {
      final navigator = Navigator.of(context);
      final ok = await _runSafety(context, ref, circleId, action, done: done);
      if (ok && navigator.mounted) {
        navigator.pop();
      }
    }

    final rows = security.when(
      loading: () => [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (error, stackTrace) => [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            tr('Could not load the safety settings.'),
            style: TextStyle(color: c.dangerText),
          ),
        ),
      ],
      data: (security) {
        final lockdown = security.lockdown;
        return [
          if (lockdown != null)
            SettingsRow(
              key: const ValueKey('safety-end-lockdown'),
              icon: Icons.lock_open_rounded,
              tone: SettingsTone.danger,
              title: tr('End lockdown'),
              onTap: () => unawaited(
                act((r) => r.endLockdown(circleId), tr('Lockdown ended.')),
              ),
            )
          else ...[
            if (security.invitesPaused)
              SettingsRow(
                key: const ValueKey('safety-resume'),
                icon: Icons.play_circle_outline,
                tone: SettingsTone.warning,
                title: tr('Resume invites'),
                onTap: () => unawaited(
                  act(
                    (r) => r.resumeInvites(circleId),
                    tr('Invites are on again.'),
                  ),
                ),
              )
            else ...[
              SettingsRow(
                key: const ValueKey('safety-pause-1'),
                icon: Icons.pause_circle_outline,
                tone: SettingsTone.warning,
                title: tr('Pause invites for 1 hour'),
                onTap: () => unawaited(
                  act(
                    (r) => r.pauseInvites(circleId, 1),
                    tr('Invites are paused.'),
                  ),
                ),
              ),
              SettingsRow(
                key: const ValueKey('safety-pause-24'),
                icon: Icons.pause_circle_outline,
                tone: SettingsTone.warning,
                title: tr('Pause invites for 24 hours'),
                onTap: () => unawaited(
                  act(
                    (r) => r.pauseInvites(circleId, 24),
                    tr('Invites are paused.'),
                  ),
                ),
              ),
            ],
            SettingsRow(
              key: const ValueKey('safety-lock-1'),
              icon: Icons.lock_outline,
              tone: SettingsTone.danger,
              title: tr('Lock down joining for 1 hour'),
              onTap: () => unawaited(
                act(
                  (r) => r.startLockdown(circleId, 1),
                  tr('Joining is locked down.'),
                ),
              ),
            ),
          ],
          SettingsRow(
            key: const ValueKey('safety-settings'),
            icon: Icons.shield_outlined,
            title: tr('Raid protection settings'),
            onTap: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              openRaidProtectionScreen(navigator.context, circleId);
            },
          ),
        ];
      },
    );

    return CircleDialog(
      title: tr('Safety actions'),
      message: tr(
        'For a raid or a flood of unwanted joins. Nobody is removed, and '
        'you can undo it any time.',
      ),
      content: SettingsGroup(
        color: c.well,
        separatorIndent: 58,
        children: rows,
      ),
      actions: [
        CircleDialogAction(
          label: tr('Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
