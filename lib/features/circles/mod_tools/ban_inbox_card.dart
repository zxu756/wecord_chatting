import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/features/groups/group_invitations.dart'
    show spansFromTemplate;
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "You were banned from a circle" in Notifications: when the ban ends, and
/// the one appeal a ban allows, with the answer once the moderators gave it.
class BanInboxCard extends ConsumerStatefulWidget {
  const BanInboxCard({required this.ban, this.now, super.key});

  final MyCircleBan ban;
  final DateTime Function()? now;

  @override
  ConsumerState<BanInboxCard> createState() => _BanInboxCardState();
}

class _BanInboxCardState extends ConsumerState<BanInboxCard> {
  Future<void> _appeal() async {
    final ban = widget.ban;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = await showCircleDialog<String>(
      context,
      builder: (context) => _AppealDialog(circleName: ban.circleName),
    );
    if (message == null || message.trim().isEmpty || !mounted) {
      return;
    }
    try {
      await ref
          .read(modToolsRepositoryProvider)
          .submitAppeal(ban.circleId, message);
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Appeal sent. You will be told here.'))),
      );
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not send the appeal. Try again.'))),
      );
    } finally {
      ref.invalidate(myCircleBansProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final ban = widget.ban;
    final now = (widget.now ?? DateTime.now)();
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    final template = ban.expiresAt == null
        ? tr('You were banned from {circle}')
        : tr('You were banned from {circle} for a while');
    final spoken = template.replaceAll('{circle}', ban.circleName);
    final note = ban.appealNote?.trim() ?? '';
    final status = ban.appealStatus;
    final statusLine = switch (status) {
      AppealStatus.pending => tr('Your appeal is waiting for the moderators.'),
      AppealStatus.denied => tr('Your appeal was turned down.'),
      AppealStatus.approved => tr('Your appeal was approved.'),
      _ => null,
    };
    return Semantics(
      container: true,
      label: spoken,
      child: InboxCardShell(
        key: ValueKey('inbox-ban-${ban.circleId}'),
        highlighted: ban.canAppeal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleNetworkAvatar(
                  name: ban.circleName,
                  url: ban.circleAvatarUrl,
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
                      color: c.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.panel, width: 2.5),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
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
                        'circle': TextSpan(text: ban.circleName, style: bold),
                      }),
                    ),
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      spokenAge(ban.bannedAt, now: now),
                      banEndLabel(ban.expiresAt, now: now),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                  if (statusLine != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      statusLine,
                      key: const ValueKey('ban-appeal-status'),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      key: const ValueKey('ban-appeal-answer'),
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
                  if (ban.canAppeal) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: WeCordButton(
                        key: const ValueKey('ban-appeal-open'),
                        label: tr('Appeal this ban'),
                        variant: WeCordButtonVariant.secondary,
                        size: WeCordButtonSize.small,
                        onPressed: () => unawaited(_appeal()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What to tell the moderators; pops the text, or null when cancelled.
class _AppealDialog extends StatefulWidget {
  const _AppealDialog({required this.circleName});

  final String circleName;

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Appeal your ban from {circle}', {'circle': widget.circleName}),
      message: tr(
        'You can send one appeal for each ban. The moderators read it and '
        'answer here.',
      ),
      content: WeCordTextField(
        fieldKey: const ValueKey('ban-appeal-text'),
        controller: _message,
        minLines: 3,
        maxLines: 6,
        inputFormatters: [LengthLimitingTextInputFormatter(1000)],
        hint: tr('Say what you would like them to know'),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('ban-appeal-send'),
          label: tr('Send appeal'),
          onPressed: _message.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_message.text),
        ),
      ],
    );
  }
}
