import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/voice.dart';

final stageRepositoryProvider = Provider<StageRepository>((ref) {
  try {
    return SupabaseStageRepository(
      SupabaseStageDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const UninitializedStageRepository();
  }
});

/// How often live stages are reloaded without a change, so a stage whose
/// channel emptied ends.
const stageInstancesRefreshInterval = Duration(seconds: 30);

/// The circle's live stages the current user can see, by channel id.
/// Reloads on changes and every [stageInstancesRefreshInterval].
final stageInstancesProvider = FutureProvider.autoDispose
    .family<Map<String, StageInstance>, String>((ref, circleId) {
      final repository = ref.watch(stageRepositoryProvider);
      final subscription = repository
          .stageChanges(circleId)
          .listen((_) => ref.invalidateSelf(), onError: (Object _) {});
      final timer = Timer(stageInstancesRefreshInterval, ref.invalidateSelf);
      ref.onDispose(() {
        subscription.cancel();
        timer.cancel();
      });
      return repository.listStages(circleId);
    });

/// No stage is live in the channel (any more).
class StageNotLiveException implements Exception {
  const StageNotLiveException();

  @override
  String toString() => tr('No stage is live right now.');
}

/// What stage moderators and the audience do on a stage. Moderators are
/// members with Mute Members and Move Members in the channel.
abstract interface class StageRepository {
  /// Live stages by channel id.
  Future<Map<String, StageInstance>> listStages(String circleId);

  /// Fires when a stage in the circle starts, changes topic or ends.
  Stream<void> stageChanges(String circleId);

  /// Starts a stage about [topic], or changes the live one's topic.
  Future<void> startStage({required String channelId, required String topic});

  /// Ends the stage; returns who was speaking.
  Future<List<String>> endStage(String channelId);

  /// Raises (or lowers) the current user's hand. Throws
  /// [StageNotLiveException] when no stage is live.
  Future<void> setHandRaised({required String channelId, required bool raised});

  /// Invites [userId] to speak; true when they became a speaker at once
  /// (they had raised their hand, or it is the current user).
  Future<bool> inviteToSpeak({
    required String channelId,
    required String userId,
  });

  /// Accepts or declines an invitation to speak; true when now a speaker.
  Future<bool> respondToInvite({
    required String channelId,
    required bool accept,
  });

  /// Moves [userId] (a speaker) back to the audience.
  Future<void> moveToAudience({
    required String channelId,
    required String userId,
  });
}

abstract interface class StageDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  Stream<void> stageChanges(String circleId);
}

class SupabaseStageRepository implements StageRepository {
  const SupabaseStageRepository(this._dataSource);

  final StageDataSource _dataSource;

  @override
  Future<Map<String, StageInstance>> listStages(String circleId) async {
    final data = await _dataSource.rpc('list_stage_instances', {
      'target_circle_id': circleId,
    });
    if (data is! Map) {
      return const {};
    }
    return {
      for (final MapEntry(:key, :value) in data.entries)
        if (key is String && value is Map)
          key: StageInstance.fromJson(Map<String, dynamic>.from(value)),
    };
  }

  @override
  Stream<void> stageChanges(String circleId) {
    return _dataSource.stageChanges(circleId);
  }

  @override
  Future<void> startStage({
    required String channelId,
    required String topic,
  }) async {
    await _dataSource.rpc('start_stage', {
      'target_channel_id': channelId,
      'stage_topic': topic.trim(),
    });
  }

  @override
  Future<List<String>> endStage(String channelId) async {
    final speakers = await _dataSource.rpc('end_stage', {
      'target_channel_id': channelId,
    });
    return [
      if (speakers is List)
        for (final speaker in speakers)
          if (speaker is String) speaker,
    ];
  }

  @override
  Future<void> setHandRaised({
    required String channelId,
    required bool raised,
  }) async {
    try {
      await _dataSource.rpc('set_stage_hand_raised', {
        'target_channel_id': channelId,
        'raised': raised,
      });
    } on PostgrestException catch (error) {
      if (error.code == '55000') {
        throw const StageNotLiveException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> inviteToSpeak({
    required String channelId,
    required String userId,
  }) async {
    try {
      final speaking = await _dataSource.rpc('invite_stage_speaker', {
        'target_channel_id': channelId,
        'target_user_id': userId,
      });
      return speaking == true;
    } on PostgrestException catch (error) {
      if (error.code == '55000') {
        throw const StageNotLiveException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> respondToInvite({
    required String channelId,
    required bool accept,
  }) async {
    final speaking = await _dataSource.rpc('respond_stage_invite', {
      'target_channel_id': channelId,
      'accept': accept,
    });
    return speaking == true;
  }

  @override
  Future<void> moveToAudience({
    required String channelId,
    required String userId,
  }) async {
    await _dataSource.rpc('set_stage_audience', {
      'target_channel_id': channelId,
      'target_user_id': userId,
    });
  }
}

class SupabaseStageDataSource implements StageDataSource {
  const SupabaseStageDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc(functionName, params: params);
  }

  @override
  Stream<void> stageChanges(String circleId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('stage-instances-$circleId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'stage_instances',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'circle_id',
                value: circleId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }
}

class UninitializedStageRepository implements StageRepository {
  const UninitializedStageRepository();

  @override
  Future<Map<String, StageInstance>> listStages(String circleId) async {
    return const {};
  }

  @override
  Stream<void> stageChanges(String circleId) => const Stream<void>.empty();

  @override
  Future<void> startStage({
    required String channelId,
    required String topic,
  }) async {}

  @override
  Future<List<String>> endStage(String channelId) async => const [];

  @override
  Future<void> setHandRaised({
    required String channelId,
    required bool raised,
  }) async {}

  @override
  Future<bool> inviteToSpeak({
    required String channelId,
    required String userId,
  }) async => false;

  @override
  Future<bool> respondToInvite({
    required String channelId,
    required bool accept,
  }) async => false;

  @override
  Future<void> moveToAudience({
    required String channelId,
    required String userId,
  }) async {}
}
