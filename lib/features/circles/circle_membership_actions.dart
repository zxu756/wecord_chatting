import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_detail_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Asks to confirm, then leaves the circle and goes back to the circle
/// list.
Future<void> leaveCircle(
  BuildContext context, {
  required CircleDetail detail,
}) async {
  final name = detail.circle.name;
  final confirmed = await confirmCircleAction(
    context,
    title: tr('Leave {name}', {'name': name}),
    message: tr(
      'Leave this circle and all of its channels? You can only rejoin '
      'with an invite.',
    ),
    confirmLabel: tr('Leave'),
  );
  if (!confirmed || !context.mounted) {
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
      SnackBar(
        content: Text(tr('Could not leave {name}. Try again.', {'name': name})),
      ),
    );
    return;
  }
  container
    ..invalidate(circleSummariesProvider)
    ..invalidate(conversationsProvider);
  router.go(HomeScreen.path);
  messenger?.showSnackBar(
    SnackBar(content: Text(tr('Left {name}.', {'name': name}))),
  );
}

/// Lets the owner pick another member and confirm with the circle's name,
/// then hands them the circle.
Future<void> transferCircleOwnership(
  BuildContext context, {
  required CircleDetail detail,
}) async {
  final newOwner = await showCircleDialog<CircleMember>(
    context,
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
      SnackBar(content: Text(tr('Could not transfer ownership. Try again.'))),
    );
    return;
  }
  container
    ..invalidate(circleDetailProvider(circleId))
    ..invalidate(circleSummariesProvider);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        tr('{name} now owns the circle.', {'name': newOwner.displayName}),
      ),
    ),
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
    final c = context.tokens.colors;
    final candidates = [
      for (final member in widget.detail.members)
        if (!member.isCurrentUser) member,
    ];
    final circleName = widget.detail.circle.name;

    return CircleDialog(
      title: tr('Transfer ownership'),
      message: tr(
        'The new owner gets every permission. You stay in the circle as '
        'a member without roles.',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (candidates.isEmpty)
            Text(
              tr(
                'Invite someone first: there is nobody to hand the circle to.',
              ),
              style: TextStyle(fontSize: 13, color: c.muted),
            )
          else
            SettingsGroup(
              color: c.well,
              separatorIndent: 62,
              children: [
                for (final member in candidates)
                  _CandidateRow(
                    key: ValueKey('transfer-owner-${member.profile.id}'),
                    member: member,
                    selected: member.profile.id == _selected?.profile.id,
                    onTap: () => setState(() => _selected = member),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          WeCordTextField(
            fieldKey: const ValueKey('transfer-confirm-name'),
            controller: _nameController,
            label: tr('Type the circle name to confirm'),
            hint: circleName,
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.danger(
          label: tr('Transfer'),
          onPressed: _confirmed
              ? () => Navigator.of(context).pop(_selected)
              : null,
        ),
      ],
    );
  }
}

/// A member the circle can be handed to, with a check when picked.
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.member,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CircleMember member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onTap,
      selected: selected,
      pressedScale: 1,
      shape: const RoundedRectangleBorder(),
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          color: selected
              ? c.accentSoft
              : hovered
              ? c.ink.withValues(alpha: 0.04)
              : c.ink.withValues(alpha: 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              CircleNetworkAvatar(
                name: member.displayName,
                url: member.profile.avatarUrl,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${member.profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 22, color: c.accent)
              else
                Icon(Icons.circle_outlined, size: 22, color: c.faint),
            ],
          ),
        );
      },
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
    final c = context.tokens.colors;
    return Scaffold(
      backgroundColor: c.rail,
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CircleRail(selectedCircleId: widget.circleId),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: PanelSurface(
                  color: c.paper,
                  child: CircleEmptyState(
                    icon: Icons.group_off_outlined,
                    title: tr("You're no longer a member of this circle"),
                    message: tr(
                      'You left it or were removed. You can rejoin with '
                      'an invite.',
                    ),
                    action: WeCordButton(
                      label: tr('Back to home'),
                      onPressed: () => context.go(HomeScreen.path),
                    ),
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
