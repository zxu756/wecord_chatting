import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/features/groups/group_invitations.dart'
    show spansFromTemplate;
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The answer to a request to join a circle, or the request while it waits,
/// in Notifications: approved opens the circle (where the rules and the
/// welcome message wait), turned down shows the moderator's note.
class JoinRequestInboxCard extends ConsumerStatefulWidget {
  const JoinRequestInboxCard({required this.request, super.key});

  final MyJoinRequest request;

  @override
  ConsumerState<JoinRequestInboxCard> createState() =>
      _JoinRequestInboxCardState();
}

class _JoinRequestInboxCardState extends ConsumerState<JoinRequestInboxCard> {
  var _busy = false;

  void _refresh() {
    ref
      ..invalidate(myJoinRequestsProvider)
      ..invalidate(circleSummariesProvider);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Something went wrong. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      _refresh();
    }
  }

  Future<void> _open() async {
    final request = widget.request;
    // Opening the circle is how the answer is read.
    unawaited(
      ref
          .read(joinRequestsRepositoryProvider)
          .dismiss(request.id)
          .then((_) => _refresh())
          .catchError((Object _) {}),
    );
    if (mounted) {
      openPage(context, '${CircleRoutes.path}/${request.circleId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final request = widget.request;
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    final template = switch (request.status) {
      JoinRequestStatus.pending => tr(
        'Your request to join {circle} is waiting for review',
      ),
      JoinRequestStatus.approved => tr(
        '{circle} approved your request to join',
      ),
      JoinRequestStatus.denied => tr(
        '{circle} turned down your request to join',
      ),
    };
    final note = request.note?.trim() ?? '';
    final spoken = template.replaceAll('{circle}', request.circleName);
    final (badgeIcon, badgeColor) = switch (request.status) {
      JoinRequestStatus.pending => (Icons.hourglass_top_rounded, c.warning),
      JoinRequestStatus.approved => (Icons.check_rounded, c.success),
      JoinRequestStatus.denied => (Icons.close_rounded, c.danger),
    };
    final approved = request.status == JoinRequestStatus.approved;
    return Semantics(
      container: true,
      label: spoken,
      child: InboxCardShell(
        key: ValueKey('inbox-join-request-${request.id}'),
        highlighted: approved,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleNetworkAvatar(
                  name: request.circleName,
                  url: request.circleAvatarUrl,
                  size: 44,
                  thing: true,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.panel, width: 2.5),
                    ),
                    child: Icon(badgeIcon, size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text.rich(
                    TextSpan(
                      children: spansFromTemplate(template, {
                        'circle': TextSpan(
                          text: request.circleName,
                          style: bold,
                        ),
                      }),
                    ),
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spokenAge(request.at),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      key: const ValueKey('join-request-note'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(WeCordRadii.md),
                      ),
                      child: Text(
                        note,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                  if (approved) ...[
                    const SizedBox(height: 4),
                    Text(
                      tr('Open it to read the rules and say hello.'),
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: switch (request.status) {
                        JoinRequestStatus.pending => WeCordButton(
                          key: const ValueKey('join-request-cancel'),
                          label: tr('Cancel request'),
                          variant: WeCordButtonVariant.secondary,
                          size: WeCordButtonSize.small,
                          onPressed: _busy
                              ? null
                              : () => unawaited(
                                  _run(
                                    () => ref
                                        .read(joinRequestsRepositoryProvider)
                                        .cancel(request.circleId),
                                  ),
                                ),
                        ),
                        JoinRequestStatus.approved => WeCordButton(
                          key: const ValueKey('join-request-open'),
                          label: tr('Open circle'),
                          size: WeCordButtonSize.small,
                          onPressed: _busy ? null : () => unawaited(_open()),
                        ),
                        JoinRequestStatus.denied => WeCordButton(
                          key: const ValueKey('join-request-dismiss'),
                          label: tr('Got it'),
                          variant: WeCordButtonVariant.secondary,
                          size: WeCordButtonSize.small,
                          onPressed: _busy
                              ? null
                              : () => unawaited(
                                  _run(
                                    () => ref
                                        .read(joinRequestsRepositoryProvider)
                                        .dismiss(request.id),
                                  ),
                                ),
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
