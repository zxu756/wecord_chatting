import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/forms/form_widgets.dart' show FormPageFrame;
import 'package:wecord/features/workflows/workflow_editor_page.dart';
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/features/workflows/workflow_summary.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the workflows of a circle or a group chat.
Future<void> openWorkflows(BuildContext context, WorkflowScope scope) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => WorkflowListPage(scope: scope),
    ),
  );
}

/// The workflows of one place: what starts each, whether it runs, and a
/// switch to pause it. Tapping one opens it; the plus makes a new one.
class WorkflowListPage extends ConsumerWidget {
  const WorkflowListPage({required this.scope, super.key});

  final WorkflowScope scope;

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    Workflow workflow,
    bool on,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(workflowRepositoryProvider)
          .setEnabled(workflow.id, enabled: on);
    } on WorkflowException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr("That didn't work. Try again."))),
      );
    }
    ref.invalidate(workflowListProvider(scope));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    Workflow? workflow,
  ]) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (context) =>
            WorkflowEditorPage(scope: scope, workflow: workflow),
      ),
    );
    ref.invalidate(workflowListProvider(scope));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final list = ref.watch(workflowListProvider(scope));
    final options = ref.watch(workflowOptionsProvider(scope)).value;
    final data = list.value;
    return FormPageFrame(
      pageKey: const ValueKey('workflow-list-page'),
      title: tr('Workflows'),
      subtitle: scope.isCircle
          ? tr('Do things for you when something happens')
          : tr('Do things in this group when something happens'),
      actions: [
        if (data != null && data.canManage)
          WeCordIconButton(
            key: const ValueKey('workflow-add'),
            tooltip: tr('New workflow'),
            icon: Icons.add_rounded,
            variant: WeCordButtonVariant.ghost,
            onPressed: () => unawaited(_edit(context, ref)),
          ),
      ],
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is WorkflowException
                      ? error.message
                      : tr("That didn't work. Try again."),
                  key: const ValueKey('workflow-list-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.dangerText),
                ),
                const SizedBox(height: 12),
                WeCordButton(
                  label: tr('Try again'),
                  onPressed: () => ref.invalidate(workflowListProvider(scope)),
                ),
              ],
            ),
          ),
        ),
        data: (data) => ListView(
          key: const ValueKey('workflow-list'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            if (data.workflows.isEmpty)
              Padding(
                key: const ValueKey('workflow-empty'),
                padding: const EdgeInsets.fromLTRB(8, 32, 8, 16),
                child: Column(
                  children: [
                    Icon(Icons.bolt_rounded, size: 40, color: c.subtle),
                    const SizedBox(height: 12),
                    Text(
                      tr('No workflows yet'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        'Welcome new members, thank people for a reaction, send a form every Friday.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: c.subtle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    WeCordButton(
                      key: const ValueKey('workflow-empty-add'),
                      label: tr('New workflow'),
                      variant: WeCordButtonVariant.accent,
                      onPressed: () => unawaited(_edit(context, ref)),
                    ),
                  ],
                ),
              )
            else
              SettingsGroup(
                color: c.well,
                children: [
                  for (final workflow in data.workflows)
                    _WorkflowRow(
                      workflow: workflow,
                      options: options,
                      onOpen: () => unawaited(_edit(context, ref, workflow)),
                      onToggle: (on) =>
                          unawaited(_toggle(context, ref, workflow, on)),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(
                tr(
                  'Up to {count} workflows here. Each runs as the person who last saved it, and pauses if they lose the right to manage this place.',
                  {
                    'count': scope.isCircle
                        ? data.limits.maxPerCircle
                        : data.limits.maxPerGroup,
                  },
                ),
                style: TextStyle(fontSize: 12.5, height: 1.4, color: c.subtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowRow extends StatelessWidget {
  const _WorkflowRow({
    required this.workflow,
    required this.options,
    required this.onOpen,
    required this.onToggle,
  });

  final Workflow workflow;
  final WorkflowOptions? options;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final trigger = workflowTriggerSummary(
      context,
      workflow.trigger,
      options ?? const WorkflowOptions(),
    );
    final status = workflow.enabled
        ? (workflow.lastStatus == 'failed'
              ? tr('Running. The last run failed.')
              : tr('Running'))
        : (workflow.pausedReason?.label ?? tr('Paused'));
    return SettingsRow(
      key: ValueKey('workflow-row-${workflow.id}'),
      icon: workflow.needsAttention
          ? Icons.warning_amber_rounded
          : Icons.bolt_rounded,
      tone: workflow.needsAttention
          ? SettingsTone.warning
          : SettingsTone.neutral,
      title: workflow.name,
      subtitle: '$trigger\n$status',
      onTap: onOpen,
      showChevron: false,
      trailing: WeCordSwitch(
        key: ValueKey('workflow-switch-${workflow.id}'),
        value: workflow.enabled,
        semanticLabel: tr('{name} is running', {'name': workflow.name}),
        onChanged: onToggle,
      ),
    );
  }
}
