import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart'
    show messageReviewCountProvider;
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/join_requests/join_requests_repository.dart'
    show joinRequestCountProvider;
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/features/circles/mod_tools/raid_protection.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The Review page body with the moderator tools' own things above [child]:
/// the raid banner and the ban appeals, in a panel that scrolls on its own
/// (a little over a quarter of the screen at most), so the join requests and the held
/// messages below keep their room.
class ModToolsReviewHost extends ConsumerWidget {
  const ModToolsReviewHost({
    required this.circleId,
    required this.child,
    this.now,
    super.key,
  });

  final String circleId;
  final Widget child;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final security = ref.watch(circleSecurityProvider(circleId)).value;
    final appeals =
        ref.watch(banAppealsProvider(circleId)).value ?? const <BanAppeal>[];
    final showBanner = security != null && security.active;
    if (!showBanner && appeals.isEmpty) {
      return child;
    }
    // Join requests take up to 55% below; without any, there is more room.
    final waiting = ref.watch(joinRequestCountProvider(circleId)).value ?? 0;
    final height = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: height * (waiting == 0 ? 0.5 : 0.28),
          ),
          child: SingleChildScrollView(
            key: const ValueKey('mod-tools-panel'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RaidStatusBanner(circleId: circleId, now: now),
                if (appeals.isNotEmpty)
                  BanAppealsSection(
                    circleId: circleId,
                    appeals: appeals,
                    now: now,
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// "Ban appeals" with a red count and one card per appeal.
class BanAppealsSection extends StatelessWidget {
  const BanAppealsSection({
    required this.circleId,
    required this.appeals,
    this.now,
    super.key,
  });

  final String circleId;
  final List<BanAppeal> appeals;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: circlePagePadding(context).copyWith(bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: Row(
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    tr('Ban appeals'),
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
                  key: const ValueKey('ban-appeals-count'),
                  count: appeals.length,
                  tone: BadgeTone.mention,
                  semanticLabel: tr('{count} waiting', {
                    'count': appeals.length,
                  }),
                ),
              ],
            ),
          ),
          for (final appeal in appeals) ...[
            BanAppealCard(
              key: ValueKey('ban-appeal-${appeal.id}'),
              appeal: appeal,
              circleId: circleId,
              now: now,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// One appeal: who, the ban, what they wrote, and Deny / Lift ban.
class BanAppealCard extends ConsumerStatefulWidget {
  const BanAppealCard({
    required this.appeal,
    required this.circleId,
    this.now,
    super.key,
  });

  final BanAppeal appeal;
  final String circleId;
  final DateTime Function()? now;

  @override
  ConsumerState<BanAppealCard> createState() => _BanAppealCardState();
}

class _BanAppealCardState extends ConsumerState<BanAppealCard> {
  /// 'approve' or 'deny' while the request runs.
  String? _busy;

  void _refresh() {
    ref
      ..invalidate(banAppealsProvider(widget.circleId))
      ..invalidate(banAppealCountProvider(widget.circleId))
      ..invalidate(messageReviewCountProvider(widget.circleId));
  }

  Future<void> _decide({required bool approve}) async {
    final appeal = widget.appeal;
    final messenger = ScaffoldMessenger.maybeOf(context);
    String? note;
    if (approve) {
      final confirmed = await confirmCircleAction(
        context,
        title: tr('Lift the ban on {name}?', {'name': appeal.name}),
        message: tr('They can join again the way anyone can. They are told.'),
        confirmLabel: tr('Lift ban'),
        destructive: false,
      );
      if (!confirmed || !mounted) {
        return;
      }
    } else {
      note = await showCircleDialog<String>(
        context,
        builder: (context) => _DeclineDialog(name: appeal.name),
      );
      if (note == null || !mounted) {
        return;
      }
    }
    setState(() => _busy = approve ? 'approve' : 'deny');
    try {
      await ref
          .read(modToolsRepositoryProvider)
          .decideAppeal(appeal.id, approve: approve, note: note);
      _refresh();
      if (mounted) {
        setState(() => _busy = null);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? tr('Lifted the ban on {name}.', {'name': appeal.name})
                : tr('Appeal turned down.'),
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _busy = null);
      }
      // Somebody else may have decided first, or the ban is theirs.
      _refresh();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr("Couldn't update this appeal. It may already be decided."),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final appeal = widget.appeal;
    final now = (widget.now ?? DateTime.now)();
    final busy = _busy != null;
    final reason = appeal.banReason?.trim() ?? '';
    return CircleCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleNetworkAvatar(
                name: appeal.name,
                url: appeal.avatarUrl,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appeal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${appeal.username} · '
                      '${formatAuditTime(appeal.createdAt, now: now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [
              banEndLabel(appeal.banExpiresAt, now: now),
              if (appeal.bannedByName case final by?)
                tr('Banned by {name}', {'name': by}),
              if (reason.isNotEmpty) tr('Reason: {reason}', {'reason': reason}),
            ].join(' · '),
            key: const ValueKey('ban-appeal-ban'),
            style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('ban-appeal-message'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Text(
              appeal.message,
              style: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('ban-appeal-deny'),
                  label: tr('Deny'),
                  variant: WeCordButtonVariant.secondary,
                  icon: Icons.close_rounded,
                  loading: _busy == 'deny',
                  onPressed: busy
                      ? null
                      : () => unawaited(_decide(approve: false)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WeCordButton(
                  key: const ValueKey('ban-appeal-approve'),
                  label: tr('Lift ban'),
                  icon: Icons.check_rounded,
                  loading: _busy == 'approve',
                  onPressed: busy
                      ? null
                      : () => unawaited(_decide(approve: true)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for an optional reason before turning an appeal down; pops the
/// reason (possibly empty), or null when cancelled.
class _DeclineDialog extends StatefulWidget {
  const _DeclineDialog({required this.name});

  final String name;

  @override
  State<_DeclineDialog> createState() => _DeclineDialogState();
}

class _DeclineDialogState extends State<_DeclineDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr("Turn down {name}'s appeal?", {'name': widget.name}),
      message: tr(
        'They are told, and can add no second appeal for this ban. You can '
        'add a reason they will read.',
      ),
      content: WeCordTextField(
        fieldKey: const ValueKey('ban-appeal-note'),
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
          key: const ValueKey('ban-appeal-deny-confirm'),
          label: tr('Deny'),
          onPressed: () => Navigator.of(context).pop(_note.text),
        ),
      ],
    );
  }
}
