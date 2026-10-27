import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/forms/form_widgets.dart' show FormPageFrame;
import 'package:wecord/features/later/later_time.dart' show describeWhen;
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The run log of one workflow: when it ran, for whom, what each step did
/// and why a run or a step was left out. Newest first; the server keeps 30
/// days.
class WorkflowRunsPage extends ConsumerWidget {
  const WorkflowRunsPage({required this.workflow, super.key});

  final Workflow workflow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final runs = ref.watch(workflowRunsProvider(workflow.id));
    return FormPageFrame(
      pageKey: const ValueKey('workflow-runs-page'),
      title: tr('Run log'),
      subtitle: workflow.name,
      actions: [
        WeCordIconButton(
          key: const ValueKey('workflow-runs-refresh'),
          tooltip: tr('Refresh'),
          icon: Icons.refresh_rounded,
          variant: WeCordButtonVariant.ghost,
          onPressed: () => ref.invalidate(workflowRunsProvider(workflow.id)),
        ),
      ],
      child: runs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is WorkflowException
                  ? error.message
                  : tr("That didn't work. Try again."),
              key: const ValueKey('workflow-runs-error'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.dangerText),
            ),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Padding(
                  key: const ValueKey('workflow-runs-empty'),
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr('It has not run yet.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.subtle),
                  ),
                ),
              )
            : ListView(
                key: const ValueKey('workflow-runs-list'),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (workflow.pausedReason != null && !workflow.enabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        workflow.pausedReason!.label,
                        key: const ValueKey('workflow-runs-paused'),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: c.warningText,
                        ),
                      ),
                    ),
                  SettingsGroup(
                    color: c.well,
                    children: [for (final run in items) _RunRow(run: run)],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text(
                      tr('Runs are kept for 30 days.'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: c.subtle,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final WorkflowRun run;

  @override
  Widget build(BuildContext context) {
    final when = describeWhen(
      MaterialLocalizations.of(context),
      run.createdAt,
      DateTime.now(),
    );
    final lines = <String>[
      if (run.actorName != null) run.actorName!,
      ?run.reasonLabel,
      for (final step in run.steps)
        if (step.status != 'ok')
          '${step.kind?.label ?? step.action}: '
              '${step.status == 'skipped' && step.detail != null ? workflowStepDetail(step.detail!) : tr('Failed')}',
    ];
    final tone = switch (run.status) {
      'succeeded' => SettingsTone.success,
      'failed' => SettingsTone.danger,
      _ => SettingsTone.neutral,
    };
    final icon = switch (run.status) {
      'succeeded' => Icons.check_rounded,
      'failed' => Icons.error_outline_rounded,
      'skipped' => Icons.remove_rounded,
      _ => Icons.hourglass_empty_rounded,
    };
    return SettingsRow(
      key: ValueKey('workflow-run-${run.id}'),
      icon: icon,
      tone: tone,
      title: '${run.statusLabel} · $when',
      subtitle: lines.isEmpty ? null : lines.join('\n'),
      showChevron: false,
    );
  }
}
