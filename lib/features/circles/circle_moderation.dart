import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_ban.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How long a timeout can last, as offered in the timeout dialog.
const circleTimeoutDurations = <(String, Duration)>[
  ('60 seconds', Duration(seconds: 60)),
  ('5 minutes', Duration(minutes: 5)),
  ('10 minutes', Duration(minutes: 10)),
  ('1 hour', Duration(hours: 1)),
  ('1 day', Duration(days: 1)),
  ('1 week', Duration(days: 7)),
];

/// How far back a ban can delete the member's messages.
const circleBanMessageWindows = <(String, int)>[
  ("Don't delete any", 0),
  ('Previous hour', 1),
  ('Previous 24 hours', 24),
  ('Previous 7 days', 168),
];

/// "15:30" today, otherwise "10/21 15:30".
String formatTimeoutEnd(DateTime value, {DateTime? now}) {
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

/// Asks how long to time [member] out for, then does it.
Future<void> timeOutCircleMember(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required CircleMember member,
}) async {
  final name = member.displayName;
  final duration = await showCircleDialog<Duration>(
    context,
    builder: (context) => CircleDialog(
      title: tr('Time out {name}', {'name': name}),
      message: tr(
        "They can still read, but can't send messages, react, start "
        'threads or join voice until it ends.',
      ),
      content: SettingsGroup(
        color: context.tokens.colors.well,
        separatorIndent: 14,
        children: [
          for (final (label, duration) in circleTimeoutDurations)
            SettingsRow(
              key: ValueKey('timeout-option-${duration.inSeconds}'),
              title: tr(label),
              onTap: () => Navigator.of(context).pop(duration),
            ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
  if (duration == null || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final until = await ref
        .read(circlesRepositoryProvider)
        .timeoutMember(
          circleId: circleId,
          userId: member.profile.id,
          duration: duration,
        );
    ref.invalidate(circleDetailProvider(circleId));
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          until == null
              ? tr('Timed out {name}.', {'name': name})
              : tr('Timed out {name} until {time}.', {
                  'name': name,
                  'time': formatTimeoutEnd(until),
                }),
        ),
      ),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          tr('Could not time out {name}. Try again.', {'name': name}),
        ),
      ),
    );
  }
}

/// Ends [member]'s timeout.
Future<void> removeCircleMemberTimeout(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required CircleMember member,
}) async {
  final name = member.displayName;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(circlesRepositoryProvider)
        .timeoutMember(
          circleId: circleId,
          userId: member.profile.id,
          duration: Duration.zero,
        );
    ref.invalidate(circleDetailProvider(circleId));
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("Removed {name}'s timeout.", {'name': name}))),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          tr("Could not remove {name}'s timeout. Try again.", {'name': name}),
        ),
      ),
    );
  }
}

/// Asks for a reason and which messages to delete, then bans [member].
Future<void> banCircleMember(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required CircleMember member,
}) async {
  final name = member.displayName;
  final choice = await showCircleDialog<({String reason, int deleteHours})>(
    context,
    builder: (context) => _BanDialog(name: name),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(circlesRepositoryProvider)
        .banMember(
          circleId: circleId,
          userId: member.profile.id,
          reason: choice.reason,
          deleteMessageHours: choice.deleteHours,
        );
    ref
      ..invalidate(circleDetailProvider(circleId))
      ..invalidate(circleBansProvider(circleId));
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Banned {name}.', {'name': name}))),
    );
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(tr('Could not ban {name}. Try again.', {'name': name})),
      ),
    );
  }
}

class _BanDialog extends StatefulWidget {
  const _BanDialog({required this.name});

  final String name;

  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  final _reason = TextEditingController();
  var _deleteHours = 0;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleDialog(
      title: tr('Ban {name}', {'name': widget.name}),
      message: tr(
        'Remove {name} from this circle and keep them from '
        'rejoining, even with an invite.',
        {'name': widget.name},
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsGroup(
            key: const ValueKey('ban-delete-messages'),
            header: tr('Delete their messages'),
            color: c.well,
            separatorIndent: 14,
            children: [
              for (final (label, hours) in circleBanMessageWindows)
                SettingsRow(
                  key: ValueKey('ban-delete-$hours'),
                  title: tr(label),
                  showChevron: false,
                  trailing: _deleteHours == hours
                      ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
                      : null,
                  onTap: () => setState(() => _deleteHours = hours),
                ),
            ],
          ),
          const SizedBox(height: 16),
          WeCordTextField(
            fieldKey: const ValueKey('ban-reason'),
            controller: _reason,
            maxLength: 512,
            maxLines: 3,
            minLines: 1,
            label: tr('Reason (optional)'),
            helperText: tr('Only moderators see it.'),
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.danger(
          key: const ValueKey('ban-confirm'),
          label: tr('Ban'),
          onPressed: () => Navigator.of(
            context,
          ).pop((reason: _reason.text.trim(), deleteHours: _deleteHours)),
        ),
      ],
    );
  }
}

final circleBansProvider = FutureProvider.autoDispose
    .family<List<CircleBan>, String>((ref, circleId) {
      return ref.watch(circlesRepositoryProvider).listBans(circleId);
    });

void openCircleBansScreen(BuildContext context, String circleId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleBansScreen(circleId: circleId),
    ),
  );
}

/// Everyone banned from a circle, newest first, with a way to unban them.
class CircleBansScreen extends ConsumerWidget {
  const CircleBansScreen({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bans = ref.watch(circleBansProvider(circleId));
    final c = context.tokens.colors;
    return CirclePageScaffold(
      title: tr('Bans'),
      body: bans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => CircleEmptyState(
          icon: Icons.error_outline,
          title: tr('Could not load bans.'),
          action: WeCordButton(
            label: tr('Try again'),
            variant: WeCordButtonVariant.onPaper,
            onPressed: () => ref.invalidate(circleBansProvider(circleId)),
          ),
        ),
        data: (bans) {
          if (bans.isEmpty) {
            return CircleEmptyState(
              key: const ValueKey('circle-bans-empty'),
              icon: Icons.verified_user_outlined,
              title: tr('Nobody is banned.'),
            );
          }
          return ListView(
            padding: circlePagePadding(context),
            children: [
              SettingsGroup(
                separatorIndent: 66,
                children: [
                  for (final ban in bans)
                    _BanRow(
                      key: ValueKey('circle-ban-${ban.userId}'),
                      ban: ban,
                      colors: c,
                      onUnban: () => _unban(context, ref, ban),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _unban(
    BuildContext context,
    WidgetRef ref,
    CircleBan ban,
  ) async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Unban {name}', {'name': ban.name}),
      message: tr('{name} will be able to join again with an invite.', {
        'name': ban.name,
      }),
      confirmLabel: tr('Unban'),
      destructive: false,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(circlesRepositoryProvider)
          .unbanMember(circleId: circleId, userId: ban.userId);
      ref.invalidate(circleBansProvider(circleId));
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Unbanned {name}.', {'name': ban.name}))),
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr('Could not unban {name}. Try again.', {'name': ban.name}),
          ),
        ),
      );
    }
  }
}

/// One banned person: avatar, name, @username with the reason and who
/// banned them, and an Unban button.
class _BanRow extends StatelessWidget {
  const _BanRow({
    required this.ban,
    required this.colors,
    required this.onUnban,
    super.key,
  });

  final CircleBan ban;
  final WeCordPalette colors;
  final VoidCallback onUnban;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final details = [
      '@${ban.username}',
      if (ban.reason case final reason? when reason.isNotEmpty) reason,
      if (ban.bannedByName case final by?) tr('Banned by {name}', {'name': by}),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Row(
        children: [
          CircleNetworkAvatar(name: ban.name, url: ban.avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ban.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          WeCordButton(
            key: ValueKey('circle-unban-${ban.userId}'),
            label: tr('Unban'),
            size: WeCordButtonSize.small,
            variant: WeCordButtonVariant.secondary,
            onPressed: onUnban,
          ),
        ],
      ),
    );
  }
}
