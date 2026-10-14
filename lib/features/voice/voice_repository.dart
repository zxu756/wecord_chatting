import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/voice.dart';

final voiceRepositoryProvider = Provider<VoiceRepository>((ref) {
  try {
    return SupabaseVoiceRepository(
      SupabaseVoiceDataSource(ref.watch(supabaseClientProvider)),
    );
  } on AssertionError {
    return const UninitializedVoiceRepository();
  }
});

/// How often the voice member list is reloaded without a change, so members
/// whose app vanished (no heartbeat for a minute) drop off.
const voiceStatesRefreshInterval = Duration(seconds: 30);

/// Who is in the circle's voice channels the current user can see. Reloads
/// on changes and every [voiceStatesRefreshInterval].
final voiceStatesProvider = FutureProvider.autoDispose
    .family<List<VoiceMemberState>, String>((ref, circleId) {
      final repository = ref.watch(voiceRepositoryProvider);
      final subscription = repository.voiceStateChanges(circleId).listen((_) {
        ref.invalidateSelf();
      });
      final timer = Timer(voiceStatesRefreshInterval, ref.invalidateSelf);
      ref.onDispose(() {
        subscription.cancel();
        timer.cancel();
      });
      return repository.listVoiceStates(circleId);
    });

/// How often active calls are reloaded without a change, so ringing stops
/// and calls whose members vanished end.
const directCallsRefreshInterval = Duration(seconds: 15);

/// Calls going on in the current user's direct and group chats. Reloads on
/// changes and every [directCallsRefreshInterval].
final activeDirectCallsProvider = FutureProvider.autoDispose<List<DirectCall>>((
  ref,
) {
  final repository = ref.watch(voiceRepositoryProvider);
  final subscription = repository.directCallChanges().listen((_) {
    ref.invalidateSelf();
  });
  final timer = Timer(directCallsRefreshInterval, ref.invalidateSelf);
  ref.onDispose(() {
    subscription.cancel();
    timer.cancel();
  });
  return repository.listActiveDirectCalls();
});

/// The call going on in [conversationId], if any.
final directCallInProvider = Provider.autoDispose.family<DirectCall?, String>((
  ref,
  conversationId,
) {
  final calls = ref.watch(activeDirectCallsProvider).valueOrNull ?? const [];
  for (final call in calls) {
    if (call.conversationId == conversationId) {
      return call;
    }
  }
  return null;
});

/// The voice service (LiveKit) has not been set up for this project yet.
class VoiceNotConfiguredException implements Exception {
  const VoiceNotConfiguredException();

  @override
  String toString() => "Voice service isn't configured yet.";
}

/// The current user may not connect to the voice channel (any more).
class VoiceAccessDeniedException implements Exception {
  const VoiceAccessDeniedException();

  @override
  String toString() => 'You cannot connect to this voice channel.';
}

abstract interface class VoiceRepository {
  /// A LiveKit server and token for the voice channel. Throws
  /// [VoiceNotConfiguredException] when voice is not set up and
  /// [VoiceAccessDeniedException] without `connect_voice`.
  Future<VoiceConnectionDetails> fetchConnectionDetails(String channelId);

  /// Marks the current user as in the voice channel (and in no other).
  /// Throws [VoiceAccessDeniedException] without `connect_voice`.
  Future<void> joinVoiceState(String channelId);

  /// Saves the current user's flags and heartbeat. False when they have no
  /// voice state any more (it went stale or they lost access).
  Future<bool> updateVoiceState({
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  });

  Future<void> leaveVoiceState();

  Future<List<VoiceMemberState>> listVoiceStates(String circleId);

  /// Fires when someone joins, leaves or changes their flags in the
  /// circle's voice channels (not on bare heartbeats).
  Stream<void> voiceStateChanges(String circleId);

  /// Joins the conversation's call, starting it (and ringing the others)
  /// when there is none; leaves any other call or voice channel. Returns
  /// the call id. Throws [VoiceAccessDeniedException] when the current user
  /// may not call there (not a member, blocked, a deleted account).
  Future<String> startDirectCall(String conversationId);

  /// Rejoins a call that is still going; false once it ended.
  Future<bool> joinDirectCall(String callId);

  /// A LiveKit server and token for the call's room.
  Future<VoiceConnectionDetails> fetchCallConnectionDetails(String callId);

  /// Saves the current user's flags and heartbeat in the call. False when
  /// they are not in it any more.
  Future<bool> updateDirectCallState({
    required String callId,
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  });

  Future<void> leaveDirectCall(String callId);

  /// Stops the call ringing for the current user.
  Future<void> declineDirectCall(String callId);

  /// Calls going on in the current user's direct and group chats.
  Future<List<DirectCall>> listActiveDirectCalls();

  /// Fires when calls start or end, or someone joins or leaves one.
  Stream<void> directCallChanges();
}

abstract interface class VoiceDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);

  /// Throws [FunctionException] for non-2xx responses.
  Future<Object?> invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  );

  Stream<void> voiceStateChanges(String circleId);

  Stream<void> directCallChanges();
}

class SupabaseVoiceRepository implements VoiceRepository {
  const SupabaseVoiceRepository(this._dataSource);

  final VoiceDataSource _dataSource;

  @override
  Future<VoiceConnectionDetails> fetchConnectionDetails(
    String channelId,
  ) async {
    final Object? data;
    try {
      data = await _dataSource.invokeFunction('livekit-token', {
        'channel_id': channelId,
      });
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      if (error.status == 503 && code == 'voice_not_configured') {
        throw const VoiceNotConfiguredException();
      }
      if (error.status == 403) {
        throw const VoiceAccessDeniedException();
      }
      rethrow;
    }
    if (data is! Map || data['url'] is! String || data['token'] is! String) {
      throw StateError('Unexpected voice token response.');
    }
    return VoiceConnectionDetails(
      url: data['url'] as String,
      token: data['token'] as String,
    );
  }

  @override
  Future<void> joinVoiceState(String channelId) async {
    try {
      await _dataSource.rpc('join_voice_state', {
        'target_channel_id': channelId,
      });
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const VoiceAccessDeniedException();
      }
      rethrow;
    }
  }

  @override
  Future<bool> updateVoiceState({
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  }) async {
    final updated = await _dataSource.rpc('update_voice_state', {
      'target_self_mute': selfMute,
      'target_self_deaf': selfDeaf,
      'target_video': video,
      'target_screen': screen,
    });
    return updated == true;
  }

  @override
  Future<void> leaveVoiceState() async {
    await _dataSource.rpc('leave_voice_state', const {});
  }

  @override
  Future<List<VoiceMemberState>> listVoiceStates(String circleId) async {
    final rows = await _dataSource.rpc('list_voice_states', {
      'target_circle_id': circleId,
    });
    if (rows is! List) {
      return const [];
    }
    return [
      for (final row in rows)
        if (row is Map)
          VoiceMemberState.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Stream<void> voiceStateChanges(String circleId) {
    return _dataSource.voiceStateChanges(circleId);
  }

  @override
  Future<String> startDirectCall(String conversationId) async {
    final Object? callId;
    try {
      callId = await _dataSource.rpc('start_direct_call', {
        'target_conversation_id': conversationId,
      });
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw const VoiceAccessDeniedException();
      }
      rethrow;
    }
    if (callId is! String) {
      throw StateError('Unexpected call response.');
    }
    return callId;
  }

  @override
  Future<bool> joinDirectCall(String callId) async {
    final joined = await _dataSource.rpc('join_direct_call', {
      'target_call_id': callId,
    });
    return joined == true;
  }

  @override
  Future<VoiceConnectionDetails> fetchCallConnectionDetails(
    String callId,
  ) async {
    final Object? data;
    try {
      data = await _dataSource.invokeFunction('livekit-token', {
        'call_id': callId,
      });
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      if (error.status == 503 && code == 'voice_not_configured') {
        throw const VoiceNotConfiguredException();
      }
      if (error.status == 403) {
        throw const VoiceAccessDeniedException();
      }
      rethrow;
    }
    if (data is! Map || data['url'] is! String || data['token'] is! String) {
      throw StateError('Unexpected voice token response.');
    }
    return VoiceConnectionDetails(
      url: data['url'] as String,
      token: data['token'] as String,
    );
  }

  @override
  Future<bool> updateDirectCallState({
    required String callId,
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  }) async {
    final updated = await _dataSource.rpc('update_direct_call_state', {
      'target_call_id': callId,
      'target_self_mute': selfMute,
      'target_self_deaf': selfDeaf,
      'target_video': video,
      'target_screen': screen,
    });
    return updated == true;
  }

  @override
  Future<void> leaveDirectCall(String callId) async {
    await _dataSource.rpc('leave_direct_call', {'target_call_id': callId});
  }

  @override
  Future<void> declineDirectCall(String callId) async {
    await _dataSource.rpc('decline_direct_call', {'target_call_id': callId});
  }

  @override
  Future<List<DirectCall>> listActiveDirectCalls() async {
    final rows = await _dataSource.rpc('list_active_direct_calls', const {});
    if (rows is! List) {
      return const [];
    }
    return [
      for (final row in rows)
        if (row is Map) DirectCall.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  Stream<void> directCallChanges() => _dataSource.directCallChanges();
}

class SupabaseVoiceDataSource implements VoiceDataSource {
  const SupabaseVoiceDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc(functionName, params: params);
  }

  @override
  Future<Object?> invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.functions.invoke(functionName, body: body);
    return response.data;
  }

  @override
  Stream<void> voiceStateChanges(String circleId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('voice-states-$circleId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'voice_states',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'circle_id',
                value: circleId,
              ),
              callback: (payload) {
                if (!isVoiceHeartbeatOnly(
                  eventType: payload.eventType,
                  oldRecord: payload.oldRecord,
                  newRecord: payload.newRecord,
                )) {
                  controller.add(null);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Stream<void> directCallChanges() {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        // Row level security limits both tables to the current user's
        // conversations.
        channel = _client
            .channel('direct-calls')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'direct_calls',
              callback: (_) => controller.add(null),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'direct_call_participants',
              callback: (payload) {
                if (!isVoiceHeartbeatOnly(
                  eventType: payload.eventType,
                  oldRecord: payload.oldRecord,
                  newRecord: payload.newRecord,
                )) {
                  controller.add(null);
                }
              },
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

/// Whether a voice_states change only moved `last_seen_at` (a heartbeat),
/// which changes nothing anyone sees.
bool isVoiceHeartbeatOnly({
  required PostgresChangeEvent eventType,
  required Map<String, dynamic> oldRecord,
  required Map<String, dynamic> newRecord,
}) {
  if (eventType != PostgresChangeEvent.update || oldRecord.isEmpty) {
    return false;
  }
  for (final key in {...oldRecord.keys, ...newRecord.keys}) {
    if (key == 'last_seen_at') {
      continue;
    }
    if (oldRecord[key] != newRecord[key]) {
      return false;
    }
  }
  return true;
}

class UninitializedVoiceRepository implements VoiceRepository {
  const UninitializedVoiceRepository();

  @override
  Future<VoiceConnectionDetails> fetchConnectionDetails(String channelId) {
    throw StateError('Supabase is not initialized.');
  }

  @override
  Future<void> joinVoiceState(String channelId) async {}

  @override
  Future<bool> updateVoiceState({
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  }) async {
    return false;
  }

  @override
  Future<void> leaveVoiceState() async {}

  @override
  Future<List<VoiceMemberState>> listVoiceStates(String circleId) async {
    return const [];
  }

  @override
  Stream<void> voiceStateChanges(String circleId) {
    return const Stream<void>.empty();
  }

  @override
  Future<String> startDirectCall(String conversationId) {
    throw StateError('Supabase is not initialized.');
  }

  @override
  Future<bool> joinDirectCall(String callId) async => false;

  @override
  Future<VoiceConnectionDetails> fetchCallConnectionDetails(String callId) {
    throw StateError('Supabase is not initialized.');
  }

  @override
  Future<bool> updateDirectCallState({
    required String callId,
    required bool selfMute,
    required bool selfDeaf,
    required bool video,
    required bool screen,
  }) async {
    return false;
  }

  @override
  Future<void> leaveDirectCall(String callId) async {}

  @override
  Future<void> declineDirectCall(String callId) async {}

  @override
  Future<List<DirectCall>> listActiveDirectCalls() async => const [];

  @override
  Stream<void> directCallChanges() => const Stream<void>.empty();
}
