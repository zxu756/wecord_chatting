import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circles_screen.dart';
import 'package:wecord/shared/models/circle.dart';

/// Asks to confirm, then leaves the circle and goes back to the circle
/// list.
Future<void> leaveCircle(
  BuildContext context, {
  required CircleDetail detail,
}) async {
  final name = detail.circle.name;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text('Leave $name'),
      content: const Text(
        'Leave this circle and all of its channels? You can only rejoin with '
        'an invite.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  // The circle's screen may go away while leaving (its realtime refresh
  // finds the caller gone), so keep what is needed afterwards.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container
        .read(circlesRepositoryProvider)
        .leaveCircle(detail.circle.id);
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not leave $name. Try again.')),
    );
    return;
  }
  container
    ..invalidate(circleSummariesProvider)
    ..invalidate(conversationsProvider);
  router.go(CirclesScreen.path);
  messenger?.showSnackBar(SnackBar(content: Text('Left $name.')));
}

/// Lets the owner pick another member and confirm with the circle's name,
/// then hands them the circle.
Future<void> transferCircleOwnership(
  BuildContext context, {
  required CircleDetail detail,
}) async {
  final newOwner = await showDialog<CircleMember>(
    context: context,
    builder: (context) => _TransferOwnershipDialog(detail: detail),
  );
  if (newOwner == null || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final circleId = detail.circle.id;
  try {
    await container
        .read(circlesRepositoryProvider)
        .transferOwnership(circleId: circleId, newOwnerId: newOwner.profile.id);
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('Could not transfer ownership. Try again.')),
    );
    return;
  }
  container
    ..invalidate(circleDetailProvider(circleId))
    ..invalidate(circleSummariesProvider);
  messenger?.showSnackBar(
    SnackBar(content: Text('${newOwner.displayName} now owns the circle.')),
  );
}

class _TransferOwnershipDialog extends StatefulWidget {
  const _TransferOwnershipDialog({required this.detail});

  final CircleDetail detail;

  @override
  State<_TransferOwnershipDialog> createState() =>
      _TransferOwnershipDialogState();
}

class _TransferOwnershipDialogState extends State<_TransferOwnershipDialog> {
  final _nameController = TextEditingController();
  CircleMember? _selected;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _selected != null &&
      _nameController.text.trim() == widget.detail.circle.name.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = [
      for (final member in widget.detail.members)
        if (!member.isCurrentUser) member,
    ];
    final circleName = widget.detail.circle.name;

    return AlertDialog(
      scrollable: true,
      title: const Text('Transfer ownership'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The new owner gets every permission. You stay in the circle as '
            'a member without roles.',
          ),
          const SizedBox(height: 12),
          if (candidates.isEmpty)
            Text(
              'Invite someone first: there is nobody to hand the circle to.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final member in candidates)
              ListTile(
                key: ValueKey('transfer-owner-${member.profile.id}'),
                contentPadding: EdgeInsets.zero,
                selected: member.profile.id == _selected?.profile.id,
                leading: CircleAvatar(
                  backgroundImage: member.profile.avatarUrl == null
                      ? null
                      : NetworkImage(member.profile.avatarUrl!),
                  child: member.profile.avatarUrl == null
                      ? Text(_initial(member.displayName))
                      : null,
                ),
                title: Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '@${member.profile.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: member.profile.id == _selected?.profile.id
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => setState(() => _selected = member),
              ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('transfer-confirm-name'),
            controller: _nameController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Type the circle name to confirm',
              hintText: circleName,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirmed
              ? () => Navigator.of(context).pop(_selected)
              : null,
          child: const Text('Transfer'),
        ),
      ],
    );
  }
}

/// Shown in place of a circle the current user left or was removed from.
/// Drops the circle from the rail on the way in.
class CircleMembershipLostView extends ConsumerStatefulWidget {
  const CircleMembershipLostView({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleMembershipLostView> createState() =>
      _CircleMembershipLostViewState();
}

class _CircleMembershipLostViewState
    extends ConsumerState<CircleMembershipLostView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(circleSummariesProvider);
        ref.invalidate(conversationsProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleRail(selectedCircleId: widget.circleId),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group_off_outlined,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "You're no longer a member of this circle",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You left it or were removed. You can rejoin with an '
                        'invite.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => context.go(CirclesScreen.path),
                        child: const Text('Back to Circles'),
                      ),
                    ],
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

String _initial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}
