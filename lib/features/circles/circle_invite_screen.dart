import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/join_requests/join_gate.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
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
  var _isCancelling = false;
  String? _errorText;

  /// Answers to the circle's questions, by question id.
  var _answers = <String, String>{};

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
                message: errorText(error),
                action: WeCordButton(
                  variant: WeCordButtonVariant.onPaper,
                  onPressed: () =>
                      ref.invalidate(circleInvitePreviewProvider(widget.code)),
                  label: tr('Try again'),
                ),
              ),
              data: (preview) {
                final circle = preview.circle;
                final joinKey = (
                  circleId: circle?.id ?? '',
                  inviteCode: widget.code,
                );
                // Where the person stands: null while unknown, then the
                // button joins the way it always did.
                final joinState = circle == null || preview.alreadyMember
                    ? null
                    : ref.watch(circleJoinStateProvider(joinKey)).value;
                final plan = planJoinButton(
                  joinState,
                  viaInvite: true,
                  now: DateTime.now().toUtc(),
                );
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
                            if (joinState != null) ...[
                              const SizedBox(height: 16),
                              _joinPanel(joinState, joinKey),
                            ],
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
                                    onPressed:
                                        _isJoining ||
                                            !plan.enabled ||
                                            (plan.kind ==
                                                    JoinButtonKind
                                                        .sendRequest &&
                                                !joinAnswersComplete(
                                                  joinState!.questions,
                                                  _answers,
                                                ))
                                        ? null
                                        : () => _join(joinKey, joinState),
                                    label: _isJoining
                                        ? (plan.kind ==
                                                  JoinButtonKind.sendRequest
                                              ? tr('Sending…')
                                              : tr('Joining…'))
                                        : plan.label,
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

  /// The questions to answer, a request already waiting, or a refusal.
  Widget _joinPanel(CircleJoinState state, JoinStateKey key) {
    if (state.isPending || state.isDenied || state.closed) {
      return JoinStatusPanel(
        state: state,
        viaInvite: true,
        cancelling: _isCancelling,
        onCancel: () => unawaited(_cancelRequest(key)),
      );
    }
    if (!state.needsReview) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.questions.isEmpty
              ? tr('The moderators of this circle approve everyone who joins.')
              : tr(
                  'The moderators of this circle approve everyone who joins. '
                  'Answer their questions to send your request.',
                ),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: context.tokens.colors.muted,
          ),
        ),
        if (state.questions.isNotEmpty) ...[
          const SizedBox(height: 14),
          JoinQuestionsForm(
            questions: state.questions,
            enabled: !_isJoining,
            onChanged: (answers) => setState(() => _answers = answers),
          ),
        ],
      ],
    );
  }

  Future<void> _cancelRequest(JoinStateKey key) async {
    setState(() => _isCancelling = true);
    try {
      await ref.read(joinRequestsRepositoryProvider).cancel(key.circleId);
    } on Object {
      // The next look at the state shows where it stands.
    }
    ref
      ..invalidate(circleJoinStateProvider(key))
      ..invalidate(myJoinRequestsProvider);
    if (mounted) {
      setState(() => _isCancelling = false);
    }
  }

  Future<void> _join(JoinStateKey key, CircleJoinState? state) async {
    setState(() {
      _isJoining = true;
      _errorText = null;
    });
    try {
      final reviewed = state?.needsReview ?? false;
      final circleId = reviewed
          ? await ref
                .read(joinRequestsRepositoryProvider)
                .acceptInvite(widget.code, answers: _answers)
          : await ref.read(circlesRepositoryProvider).acceptInvite(widget.code);
      ref
        ..invalidate(circleSummariesProvider)
        ..invalidate(myJoinRequestsProvider);
      if (reviewed) {
        // A request was made, not a membership: show it waiting (unless the
        // server let the person straight in).
        ref.invalidate(circleJoinStateProvider(key));
        final after = await ref.read(circleJoinStateProvider(key).future);
        if (!mounted) return;
        if (after?.isMember ?? false) {
          context.go('${CircleRoutes.path}/$circleId');
          return;
        }
        setState(() => _isJoining = false);
        return;
      }
      if (mounted) context.go('${CircleRoutes.path}/$circleId');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isJoining = false;
        _errorText =
            joinErrorMessage(error) ??
            tr('Could not join this circle. {error}', {
              'error': errorText(error),
            });
      });
      ref
        ..invalidate(circleInvitePreviewProvider(widget.code))
        ..invalidate(circleJoinStateProvider(key));
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
