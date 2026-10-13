import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/voice/voice_repository.dart';

void main() {
  test('fetches a LiveKit token for the channel', () async {
    final source = _FakeVoiceDataSource()
      ..functionResult = {'url': 'wss://lk.test', 'token': 'jwt'};
    final repository = SupabaseVoiceRepository(source);

    final details = await repository.fetchConnectionDetails('channel-1');

    expect(details.url, 'wss://lk.test');
    expect(details.token, 'jwt');
    expect(source.functionCalls, [
      [
        'livekit-token',
        {'channel_id': 'channel-1'},
      ],
    ]);
  });

  test('503 voice_not_configured means voice is not set up', () async {
    final source = _FakeVoiceDataSource()
      ..functionError = const FunctionException(
        status: 503,
        details: {'error': 'voice_not_configured'},
      );

    await expectLater(
      SupabaseVoiceRepository(source).fetchConnectionDetails('channel-1'),
      throwsA(isA<VoiceNotConfiguredException>()),
    );
  });

  test('403 means no access; other failures pass through', () async {
    final source = _FakeVoiceDataSource()
      ..functionError = const FunctionException(
        status: 403,
        details: {'error': 'forbidden'},
      );
    final repository = SupabaseVoiceRepository(source);
    await expectLater(
      repository.fetchConnectionDetails('channel-1'),
      throwsA(isA<VoiceAccessDeniedException>()),
    );

    source.functionError = const FunctionException(
      status: 503,
      details: {'error': 'something_else'},
    );
    await expectLater(
      repository.fetchConnectionDetails('channel-1'),
      throwsA(isA<FunctionException>()),
    );

    source
      ..functionError = null
      ..functionResult = {'url': 'wss://lk.test'};
    await expectLater(
      repository.fetchConnectionDetails('channel-1'),
      throwsA(isA<StateError>()),
    );
  });

  test('voice state RPCs send the right parameters', () async {
    final source = _FakeVoiceDataSource()
      ..rpcResults['update_voice_state'] = true;
    final repository = SupabaseVoiceRepository(source);

    await repository.joinVoiceState('channel-1');
    final alive = await repository.updateVoiceState(
      selfMute: true,
      selfDeaf: false,
      video: true,
      screen: false,
    );
    await repository.leaveVoiceState();

    expect(alive, isTrue);
    expect(source.rpcCalls, [
      [
        'join_voice_state',
        {'target_channel_id': 'channel-1'},
      ],
      [
        'update_voice_state',
        {
          'target_self_mute': true,
          'target_self_deaf': false,
          'target_video': true,
          'target_screen': false,
        },
      ],
      ['leave_voice_state', <String, dynamic>{}],
    ]);

    source.rpcResults['update_voice_state'] = false;
    expect(
      await repository.updateVoiceState(
        selfMute: false,
        selfDeaf: false,
        video: false,
        screen: false,
      ),
      isFalse,
    );
  });

  test('joining without connect_voice is access denied', () async {
    final source = _FakeVoiceDataSource()
      ..rpcErrors['join_voice_state'] = const PostgrestException(
        message: 'You cannot connect to this voice channel',
        code: '42501',
      );

    await expectLater(
      SupabaseVoiceRepository(source).joinVoiceState('channel-1'),
      throwsA(isA<VoiceAccessDeniedException>()),
    );
  });

  test('lists voice members with names, nicknames and flags', () async {
    final source = _FakeVoiceDataSource()
      ..rpcResults['list_voice_states'] = [
        {
          'channel_id': 'channel-1',
          'circle_id': 'circle-1',
          'user_id': 'user-2',
          'joined_at': '2026-10-14T09:00:00Z',
          'last_seen_at': '2026-10-14T09:00:20Z',
          'self_mute': true,
          'self_deaf': false,
          'video': true,
          'screen': false,
          'profile': {
            'id': 'user-2',
            'username': 'bart',
            'display_name': 'Bart',
            'avatar_url': null,
          },
          'nickname': 'Bart the Bold',
          'role_color': 0x3366FF,
        },
      ];

    final states = await SupabaseVoiceRepository(
      source,
    ).listVoiceStates('circle-1');

    expect(source.rpcCalls.single, [
      'list_voice_states',
      {'target_circle_id': 'circle-1'},
    ]);
    final state = states.single;
    expect(state.channelId, 'channel-1');
    expect(state.userId, 'user-2');
    expect(state.name, 'Bart the Bold');
    expect(state.roleColor, 0x3366FF);
    expect(state.selfMute, isTrue);
    expect(state.video, isTrue);
    expect(state.joinedAt, DateTime.utc(2026, 10, 14, 9));
  });

  test('bare heartbeats do not count as changes', () {
    final before = {
      'channel_id': 'c',
      'user_id': 'u',
      'self_mute': false,
      'last_seen_at': '2026-10-14T09:00:00Z',
    };
    expect(
      isVoiceHeartbeatOnly(
        eventType: PostgresChangeEvent.update,
        oldRecord: before,
        newRecord: {...before, 'last_seen_at': '2026-10-14T09:00:20Z'},
      ),
      isTrue,
    );
    expect(
      isVoiceHeartbeatOnly(
        eventType: PostgresChangeEvent.update,
        oldRecord: before,
        newRecord: {...before, 'self_mute': true},
      ),
      isFalse,
    );
    expect(
      isVoiceHeartbeatOnly(
        eventType: PostgresChangeEvent.insert,
        oldRecord: const {},
        newRecord: before,
      ),
      isFalse,
    );
    expect(
      isVoiceHeartbeatOnly(
        eventType: PostgresChangeEvent.delete,
        oldRecord: before,
        newRecord: const {},
      ),
      isFalse,
    );
  });
}

class _FakeVoiceDataSource implements VoiceDataSource {
  /// [name, params] per call.
  final rpcCalls = <List<Object>>[];
  final rpcResults = <String, Object?>{};
  final rpcErrors = <String, Object>{};
  final functionCalls = <List<Object>>[];
  Object? functionResult;
  Object? functionError;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add([functionName, params]);
    if (rpcErrors[functionName] case final error?) {
      throw error;
    }
    return rpcResults[functionName];
  }

  @override
  Future<Object?> invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    functionCalls.add([functionName, body]);
    if (functionError case final error?) {
      throw error;
    }
    return functionResult;
  }

  @override
  Stream<void> voiceStateChanges(String circleId) {
    return const Stream<void>.empty();
  }
}
