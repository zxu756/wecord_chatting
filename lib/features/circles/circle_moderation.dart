import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_ban.dart';

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
  final duration = await showDialog<Duration>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Time out {name}', {'name': name})),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            tr(
              "They can still read, but can't send messages, react, start "
              'threads or join voice until it ends.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        for (final (label, duration) in circleTimeoutDurations)
          SimpleDialogOption(
            key: ValueKey('timeout-option-${duration.inSeconds}'),
            onPressed: () => Navigator.of(context).pop(duration),
            child: Text(tr(label)),
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
  final choice = await showDialog<({String reason, int deleteHours})>(
    context: context,
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
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Ban {name}', {'name': widget.name})),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(
              'Remove {name} from this circle and keep them from '
              'rejoining, even with an invite.',
              {'name': widget.name},
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: const ValueKey('ban-delete-messages'),
            initialValue: _deleteHours,
            decoration: InputDecoration(labelText: tr('Delete their messages')),
            items: [
              for (final (label, hours) in circleBanMessageWindows)
                DropdownMenuItem(value: hours, child: Text(tr(label))),
            ],
            onChanged: (value) => setState(() => _deleteHours = value ?? 0),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('ban-reason'),
            controller: _reason,
            maxLength: 512,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: tr('Reason (optional)'),
              helperText: tr('Only moderators see it.'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('ban-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(
            context,
          ).pop((reason: _reason.text.trim(), deleteHours: _deleteHours)),
          child: Text(tr('Ban')),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bans'))),
      body: bans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Could not load bans.')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(circleBansProvider(circleId)),
                  child: Text(tr('Try again')),
                ),
              ],
            ),
          ),
        ),
        data: (bans) {
          if (bans.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Nobody is banned.'),
                  key: const ValueKey('circle-bans-empty'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: bans.length,
            itemBuilder: (context, index) {
              final ban = bans[index];
              final details = [
                if (ban.reason case final reason? when reason.isNotEmpty)
                  reason,
                if (ban.bannedByName case final by?)
                  tr('Banned by {name}', {'name': by}),
              ].join(' · ');
              return ListTile(
                key: ValueKey('circle-ban-${ban.userId}'),
                leading: FallbackAvatar(
                  title: ban.name,
                  avatarUrl: ban.avatarUrl,
                ),
                title: Text(ban.name),
                subtitle: details.isEmpty
                    ? Text('@${ban.username}')
                    : Text(
                        '@${ban.username} · $details',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: TextButton(
                  key: ValueKey('circle-unban-${ban.userId}'),
                  onPressed: () => _unban(context, ref, ban),
                  child: Text(tr('Unban')),
                ),
              );
            },
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Unban {name}', {'name': ban.name})),
        content: Text(
          tr('{name} will be able to join again with an invite.', {
            'name': ban.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Unban')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
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
