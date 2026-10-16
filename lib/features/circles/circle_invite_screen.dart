import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_invite.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/ui/ui.dart';

final circleInvitePreviewProvider = FutureProvider.autoDispose
    .family<CircleInvitePreview, String>((ref, code) {
      return ref.watch(circlesRepositoryProvider).getInvitePreview(code);
    });

class CircleInviteScreen extends ConsumerStatefulWidget {
  const CircleInviteScreen({required this.code, super.key});

  static const path = circleInviteRoutePrefix;

  final String code;

  @override
  ConsumerState<CircleInviteScreen> createState() => _CircleInviteScreenState();
}

class _CircleInviteScreenState extends ConsumerState<CircleInviteScreen> {
  var _isJoining = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final preview = ref.watch(circleInvitePreviewProvider(widget.code));
    return CirclePageScaffold(
      title: tr('Circle invite'),
      constrainBody: false,
      body: Center(
        // Scrolls on short phones and with large text.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: preview.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, stackTrace) => CircleEmptyState(
                icon: Icons.error_outline_rounded,
                title: tr('Could not load invite'),
                message: error.toString(),
                action: WeCordButton(
                  variant: WeCordButtonVariant.onPaper,
                  onPressed: () =>
                      ref.invalidate(circleInvitePreviewProvider(widget.code)),
                  label: tr('Try again'),
                ),
              ),
              data: (preview) {
                final circle = preview.circle;
                if (circle == null || !preview.canJoin) {
                  return CircleEmptyState(
                    icon: Icons.link_off_rounded,
                    title: tr('Invite invalid'),
                    message: _invalidMessage(preview.invalidReason),
                    action: WeCordButton(
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: () => context.go(HomeScreen.path),
                      label: tr('Back to home'),
                    ),
                  );
                }
                return Container(
                  decoration: BoxDecoration(
                    color: c.panel,
                    borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            height: 96,
                            color: WeCordAvatarColors.forSeed(circle.name),
                          ),
                          Positioned(
                            bottom: -36,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: ShapeDecoration(
                                color: c.panel,
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: CircleNetworkAvatar(
                                name: circle.name,
                                url: circle.avatarUrl,
                                size: 72,
                                thing: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              preview.alreadyMember
                                  ? tr('You are already a member of')
                                  : tr('You have been invited to join'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: c.muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              circle.name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                PresenceDot(color: c.faint, size: 9),
                                const SizedBox(width: 6),
                                Text(
                                  circle.memberCount == 1
                                      ? tr('1 member')
                                      : tr('{count} members', {
                                          'count': circle.memberCount,
                                        }),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: c.muted,
                                  ),
                                ),
                              ],
                            ),
                            if (_errorText != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _errorText!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: c.dangerText,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            preview.alreadyMember
                                ? WeCordButton(
                                    expand: true,
                                    size: WeCordButtonSize.large,
                                    onPressed: () => context.go(
                                      '${CircleRoutes.path}/${circle.id}',
                                    ),
                                    label: tr('Open circle'),
                                  )
                                : WeCordButton(
                                    expand: true,
                                    size: WeCordButtonSize.large,
                                    variant: WeCordButtonVariant.accent,
                                    onPressed: _isJoining ? null : _join,
                                    label: _isJoining
                                        ? tr('Joining…')
                                        : tr('Join circle'),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _join() async {
    setState(() {
      _isJoining = true;
      _errorText = null;
    });
    try {
      final circleId = await ref
          .read(circlesRepositoryProvider)
          .acceptInvite(widget.code);
      ref.invalidate(circleSummariesProvider);
      if (mounted) context.go('${CircleRoutes.path}/$circleId');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
        _errorText = '$error'.contains('Banned from this circle')
            ? tr("You're banned from this circle.")
            : tr('Could not join this circle. {error}', {'error': error});
      });
      ref.invalidate(circleInvitePreviewProvider(widget.code));
    }
  }
}

String _invalidMessage(CircleInviteInvalidReason? reason) {
  return switch (reason) {
    CircleInviteInvalidReason.expired => tr('This invite has expired.'),
    CircleInviteInvalidReason.revoked => tr('This invite was revoked.'),
    CircleInviteInvalidReason.exhausted => tr(
      'This invite has reached its usage limit.',
    ),
    CircleInviteInvalidReason.notFound ||
    null => tr('This invite does not exist or is no longer available.'),
  };
}
