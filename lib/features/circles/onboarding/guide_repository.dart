import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';

/// Who may edit a circle's guide. The server decides again on every call;
/// attaching roles to an answer also needs manage_roles.
extension CircleGuidePermissions on CircleDetail {
  bool get canEditGuide => can(CirclePermission.manageCircle);
  bool get canAttachGuideRoles => can(CirclePermission.manageRoles);
}

/// The calls behind the questions, the newcomer tasks and the greeting.
class CircleGuideRepository {
  const CircleGuideRepository(this._rpc);

  final CircleRpc _rpc;

  Future<CircleGuide> load(String circleId) async {
    final result = await _rpc('get_circle_guide', {
      'target_circle_id': circleId,
    });
    return CircleGuide.fromJson(rpcObject(result));
  }

  /// Saves the member's picks; the server makes their roles match. Returns
  /// the names of the roles they now have from it, and the ones taken back.
  Future<({List<String> added, List<String> removed})> answer(
    String circleId,
    Iterable<String> optionIds,
  ) async {
    final result = await _rpc('complete_onboarding_prompts', {
      'target_circle_id': circleId,
      'option_ids': optionIds.toList(),
    });
    final map = result is Map ? Map<String, dynamic>.from(result) : const {};
    List<String> names(Object? value) => [
      if (value is List)
        for (final role in value)
          if (role is Map && role['name'] is String) role['name'] as String,
    ];
    return (added: names(map['added']), removed: names(map['removed']));
  }

  Future<void> completeTask(String circleId, String taskId) async {
    await _rpc('complete_guide_task', {
      'target_circle_id': circleId,
      'target_task_id': taskId,
    });
  }

  Future<void> dismiss(String circleId, {bool dismissed = true}) async {
    await _rpc('dismiss_circle_guide', {
      'target_circle_id': circleId,
      'dismissed': dismissed,
    });
  }

  Future<CircleGuideConfig> loadConfig(String circleId) async {
    final result = await _rpc('get_circle_guide_config', {
      'target_circle_id': circleId,
    });
    return CircleGuideConfig.fromJson(rpcObject(result));
  }

  Future<void> savePrompts(
    String circleId,
    List<GuidePromptDraftData> prompts,
  ) async {
    await _rpc('set_circle_guide_prompts', {
      'target_circle_id': circleId,
      'prompt_list': [for (final prompt in prompts) prompt.toJson()],
    });
  }

  Future<void> saveTasks(
    String circleId,
    List<GuideTaskDraftData> tasks,
  ) async {
    await _rpc('set_circle_guide_tasks', {
      'target_circle_id': circleId,
      'task_list': [for (final task in tasks) task.toJson()],
    });
  }

  /// Where new members are announced (null: nowhere) and the sticker the
  /// card's "Say hello" sends.
  Future<void> saveGreeting(
    String circleId, {
    String? channelId,
    String? stickerId,
  }) async {
    await _rpc('set_circle_greeting', {
      'target_circle_id': circleId,
      'target_channel_id': channelId,
      'target_sticker_id': stickerId,
    });
  }
}

final circleGuideRepositoryProvider = Provider<CircleGuideRepository>((ref) {
  return CircleGuideRepository(ref.watch(circleRpcProvider));
});

/// The circle's guide for the current member. Null when it cannot be read:
/// the guide is a helper, never a reason to break the circle.
final circleGuideProvider = FutureProvider.autoDispose
    .family<CircleGuide?, String>((ref, circleId) async {
      try {
        return await ref.watch(circleGuideRepositoryProvider).load(circleId);
      } on Object {
        return null;
      }
    });

/// The editor's view of the guide.
final circleGuideConfigProvider = FutureProvider.autoDispose
    .family<CircleGuideConfig, String>((ref, circleId) {
      return ref.watch(circleGuideRepositoryProvider).loadConfig(circleId);
    });
