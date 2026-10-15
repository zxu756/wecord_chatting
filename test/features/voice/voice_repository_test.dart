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

  test('a full channel refuses the token and the join', () async {
    final source = _FakeVoiceDataSource()
      ..functionError = const FunctionException(
        status: 409,
        details: {'error': 'channel_full'},
      )
      ..rpcErrors['join_voice_state'] = const PostgrestException(
        message: 'This voice channel is full',
        code: '53300',
      );
    final repository = SupabaseVoiceRepository(source);
    await expectLater(
      repository.fetchConnectionDetails('channel-1'),
      throwsA(isA<VoiceChannelFullException>()),
    );
    await expectLater(
      repository.joinVoiceState('channel-1'),
      throwsA(isA<VoiceChannelFullException>()),
    );
  });

  test('the token says whether the server muted us', () async {
    final source = _FakeVoiceDataSource()
      ..functionResult = {
        'url': 'wss://lk.test',
        'token': 'jwt',
        'server_mute': true,
      };
    final details = await SupabaseVoiceRepository(
      source,
    ).fetchConnectionDetails('channel-1');
    expect(details.serverMute, isTrue);
    expect(details.serverDeaf, isFalse);
  });

  test('moderation RPCs send the right parameters', () async {
    final source = _FakeVoiceDataSource()
      ..rpcResults['disconnect_voice_member'] = 'channel-1'
      ..rpcResults['move_voice_member'] = 'channel-1'
      ..rpcResults['list_voice_channel_user_limits'] = {'channel-2': 5}
      ..rpcResults['get_own_voice_state'] = {
        'state': {
          'channel_id': 'channel-2',
          'circle_id': 'circle-1',
          'conversation_id': 'conv-2',
          'channel_name': 'Stage',
          'server_mute': true,
          'server_deaf': false,
        },
        'disconnected': false,
      };
    final repository = SupabaseVoiceRepository(source);

    await repository.setServerMute(
      circleId: 'circle-1',
      userId: 'user-2',
      muted: true,
    );
    await repository.setServerDeaf(
      circleId: 'circle-1',
      userId: 'user-2',
      deafened: false,
    );
    expect(
      await repository.disconnectMember(circleId: 'circle-1', userId: 'user-2'),
      'channel-1',
    );
    expect(
      await repository.moveMember(
        circleId: 'circle-1',
        userId: 'user-2',
        channelId: 'channel-2',
      ),
      'channel-1',
    );
    await repository.setUserLimit(channelId: 'channel-2', limit: 5);
    expect(await repository.listUserLimits('circle-1'), {'channel-2': 5});
    final own = await repository.fetchOwnVoiceState();
    expect(own.channelId, 'channel-2');
    expect(own.conversationId, 'conv-2');
    expect(own.serverMute, isTrue);
    await repository.enforceVoiceState(
      channelId: 'channel-1',
      userId: 'user-2',
    );

    expect(source.rpcCalls.take(5), [
      [
        'set_voice_server_mute',
        {
          'target_circle_id': 'circle-1',
          'target_user_id': 'user-2',
          'muted': true,
        },
      ],
      [
        'set_voice_server_deaf',
        {
          'target_circle_id': 'circle-1',
          'target_user_id': 'user-2',
          'deafened': false,
        },
      ],
      [
        'disconnect_voice_member',
        {'target_circle_id': 'circle-1', 'target_user_id': 'user-2'},
      ],
      [
        'move_voice_member',
        {
          'target_circle_id': 'circle-1',
          'target_user_id': 'user-2',
          'target_channel_id': 'channel-2',
        },
      ],
      [
        'set_voice_channel_user_limit',
        {'target_channel_id': 'channel-2', 'user_limit': 5},
      ],
    ]);
    expect(source.functionCalls.single, [
      'livekit-token',
      {
        'enforce': {'channel_id': 'channel-1', 'user_id': 'user-2'},
      },
    ]);
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

  group('direct calls', () {
    test('starting a call returns its id; 42501 means no access', () async {
      final source = _FakeVoiceDataSource()
        ..rpcResults['start_direct_call'] = 'call-1';
      final repository = SupabaseVoiceRepository(source);

      expect(await repository.startDirectCall('dm-1'), 'call-1');
      expect(source.rpcCalls.single, [
        'start_direct_call',
        {'target_conversation_id': 'dm-1'},
      ]);

      source.rpcErrors['start_direct_call'] = const PostgrestException(
        message: 'You cannot call in this conversation',
        code: '42501',
      );
      await expectLater(
        repository.startDirectCall('dm-1'),
        throwsA(isA<VoiceAccessDeniedException>()),
      );
    });

    test('call tokens ask for the call, not a channel', () async {
      final source = _FakeVoiceDataSource()
        ..functionResult = {'url': 'wss://lk.test', 'token': 'jwt'};
      final repository = SupabaseVoiceRepository(source);

      final details = await repository.fetchCallConnectionDetails('call-1');

      expect(details.token, 'jwt');
      expect(source.functionCalls.single, [
        'livekit-token',
        {'call_id': 'call-1'},
      ]);
    });

    test('heartbeats, rejoins, leaves and declines call their RPCs', () async {
      final source = _FakeVoiceDataSource()
        ..rpcResults['update_direct_call_state'] = true
        ..rpcResults['join_direct_call'] = false;
      final repository = SupabaseVoiceRepository(source);

      expect(
        await repository.updateDirectCallState(
          callId: 'call-1',
          selfMute: true,
          selfDeaf: false,
          video: true,
          screen: false,
        ),
        isTrue,
      );
      expect(await repository.joinDirectCall('call-1'), isFalse);
      await repository.leaveDirectCall('call-1');
      await repository.declineDirectCall('call-2');

      expect(
        [for (final call in source.rpcCalls) call.first],
        [
          'update_direct_call_state',
          'join_direct_call',
          'leave_direct_call',
          'decline_direct_call',
        ],
      );
      expect(source.rpcCalls.first.last, {
        'target_call_id': 'call-1',
        'target_self_mute': true,
        'target_self_deaf': false,
        'target_video': true,
        'target_screen': false,
      });
      expect(source.rpcCalls.last.last, {'target_call_id': 'call-2'});
    });

    test('active calls parse with their participants', () async {
      final source = _FakeVoiceDataSource()
        ..rpcResults['list_active_direct_calls'] = [
          {
            'call_id': 'call-1',
            'conversation_id': 'dm-1',
            'started_by': 'user-2',
            'created_at': '2026-10-14T09:00:00Z',
            'ringing': true,
            'participants': [
              {
                'user_id': 'user-2',
                'username': 'bob',
                'display_name': 'Bob',
                'avatar_url': null,
                'self_mute': true,
                'video': true,
              },
            ],
          },
        ];

      final calls = await SupabaseVoiceRepository(
        source,
      ).listActiveDirectCalls();

      final call = calls.single;
      expect(call.callId, 'call-1');
      expect(call.conversationId, 'dm-1');
      expect(call.ringing, isTrue);
      expect(call.caller!.name, 'Bob');
      expect(call.participants.single.selfMute, isTrue);
      expect(call.participants.single.video, isTrue);
      expect(call.createdAt, DateTime.utc(2026, 10, 14, 9));
    });
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

  @override
  Stream<void> ownVoiceStateChanges() => const Stream<void>.empty();

  @override
  Stream<void> directCallChanges() => const Stream<void>.empty();
}
