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
    final preview = ref.watch(circleInvitePreviewProvider(widget.code));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Circle invite'))),
      body: Center(
        // Scrolls on short phones and with large text.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: preview.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, stackTrace) => _InviteMessage(
                icon: Icons.error_outline,
                title: tr('Could not load invite'),
                message: error.toString(),
                action: FilledButton(
                  onPressed: () =>
                      ref.invalidate(circleInvitePreviewProvider(widget.code)),
                  child: Text(tr('Try again')),
                ),
              ),
              data: (preview) {
                final circle = preview.circle;
                if (circle == null || !preview.canJoin) {
                  return _InviteMessage(
                    icon: Icons.link_off,
                    title: tr('Invite invalid'),
                    message: _invalidMessage(preview.invalidReason),
                    action: OutlinedButton(
                      onPressed: () => context.go(HomeScreen.path),
                      child: Text(tr('Back to home')),
                    ),
                  );
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: circle.avatarUrl == null
                              ? null
                              : NetworkImage(circle.avatarUrl!),
                          child: circle.avatarUrl == null
                              ? Text(
                                  _initial(circle.name),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          preview.alreadyMember
                              ? tr('You are already a member of')
                              : tr('You have been invited to join'),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          circle.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          circle.memberCount == 1
                              ? tr('1 member')
                              : tr('{count} members', {
                                  'count': circle.memberCount,
                                }),
                        ),
                        if (_errorText != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorText!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: preview.alreadyMember
                              ? FilledButton(
                                  onPressed: () => context.go(
                                    '${CircleRoutes.path}/${circle.id}',
                                  ),
                                  child: Text(tr('Open circle')),
                                )
                              : FilledButton(
                                  onPressed: _isJoining ? null : _join,
                                  child: Text(
                                    _isJoining
                                        ? tr('Joining…')
                                        : tr('Join circle'),
                                  ),
                                ),
                        ),
                      ],
                    ),
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

class _InviteMessage extends StatelessWidget {
  const _InviteMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        action,
      ],
    );
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

String _initial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}
