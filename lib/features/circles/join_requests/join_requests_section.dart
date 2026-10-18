import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_request_models.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The Review page body with the circle's join requests above [child] (the
/// held and flagged messages). Shows nothing extra without requests or
/// without the permission to review them.
class JoinRequestsHost extends StatelessWidget {
  const JoinRequestsHost({
    required this.circleId,
    required this.child,
    this.now,
    super.key,
  });

  final String circleId;
  final Widget child;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JoinRequestsSection(circleId: circleId, now: now),
        Expanded(child: child),
      ],
    );
  }
}

/// "Join requests" with a red count and one card per request, each with
/// the person, their answers, Deny and Approve.
class JoinRequestsSection extends ConsumerWidget {
  const JoinRequestsSection({required this.circleId, this.now, super.key});

  final String circleId;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(pendingJoinRequestsProvider(circleId));
    return requests.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) {
        // Without the permission there is simply no such section.
        if ('$error'.contains('42501')) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: circlePagePadding(context).copyWith(bottom: 0),
          child: CircleCard(
            key: const ValueKey('join-requests-error'),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Could not load join requests.'),
                    style: TextStyle(
                      fontSize: 14,
                      color: context.tokens.colors.dangerText,
                    ),
                  ),
                ),
                WeCordButton(
                  label: tr('Try again'),
                  variant: WeCordButtonVariant.ghost,
                  size: WeCordButtonSize.small,
                  onPressed: () =>
                      ref.invalidate(pendingJoinRequestsProvider(circleId)),
                ),
              ],
            ),
          ),
        );
      },
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        final height = MediaQuery.sizeOf(context).height;
        final c = context.tokens.colors;
        // A framed panel that scrolls on its own, so a card cut by its edge
        // reads as "more below" and the held messages keep their place.
        return Padding(
          padding: circlePagePadding(context).copyWith(bottom: 0),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.55),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(WeCordRadii.xl + 6),
                border: Border.all(color: c.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.xl + 5),
                child: ListView.separated(
                  key: const ValueKey('join-requests'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                  itemCount: items.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _SectionHeader(count: items.length);
                    }
                    final item = items[index - 1];
                    return JoinRequestCard(
                      key: ValueKey('join-request-${item.id}'),
                      request: item,
                      circleId: circleId,
                      now: now,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      child: Row(
        children: [
          Semantics(
            header: true,
            child: Text(
              tr('Join requests'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CountBadge(
            key: const ValueKey('join-requests-count'),
            count: count,
            tone: BadgeTone.mention,
            semanticLabel: tr('{count} waiting', {'count': count}),
          ),
        ],
      ),
    );
  }
}

/// One person waiting to join.
class JoinRequestCard extends ConsumerStatefulWidget {
  const JoinRequestCard({
    required this.request,
    required this.circleId,
    this.now,
    super.key,
  });

  final PendingJoinRequest request;
  final String circleId;
  final DateTime Function()? now;

  @override
  ConsumerState<JoinRequestCard> createState() => _JoinRequestCardState();
}

class _JoinRequestCardState extends ConsumerState<JoinRequestCard> {
  /// 'approve' or 'deny' while the request runs.
  String? _busy;

  void _refresh() {
    ref
      ..invalidate(pendingJoinRequestsProvider(widget.circleId))
      ..invalidate(joinRequestCountProvider(widget.circleId))
      ..invalidate(messageReviewCountProvider(widget.circleId));
  }

  Future<void> _approve() async {
    final request = widget.request;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = 'approve');
    try {
      await ref
          .read(joinRequestsRepositoryProvider)
          .decide(request.id, approve: true);
      _refresh();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('{name} can join now.', {'name': request.name})),
        ),
      );
    } on Object {
      _failed(messenger);
    }
  }

  Future<void> _deny() async {
    final request = widget.request;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final note = await showCircleDialog<String>(
      context,
      builder: (context) => _DenyDialog(name: request.name),
    );
    if (note == null || !mounted) {
      return;
    }
    setState(() => _busy = 'deny');
    try {
      await ref
          .read(joinRequestsRepositoryProvider)
          .decide(request.id, approve: false, note: note);
      _refresh();
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Request turned down.'))),
      );
    } on Object {
      _failed(messenger);
    }
  }

  void _failed(ScaffoldMessengerState? messenger) {
    if (mounted) {
      setState(() => _busy = null);
    }
    // Somebody else may have decided first.
    _refresh();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          tr("Couldn't update this request. It may already be decided."),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final request = widget.request;
    final now = (widget.now ?? DateTime.now)();
    final busy = _busy != null;
    final account = request.accountCreatedAt;
    return CircleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PersonAvatar(
                name: request.name,
                size: 40,
                image: request.avatarUrl == null
                    ? null
                    : NetworkImage(request.avatarUrl!),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${request.username} · '
                      '${formatAuditTime(request.createdAt, now: now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (request.invitedByName case final inviter?) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person_add_alt_1_outlined, size: 16, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('Invited by {name}', {'name': inviter}),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ],
            ),
          ],
          if (request.answers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('join-request-answers'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, entry) in request.answers.indexed) ...[
                    if (index > 0) const SizedBox(height: 10),
                    Text(
                      entry.prompt,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.subtle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.answer,
                      style: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (request.invitedByName == null) ...[
            const SizedBox(height: 10),
            Text(
              tr('No answers.'),
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          ],
          if (account != null) ...[
            const SizedBox(height: 10),
            Text(
              tr('Account created {time}', {
                'time': formatAuditTime(account, now: now),
              }),
              style: TextStyle(fontSize: 12.5, color: c.subtle),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('join-request-deny'),
                  label: tr('Deny'),
                  variant: WeCordButtonVariant.secondary,
                  icon: Icons.close_rounded,
                  loading: _busy == 'deny',
                  onPressed: busy ? null : () => unawaited(_deny()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('join-request-approve'),
                  label: tr('Approve'),
                  icon: Icons.check_rounded,
                  loading: _busy == 'approve',
                  onPressed: busy ? null : () => unawaited(_approve()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for an optional reason before turning a request down; pops the
/// reason (possibly empty), or null when cancelled.
class _DenyDialog extends StatefulWidget {
  const _DenyDialog({required this.name});

  final String name;

  @override
  State<_DenyDialog> createState() => _DenyDialogState();
}

class _DenyDialogState extends State<_DenyDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Turn down {name}?', {'name': widget.name}),
      message: tr(
        'They are told. You can add a reason they will read. They can ask '
        'again after a day.',
      ),
      content: WeCordTextField(
        fieldKey: const ValueKey('join-deny-note'),
        controller: _note,
        minLines: 2,
        maxLines: 4,
        inputFormatters: [LengthLimitingTextInputFormatter(500)],
        hint: tr('Reason (optional)'),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.danger(
          key: const ValueKey('join-deny-confirm'),
          label: tr('Deny'),
          onPressed: () => Navigator.of(context).pop(_note.text),
        ),
      ],
    );
  }
}
