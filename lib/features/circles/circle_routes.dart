import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_creation_sheet.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Circle locations; a circle lives at `/circles/<id>`.
abstract final class CircleRoutes {
  static const path = '/circles';
}

enum _AddCircleChoice { create, join }

/// Asks whether to create a circle or join one with an invite, then does it.
Future<void> showAddCircleSheet(BuildContext context) async {
  final choice = await showWeCordSheet<_AddCircleChoice>(
    context,
    builder: (sheetContext, _) {
      final c = sheetContext.tokens.colors;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Semantics(
                header: true,
                child: Text(
                  tr('Add a circle'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
              child: Text(
                tr('Start your own, or join one you were invited to.'),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  icon: Icons.add_rounded,
                  tone: SettingsTone.accent,
                  title: tr('Create a circle'),
                  subtitle: tr('Channels, voice and events for your people.'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_AddCircleChoice.create),
                ),
                SettingsRow(
                  icon: Icons.add_link_rounded,
                  tone: SettingsTone.success,
                  title: tr('Join with invite'),
                  subtitle: tr('Paste an invite code or link.'),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_AddCircleChoice.join),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  if (choice == null || !context.mounted) {
    return;
  }
  switch (choice) {
    case _AddCircleChoice.create:
      await showWeCordSheet<void>(
        context,
        builder: (context, _) => const CircleCreationSheet(),
      );
    case _AddCircleChoice.join:
      await joinCircleWithInvite(context);
  }
}

/// Asks for an invite code or link and opens its invite page.
Future<void> joinCircleWithInvite(BuildContext context) async {
  final code = await showCircleDialog<String>(
    context,
    builder: (context) => const _JoinWithInviteDialog(),
  );
  if (code != null && context.mounted) {
    await context.push(circleInvitePath(code));
  }
}

class _JoinWithInviteDialog extends StatefulWidget {
  const _JoinWithInviteDialog();

  @override
  State<_JoinWithInviteDialog> createState() => _JoinWithInviteDialogState();
}

class _JoinWithInviteDialogState extends State<_JoinWithInviteDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = parseCircleInviteCode(_controller.text);
    if (code == null) {
      setState(() => _errorText = tr('Enter an invite code or link'));
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Join with invite'),
      content: WeCordTextField(
        controller: _controller,
        autofocus: true,
        label: tr('Invite code or link'),
        errorText: _errorText,
        prefixIcon: Icons.link_rounded,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(label: tr('Join'), onPressed: _submit),
      ],
    );
  }
}
