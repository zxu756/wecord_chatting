import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/workflows/workflow_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Where a workflow lives: a circle or a group chat, never both.
@immutable
class WorkflowScope {
  const WorkflowScope.circle(String id) : circleId = id, conversationId = null;

  const WorkflowScope.group(String id) : circleId = null, conversationId = id;

  final String? circleId;
  final String? conversationId;

  bool get isCircle => circleId != null;

  @override
  bool operator ==(Object other) =>
      other is WorkflowScope &&
      other.circleId == circleId &&
      other.conversationId == conversationId;

  @override
  int get hashCode => Object.hash(circleId, conversationId);
}

/// Workflows on the server: the `*_workflow*` functions of migration
/// 202610281310.
abstract interface class WorkflowRepository {
  Future<WorkflowList> list(WorkflowScope scope);

  Future<WorkflowOptions> options(WorkflowScope scope);

  /// Makes or changes a workflow; [id] null makes one. The saver becomes the
  /// person its actions run as.
  Future<Workflow> save(
    WorkflowScope scope, {
    String? id,
    required String name,
    required WorkflowTrigger trigger,
    required List<WorkflowAction> actions,
    bool? enabled,
  });

  Future<Workflow> setEnabled(String id, {required bool enabled});

  Future<void> delete(String id);

  Future<List<WorkflowRun>> runs(String id, {int limit = 30, DateTime? before});
}

class SupabaseWorkflowRepository implements WorkflowRepository {
  SupabaseWorkflowRepository(this._client);

  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw WorkflowException.fromPostgrest(error);
    }
  }

  Map<String, dynamic> _scopeParams(WorkflowScope scope) => {
    'p_circle_id': scope.circleId,
    'p_conversation_id': scope.conversationId,
  };

  @override
  Future<WorkflowList> list(WorkflowScope scope) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'list_workflows',
        params: _scopeParams(scope),
      );
      return WorkflowList.fromJson(Map<String, dynamic>.from(data! as Map));
    });
  }

  @override
  Future<WorkflowOptions> options(WorkflowScope scope) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'get_workflow_options',
        params: _scopeParams(scope),
      );
      return WorkflowOptions.fromJson(Map<String, dynamic>.from(data! as Map));
    });
  }

  @override
  Future<Workflow> save(
    WorkflowScope scope, {
    String? id,
    required String name,
    required WorkflowTrigger trigger,
    required List<WorkflowAction> actions,
    bool? enabled,
  }) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'save_workflow',
        params: {
          'p_workflow': {
            'id': ?id,
            if (id == null && scope.circleId != null)
              'circle_id': scope.circleId,
            if (id == null && scope.conversationId != null)
              'conversation_id': scope.conversationId,
            'name': name,
            'trigger': trigger.toJson(),
            'actions': [for (final action in actions) action.toJson()],
            'enabled': ?enabled,
          },
        },
      );
      return Workflow.fromJson(data)!;
    });
  }

  @override
  Future<Workflow> setEnabled(String id, {required bool enabled}) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'set_workflow_enabled',
        params: {'p_workflow_id': id, 'p_enabled': enabled},
      );
      return Workflow.fromJson(data)!;
    });
  }

  @override
  Future<void> delete(String id) {
    return _guard(() async {
      await _client.rpc<Object?>(
        'delete_workflow',
        params: {'p_workflow_id': id},
      );
    });
  }

  @override
  Future<List<WorkflowRun>> runs(
    String id, {
    int limit = 30,
    DateTime? before,
  }) {
    return _guard(() async {
      final data = await _client.rpc<Object?>(
        'list_workflow_runs',
        params: {
          'p_workflow_id': id,
          'p_limit': limit,
          'p_before': before?.toUtc().toIso8601String(),
        },
      );
      return [
        for (final item in (data as List?) ?? const [])
          if (item is Map)
            WorkflowRun.fromJson(Map<String, dynamic>.from(item)),
      ];
    });
  }
}

class _UninitializedWorkflowRepository implements WorkflowRepository {
  const _UninitializedWorkflowRepository();

  static Never _fail() =>
      throw StateError('Supabase must be initialized before using workflows.');

  @override
  Future<WorkflowList> list(WorkflowScope scope) => _fail();

  @override
  Future<WorkflowOptions> options(WorkflowScope scope) => _fail();

  @override
  Future<Workflow> save(
    WorkflowScope scope, {
    String? id,
    required String name,
    required WorkflowTrigger trigger,
    required List<WorkflowAction> actions,
    bool? enabled,
  }) => _fail();

  @override
  Future<Workflow> setEnabled(String id, {required bool enabled}) => _fail();

  @override
  Future<void> delete(String id) => _fail();

  @override
  Future<List<WorkflowRun>> runs(
    String id, {
    int limit = 30,
    DateTime? before,
  }) => _fail();
}

final workflowRepositoryProvider = Provider<WorkflowRepository>((ref) {
  try {
    return SupabaseWorkflowRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedWorkflowRepository();
  }
});

/// The workflows of a circle or group (managers only).
final workflowListProvider = FutureProvider.autoDispose
    .family<WorkflowList, WorkflowScope>((ref, scope) {
      return ref.watch(workflowRepositoryProvider).list(scope);
    });

/// The channels, roles and forms the editor can pick.
final workflowOptionsProvider = FutureProvider.autoDispose
    .family<WorkflowOptions, WorkflowScope>((ref, scope) {
      return ref.watch(workflowRepositoryProvider).options(scope);
    });

/// The newest runs of one workflow.
final workflowRunsProvider = FutureProvider.autoDispose
    .family<List<WorkflowRun>, String>((ref, id) {
      return ref.watch(workflowRepositoryProvider).runs(id);
    });
