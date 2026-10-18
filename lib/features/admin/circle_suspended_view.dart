import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/admin/admin_models.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_membership_actions.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What a circle page shows when the server will not give its detail: the
/// "This circle was suspended" state when an admin suspended it, else the
/// usual "you are no longer a member".
class CircleUnavailableView extends ConsumerWidget {
  const CircleUnavailableView({required this.circleId, super.key});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final takedowns = ref.watch(circleTakedownsProvider);
    return takedowns.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => CircleMembershipLostView(circleId: circleId),
      data: (byId) => byId[circleId] == CircleTakedownMode.suspend
          ? CircleSuspendedView(circleId: circleId)
          : CircleMembershipLostView(circleId: circleId),
    );
  }
}

/// The state of a circle an admin suspended: nobody can enter or read it.
/// Members can leave.
class CircleSuspendedView extends ConsumerStatefulWidget {
  const CircleSuspendedView({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleSuspendedView> createState() =>
      _CircleSuspendedViewState();
}

class _CircleSuspendedViewState extends ConsumerState<CircleSuspendedView> {
  var _leaving = false;

  Future<void> _leave() async {
    final sure = await confirmCircleAction(
      context,
      title: tr('Leave this circle?'),
      message: tr('It will be gone from your list.'),
      confirmLabel: tr('Leave circle'),
    );
    if (!sure || !mounted) {
      return;
    }
    setState(() => _leaving = true);
    try {
      await ref.read(circlesRepositoryProvider).leaveCircle(widget.circleId);
      ref
        ..invalidate(circleSummariesProvider)
        ..invalidate(conversationsProvider)
        ..invalidate(circleTakedownsProvider);
      if (mounted) {
        context.go(HomeScreen.path);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _leaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorText(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Scaffold(
      key: const ValueKey('circle-suspended'),
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
                    icon: Icons.block_rounded,
                    title: tr('This circle was suspended'),
                    message: tr(
                      'WeCord suspended it. Nobody can open it for now. You '
                      'can leave it if you do not want it in your list.',
                    ),
                    action: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        WeCordButton(
                          key: const ValueKey('circle-suspended-leave'),
                          label: tr('Leave circle'),
                          variant: WeCordButtonVariant.onPaper,
                          loading: _leaving,
                          onPressed: _leaving ? null : _leave,
                        ),
                        WeCordButton(
                          label: tr('Back to home'),
                          onPressed: () => context.go(HomeScreen.path),
                        ),
                      ],
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
