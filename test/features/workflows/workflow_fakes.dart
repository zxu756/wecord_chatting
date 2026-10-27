import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/features/workflows/workflow_repository.dart';

/// The workflows of one place in memory, with the rules the server enforces
/// (managers only, at most five steps, a name, a limit per place).
class FakeWorkflowRepository implements WorkflowRepository {
  FakeWorkflowRepository({
    List<Workflow>? workflows,
    this.canManage = true,
    WorkflowOptions? options,
    this.limits = const WorkflowLimits(),
  }) : items = [...?workflows],
       optionsData = options ?? sampleWorkflowOptions();

  final List<Workflow> items;
  bool canManage;
  final WorkflowOptions optionsData;
  final WorkflowLimits limits;

  /// The runs by workflow id.
  final runsById = <String, List<WorkflowRun>>{};

  /// Makes the next call of this kind fail.
  Object? listError;
  Object? saveError;

  final calls = <String>[];

  /// What the last save was asked to write.
  ({
    String? id,
    String name,
    WorkflowTrigger trigger,
    List<WorkflowAction> actions,
    bool? enabled,
  })?
  lastSave;

  var _next = 100;

  @override
  Future<WorkflowList> list(WorkflowScope scope) async {
    calls.add('list');
    if (listError != null) {
      throw listError!;
    }
    if (!canManage) {
      throw const WorkflowException(WorkflowFailureKind.notAllowed);
    }
    return WorkflowList(limits: limits, workflows: [...items]);
  }

  @override
  Future<WorkflowOptions> options(WorkflowScope scope) async {
    calls.add('options');
    return optionsData;
  }

  @override
  Future<Workflow> save(
    WorkflowScope scope, {
    String? id,
    required String name,
    required WorkflowTrigger trigger,
    required List<WorkflowAction> actions,
    bool? enabled,
  }) async {
    calls.add('save');
    if (saveError != null) {
      throw saveError!;
    }
    if (!canManage) {
      throw const WorkflowException(WorkflowFailureKind.notAllowed);
    }
    if (name.trim().isEmpty) {
      throw const WorkflowException(WorkflowFailureKind.textInvalid);
    }
    if (actions.isEmpty || actions.length > limits.maxActions) {
      throw const WorkflowException(WorkflowFailureKind.actionsInvalid);
    }
    if (id == null &&
        items.length >=
            (scope.isCircle ? limits.maxPerCircle : limits.maxPerGroup)) {
      throw const WorkflowException(WorkflowFailureKind.limitReached);
    }
    lastSave = (
      id: id,
      name: name,
      trigger: trigger,
      actions: actions,
      enabled: enabled,
    );
    final saved = sampleWorkflow(
      id ?? 'wf-${_next++}',
      name,
      trigger: trigger,
      actions: actions,
      enabled: enabled ?? true,
      circleId: scope.circleId,
      conversationId: scope.conversationId,
    );
    final index = items.indexWhere((w) => w.id == saved.id);
    if (index >= 0) {
      items[index] = saved;
    } else {
      items.add(saved);
    }
    return saved;
  }

  @override
  Future<Workflow> setEnabled(String id, {required bool enabled}) async {
    calls.add(enabled ? 'resume' : 'pause');
    final index = items.indexWhere((w) => w.id == id);
    final old = items[index];
    final changed = sampleWorkflow(
      old.id,
      old.name,
      trigger: old.trigger,
      actions: old.actions,
      enabled: enabled,
      pausedReason: enabled ? null : WorkflowPauseReason.manual,
      circleId: old.circleId,
      conversationId: old.conversationId,
    );
    items[index] = changed;
    return changed;
  }

  @override
  Future<void> delete(String id) async {
    calls.add('delete');
    items.removeWhere((w) => w.id == id);
  }

  @override
  Future<List<WorkflowRun>> runs(
    String id, {
    int limit = 30,
    DateTime? before,
  }) async {
    calls.add('runs');
    return runsById[id] ?? const [];
  }
}

WorkflowOptions sampleWorkflowOptions() => const WorkflowOptions(
  channels: [
    WorkflowChannel(id: 'ch-1', name: 'welcome'),
    WorkflowChannel(id: 'ch-2', name: 'general'),
  ],
  roles: [
    WorkflowRoleOption(id: 'role-1', name: 'Newbie'),
    WorkflowRoleOption(id: 'role-2', name: 'Regular'),
  ],
  forms: [
    WorkflowFormOption(id: 'form-1', title: 'Weekly report'),
    WorkflowFormOption(id: 'form-2', title: 'Sign-up'),
  ],
);

Workflow sampleWorkflow(
  String id,
  String name, {
  WorkflowTrigger trigger = const WorkflowTrigger(
    WorkflowTriggerKind.memberJoined,
  ),
  List<WorkflowAction>? actions,
  bool enabled = true,
  WorkflowPauseReason? pausedReason,
  String? circleId = 'circle-1',
  String? conversationId,
  String? lastStatus,
  int runsToday = 0,
}) => Workflow(
  id: id,
  name: name,
  trigger: trigger,
  actions:
      actions ??
      const [
        WorkflowAction(WorkflowActionKind.sendMessage, {
          'channel_id': 'ch-1',
          'text': 'Welcome, {member}!',
        }),
      ],
  enabled: enabled,
  pausedReason: pausedReason,
  circleId: circleId,
  conversationId: conversationId,
  creatorName: 'Ada',
  createdByMe: true,
  lastStatus: lastStatus,
  runsToday: runsToday,
);

List<Override> workflowOverrides(FakeWorkflowRepository repository) => [
  workflowRepositoryProvider.overrideWithValue(repository),
];
