import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "WeCord AI in this group", the group owner's switch in the group's
/// settings. When it is off, mentioning @WeCord AI in the group gets no
/// answer. Shown only to the owner, and only where the server has AI set up.
class AiAssistantGroupRow extends ConsumerStatefulWidget {
  const AiAssistantGroupRow({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<AiAssistantGroupRow> createState() =>
      _AiAssistantGroupRowState();
}

class _AiAssistantGroupRowState extends ConsumerState<AiAssistantGroupRow> {
  bool? _value;
  var _saving = false;

  Future<void> _set(bool enabled) async {
    final before = _value ?? true;
    setState(() {
      _value = enabled;
      _saving = true;
    });
    try {
      await ref
          .read(assistantRepositoryProvider)
          .setGroupAssistantEnabled(widget.conversationId, enabled: enabled);
      ref.invalidate(groupAssistantEnabledProvider(widget.conversationId));
    } on Object {
      if (mounted) {
        setState(() => _value = before);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not save. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(aiStatusProvider).value == null) {
      return const SizedBox.shrink();
    }
    final stored = ref
        .watch(groupAssistantEnabledProvider(widget.conversationId))
        .value;
    return SettingsRow.toggle(
      key: const ValueKey('group-detail-ai'),
      icon: Icons.auto_awesome_rounded,
      tone: SettingsTone.accent,
      title: tr('WeCord AI in this group'),
      subtitle: tr(
        'Members can mention @WeCord AI to ask a question, summarize or list to-dos. Everyone sees the answer. Turn off to stop it answering here.',
      ),
      value: _value ?? stored ?? true,
      onChanged: _saving || stored == null
          ? null
          : (value) => unawaited(_set(value)),
    );
  }
}
