import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/member_honors/honor_models.dart';
import 'package:wecord/features/member_honors/honor_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Asks for [member]'s title in this circle and saves it. Returns whether
/// something was saved. A blank title takes it off.
Future<bool> changeMemberTitle(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required CircleMember member,
  String? currentTitle,
}) async {
  final title = await showCircleDialog<String>(
    context,
    builder: (context) => _TitleDialog(
      member: member,
      isSelf: member.isCurrentUser,
      currentTitle: currentTitle,
    ),
  );
  if (title == null || !context.mounted) {
    return false;
  }
  return _save(
    context,
    ref,
    circleId: circleId,
    userId: member.profile.id,
    title: title,
  );
}

/// Takes the current user's own title off; anyone may.
Future<bool> removeOwnMemberTitle(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required String userId,
}) {
  return _save(context, ref, circleId: circleId, userId: userId, title: '');
}

Future<bool> _save(
  BuildContext context,
  WidgetRef ref, {
  required String circleId,
  required String userId,
  required String title,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(memberHonorsRepositoryProvider)
        .setTitle(circleId: circleId, userId: userId, title: title);
    ref.invalidate(circleMemberFlairProvider(circleId));
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          title.trim().isEmpty ? tr('Title removed.') : tr('Title saved.'),
        ),
      ),
    );
    return true;
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not change the title. Try again.'))),
    );
    return false;
  }
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog({
    required this.member,
    required this.isSelf,
    required this.currentTitle,
  });

  final CircleMember member;
  final bool isSelf;
  final String? currentTitle;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late final _controller = TextEditingController(text: widget.currentTitle);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    final problem = memberTitleProblem(text);
    if (problem != null) {
      setState(
        () => _error = problem == 'length'
            ? tr('A title is up to 10 characters.')
            : tr('This title uses characters that are not allowed.'),
      );
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.member.displayName;
    return CircleDialog(
      title: tr('Set title'),
      message: widget.isSelf
          ? tr('Shown next to your name in this circle.')
          : tr('Shown next to {name} in this circle.', {'name': name}),
      content: WeCordTextField(
        controller: _controller,
        autofocus: true,
        maxLength: maxMemberTitleLength,
        label: trIn('honors', 'Title'),
        hint: tr('Founder, Photo editor…'),
        errorText: _error,
        onChanged: (_) {
          if (_error != null) {
            setState(() => _error = null);
          }
        },
        onSubmitted: (_) => _save(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (widget.currentTitle != null)
          CircleDialogAction(
            key: const ValueKey('title-remove'),
            label: tr('Remove title'),
            onPressed: () => Navigator.of(context).pop(''),
          ),
        CircleDialogAction.primary(
          key: const ValueKey('title-save'),
          label: tr('Save'),
          onPressed: _save,
        ),
      ],
    );
  }
}
