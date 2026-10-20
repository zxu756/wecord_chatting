import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/guard2/guard2_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "What the guard checks" in the AI guard's settings: polls, the titles of
/// events, notes and tasks, and pictures (AI guard 2.0). Every change is
/// saved at once and goes back when saving fails. Shows nothing until the
/// settings are read, and nothing for people who cannot read them.
class GuardScopeSection extends ConsumerStatefulWidget {
  const GuardScopeSection({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<GuardScopeSection> createState() => _GuardScopeSectionState();
}

class _GuardScopeSectionState extends ConsumerState<GuardScopeSection> {
  CircleAiGuardScope? _scope;
  var _saving = false;

  Future<void> _change(CircleAiGuardScope next) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final previous = _scope;
    setState(() {
      _scope = next;
      _saving = true;
    });
    try {
      final saved = await ref
          .read(guard2RepositoryProvider)
          .saveScope(widget.circleId, next);
      if (mounted) {
        setState(() => _scope = saved);
      }
      ref.invalidate(circleAiGuardScopeProvider(widget.circleId));
    } on Object {
      if (mounted) {
        setState(() => _scope = previous);
      }
      messenger?.showSnackBar(
        SnackBar(content: Text(tr("Couldn't save the AI guard. Try again."))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(circleAiGuardScopeProvider(widget.circleId));
    final scope = _scope ?? loaded.value;
    if (scope == null) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey('ai-guard-scope'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('Also checks')),
        SettingsGroup(
          footer: tr(
            'Pictures from new members go to the AI provider only while '
            'this is on, and WeCord does not keep them. If the AI cannot '
            'read a picture, it is shown as usual and marked as not '
            'checked.',
          ),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('ai-guard-scope-polls'),
              icon: Icons.poll_outlined,
              title: tr('Polls'),
              subtitle: tr('The question and the options.'),
              value: scope.polls,
              onChanged: _saving
                  ? null
                  : (value) => unawaited(_change(scope.copyWith(polls: value))),
            ),
            SettingsRow.toggle(
              key: const ValueKey('ai-guard-scope-items'),
              icon: Icons.event_note_outlined,
              title: tr('Titles of events, notes and tasks'),
              subtitle: tr(
                'Checked after they are made. What the AI flags is listed '
                'for moderators; it is never hidden.',
              ),
              value: scope.items,
              onChanged: _saving
                  ? null
                  : (value) => unawaited(_change(scope.copyWith(items: value))),
            ),
            SettingsRow.toggle(
              key: const ValueKey('ai-guard-scope-images'),
              icon: Icons.image_outlined,
              title: tr('Pictures'),
              subtitle: scope.visionAvailable
                  ? tr(
                      "Sent to the AI provider's picture model. Costs more "
                      'than text.',
                    )
                  : tr(
                      'Not set up on this server yet, so pictures are sent '
                      'as usual.',
                    ),
              value: scope.images,
              onChanged: _saving
                  ? null
                  : (value) =>
                        unawaited(_change(scope.copyWith(images: value))),
            ),
          ],
        ),
      ],
    );
  }
}
