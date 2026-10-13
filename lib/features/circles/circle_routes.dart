import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/circles/circle_creation_sheet.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';

/// Circle locations; a circle lives at `/circles/<id>`.
abstract final class CircleRoutes {
  static const path = '/circles';
}

enum _AddCircleChoice { create, join }

/// Asks whether to create a circle or join one with an invite, then does it.
Future<void> showAddCircleSheet(BuildContext context) async {
  final choice = await showModalBottomSheet<_AddCircleChoice>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              'Add a circle',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              'Start your own, or join one you were invited to.',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Create a circle'),
            onTap: () =>
                Navigator.of(sheetContext).pop(_AddCircleChoice.create),
          ),
          ListTile(
            leading: const Icon(Icons.add_link),
            title: const Text('Join with invite'),
            onTap: () => Navigator.of(sheetContext).pop(_AddCircleChoice.join),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) {
    return;
  }
  switch (choice) {
    case _AddCircleChoice.create:
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => const CircleCreationSheet(),
      );
    case _AddCircleChoice.join:
      await joinCircleWithInvite(context);
  }
}

/// Asks for an invite code or link and opens its invite page.
Future<void> joinCircleWithInvite(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
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
      setState(() => _errorText = 'Enter an invite code or link');
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Join with invite'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Invite code or link',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Join')),
      ],
    );
  }
}
