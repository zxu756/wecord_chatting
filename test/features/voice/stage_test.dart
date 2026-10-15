import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/stage_repository.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/voice.dart';

import 'voice_fakes.dart';

/// Stage channels: the audience listens, speakers talk, moderators run it.
void main() {
  group('stage session', () {
    late FakeVoiceRepository repository;
    late FakeVoiceCallConnector connector;
    late VoiceSessionController controller;

    setUp(() {
      repository = FakeVoiceRepository()..tokenStage = true;
      connector = FakeVoiceCallConnector();
      controller = VoiceSessionController(
        repository: repository,
        connector: connector,
      );
    });

    Future<void> joinStage() {
      return controller.join(
        circleId: 'circle-1',
        channelId: 'ch-town',
        conversationId: 'conv-town',
        channelName: 'Town hall',
      );
    }

    testWidgets('the audience joins with the microphone closed', (
      tester,
    ) async {
      await joinStage();

      final session = controller.state!;
      expect(session.stage, isTrue);
      expect(session.stageSpeaker, isFalse);
      expect(session.stageListener, isTrue);
      expect(session.microphoneWanted, isFalse);
      expect(connector.last.microphone, isFalse);
      // Not shown as muted by choice: they just can't speak.
      expect(session.selfMute, isFalse);

      // Unmuting does nothing for a listener.
      await controller.toggleMute();
      expect(connector.last.microphone, isFalse);
      await controller.leave();
    });

    testWidgets('becoming a speaker starts muted; going back closes the mic', (
      tester,
    ) async {
      await joinStage();

      repository.ownState = const OwnVoiceState(
        channelId: 'ch-town',
        circleId: 'circle-1',
        stage: true,
        stageInvited: true,
      );
      repository.emitChange();
      await tester.pump();
      expect(controller.state!.stageInvited, isTrue);
      expect(repository.enforced, isEmpty);

      repository.ownState = const OwnVoiceState(
        channelId: 'ch-town',
        circleId: 'circle-1',
        stage: true,
        stageSpeaker: true,
      );
      await controller.syncOwnState();
      var session = controller.state!;
      expect(session.stageSpeaker, isTrue);
      expect(session.stageInvited, isFalse);
      expect(session.selfMute, isTrue);
      expect(connector.last.microphone, isFalse);
      // Asks the voice server to let them publish.
      expect(repository.enforced, ['ch-town:user-1']);

      await controller.toggleMute();
      expect(connector.last.microphone, isTrue);
      await controller.toggleCamera();
      expect(connector.last.camera, isTrue);

      repository.ownState = const OwnVoiceState(
        channelId: 'ch-town',
        circleId: 'circle-1',
        stage: true,
      );
      await controller.syncOwnState();
      session = controller.state!;
      expect(session.stageListener, isTrue);
      expect(session.video, isFalse);
      expect(connector.last.microphone, isFalse);
      expect(connector.last.camera, isFalse);
      expect(repository.enforced, ['ch-town:user-1', 'ch-town:user-1']);
      await controller.leave();
    });

    testWidgets('a speaker reconnecting keeps the microphone', (tester) async {
      repository.tokenStageSpeaker = true;
      await joinStage();

      expect(controller.state!.stageSpeaker, isTrue);
      expect(connector.last.microphone, isTrue);
      await controller.leave();
    });
  });

  group('stage repository', () {
    test('lists live stages and maps refusals', () async {
      final source = _FakeStageDataSource()
        ..results['list_stage_instances'] = {
          'ch-town': {
            'channel_id': 'ch-town',
            'circle_id': 'circle-1',
            'topic': 'Weekly talk',
            'started_by': 'user-1',
            'started_at': '2026-10-16T09:00:00Z',
          },
        }
        ..results['end_stage'] = ['user-2', 'user-3']
        ..results['invite_stage_speaker'] = true;
      final repository = SupabaseStageRepository(source);

      final stages = await repository.listStages('circle-1');
      expect(stages.keys, ['ch-town']);
      expect(stages['ch-town']!.topic, 'Weekly talk');
      expect(stages['ch-town']!.startedAt, DateTime.utc(2026, 10, 16, 9));

      await repository.startStage(channelId: 'ch-town', topic: '  Hi  ');
      expect(source.calls.last, [
        'start_stage',
        {'target_channel_id': 'ch-town', 'stage_topic': 'Hi'},
      ]);
      expect(await repository.endStage('ch-town'), ['user-2', 'user-3']);
      expect(
        await repository.inviteToSpeak(channelId: 'ch-town', userId: 'user-2'),
        isTrue,
      );
      await repository.moveToAudience(channelId: 'ch-town', userId: 'user-2');
      expect(source.calls.last, [
        'set_stage_audience',
        {'target_channel_id': 'ch-town', 'target_user_id': 'user-2'},
      ]);

      source.errors['set_stage_hand_raised'] = const PostgrestException(
        message: 'No stage is live here',
        code: '55000',
      );
      await expectLater(
        repository.setHandRaised(channelId: 'ch-town', raised: true),
        throwsA(isA<StageNotLiveException>()),
      );
    });

    test('voice states and tokens carry the stage role', () async {
      final member = VoiceMemberState.fromJson({
        'channel_id': 'ch-town',
        'circle_id': 'circle-1',
        'user_id': 'user-2',
        'joined_at': '2026-10-16T09:00:00Z',
        'stage_speaker': false,
        'stage_invited': true,
        'hand_raised_at': '2026-10-16T09:05:00Z',
        'profile': {'username': 'bart', 'display_name': 'Bart'},
      });
      expect(member.stageInvited, isTrue);
      expect(member.handRaised, isTrue);
      expect(member.handRaisedAt, DateTime.utc(2026, 10, 16, 9, 5));

      final own = OwnVoiceState.fromJson({
        'state': {
          'channel_id': 'ch-town',
          'channel_kind': 'stage',
          'stage_speaker': true,
          'hand_raised_at': null,
        },
      });
      expect(own.stage, isTrue);
      expect(own.stageSpeaker, isTrue);
      expect(own.handRaised, isFalse);

      final source = _FakeVoiceDataSource()
        ..functionResult = {
          'url': 'wss://lk.test',
          'token': 'jwt',
          'stage': true,
          'stage_speaker': false,
        };
      final details = await SupabaseVoiceRepository(
        source,
      ).fetchConnectionDetails('ch-town');
      expect(details.stage, isTrue);
      expect(details.stageSpeaker, isFalse);
    });

    test('stage channels read their kind; moderators need both rights', () {
      final channel = CircleChannel.fromJson({
        'id': 'ch-town',
        'circle_id': 'circle-1',
        'conversation_id': 'conv-town',
        'name': 'Town hall',
        'kind': 'stage',
      });
      expect(channel.kind, CircleChannelKind.stage);
      expect(channel.isStage, isTrue);
      expect(channel.isVoice, isTrue);
    });
  });

  group('stage view', () {
    late FakeVoiceRepository voice;
    late _FakeStageRepository stages;
    late ProviderContainer container;

    setUp(() {
      voice = FakeVoiceRepository()..tokenStage = true;
      stages = _FakeStageRepository();
    });

    final me = voiceMember(userId: 'user-1', name: 'Ada', channelId: 'ch-town');

    Future<void> pumpStage(
      WidgetTester tester, {
      required bool moderator,
      required List<VoiceMemberState> members,
      bool speaker = false,
    }) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      voice
        ..tokenStageSpeaker = speaker
        ..states['circle-1'] = members;
      container = ProviderContainer(
        overrides: [
          voiceRepositoryProvider.overrideWithValue(voice),
          voiceCallConnectorProvider.overrideWithValue(
            FakeVoiceCallConnector(),
          ),
          stageRepositoryProvider.overrideWithValue(stages),
          voiceSettingsStoreProvider.overrideWithValue(
            InMemoryVoiceSettingsStore(),
          ),
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthUser(id: 'user-1', email: 'ada@example.com'),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: VoiceChannelView(
              circleId: 'circle-1',
              channelId: 'ch-town',
              conversationId: 'conv-town',
              channelName: 'Town hall',
              isStage: true,
              stageModerator: moderator,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> join(WidgetTester tester) async {
      await container
          .read(voiceSessionProvider.notifier)
          .join(
            circleId: 'circle-1',
            channelId: 'ch-town',
            conversationId: 'conv-town',
            channelName: 'Town hall',
          );
      await tester.pumpAndSettle();
    }

    Future<void> leave(WidgetTester tester) async {
      await container.read(voiceSessionProvider.notifier).leave();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('before joining: the topic, speakers and a Join button', (
      tester,
    ) async {
      stages.live['ch-town'] = _stage('Weekly talk');
      await pumpStage(
        tester,
        moderator: false,
        members: [
          voiceMember(
            userId: 'user-2',
            name: 'Bart',
            channelId: 'ch-town',
            stageSpeaker: true,
          ),
          voiceMember(userId: 'user-3', name: 'Grace', channelId: 'ch-town'),
        ],
      );

      expect(find.byKey(const ValueKey('stage-lobby')), findsOneWidget);
      expect(find.text('Weekly talk'), findsOneWidget);
      expect(find.text('Bart'), findsOneWidget);
      expect(find.text('1 listening'), findsOneWidget);
      expect(find.byIcon(Icons.podcasts), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('stage-join-button')));
      await tester.pumpAndSettle();
      expect(voice.joined, ['ch-town']);
      expect(find.byKey(const ValueKey('stage-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-controls')), findsOneWidget);
      await leave(tester);
    });

    testWidgets('the audience raises a hand and answers an invitation', (
      tester,
    ) async {
      stages.live['ch-town'] = _stage('Weekly talk');
      await pumpStage(
        tester,
        moderator: false,
        members: [
          me,
          voiceMember(
            userId: 'user-2',
            name: 'Bart',
            channelId: 'ch-town',
            stageSpeaker: true,
          ),
        ],
      );
      await join(tester);

      expect(
        find.byKey(const ValueKey('stage-speaker-user-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('stage-listener-user-1')),
        findsOneWidget,
      );
      // Listeners have no microphone button, and can't start a stage.
      expect(find.byKey(const ValueKey('voice-control-mic')), findsNothing);
      expect(find.byKey(const ValueKey('stage-start-button')), findsNothing);
      expect(find.byKey(const ValueKey('stage-end-button')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('stage-control-hand')));
      await tester.pumpAndSettle();
      expect(stages.calls, ['hand:ch-town:true']);

      voice.ownState = const OwnVoiceState(
        channelId: 'ch-town',
        circleId: 'circle-1',
        stage: true,
        stageInvited: true,
      );
      voice.emitChange();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage-invite-banner')), findsOneWidget);

      voice.ownState = const OwnVoiceState(
        channelId: 'ch-town',
        circleId: 'circle-1',
        stage: true,
        stageSpeaker: true,
      );
      await tester.tap(find.byKey(const ValueKey('stage-invite-accept')));
      await tester.pumpAndSettle();
      expect(stages.calls.last, 'respond:ch-town:true');
      expect(find.byKey(const ValueKey('stage-invite-banner')), findsNothing);
      expect(
        find.byKey(const ValueKey('stage-speaker-user-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('voice-control-mic')), findsOneWidget);
      expect(voice.enforced, contains('ch-town:user-1'));
      await leave(tester);
    });

    testWidgets('moderators start, invite raised hands, move down and end', (
      tester,
    ) async {
      await pumpStage(
        tester,
        moderator: true,
        members: [
          me,
          voiceMember(
            userId: 'user-2',
            name: 'Bart',
            channelId: 'ch-town',
            stageSpeaker: true,
          ),
          voiceMember(
            userId: 'user-3',
            name: 'Grace',
            channelId: 'ch-town',
            handRaisedAt: DateTime.utc(2026, 10, 16, 9),
          ),
        ],
      );
      await join(tester);

      expect(find.text('No stage is live right now.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stage-start-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage-topic-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('stage-topic-field')),
        'Launch day',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stage-topic-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stage-topic-dialog')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(stages.calls, ['start:ch-town:Launch day']);
      expect(find.text('Launch day'), findsOneWidget);

      // Grace raised her hand.
      expect(find.byKey(const ValueKey('stage-hands-heading')), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-hand-badge-user-3')), findsOne);
      await tester.tap(find.byKey(const ValueKey('stage-accept-hand-user-3')));
      await tester.pumpAndSettle();
      expect(stages.calls.last, 'invite:ch-town:user-3');
      expect(voice.enforced, ['ch-town:user-3']);

      // Bart goes back to the audience.
      await tester.tap(find.byKey(const ValueKey('stage-speaker-user-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stage-menu-audience')));
      await tester.pumpAndSettle();
      expect(stages.calls.last, 'audience:ch-town:user-2');
      expect(voice.enforced.last, 'ch-town:user-2');

      // The moderator steps up themselves.
      await tester.tap(find.byKey(const ValueKey('stage-control-speak')));
      await tester.pumpAndSettle();
      expect(stages.calls.last, 'invite:ch-town:user-1');

      stages.endedSpeakers = ['user-2', 'user-3'];
      await tester.tap(find.byKey(const ValueKey('stage-end-button')));
      await tester.pumpAndSettle();
      expect(stages.calls.last, 'end:ch-town');
      expect(voice.enforced, containsAll(['ch-town:user-3', 'ch-town:user-2']));
      expect(find.text('No stage is live right now.'), findsOneWidget);
      await leave(tester);
    });
  });
}

StageInstance _stage(String topic) {
  return StageInstance(
    channelId: 'ch-town',
    circleId: 'circle-1',
    topic: topic,
    startedAt: DateTime.utc(2026, 10, 16, 9),
  );
}

class _FakeStageRepository implements StageRepository {
  final live = <String, StageInstance>{};
  final calls = <String>[];
  List<String> endedSpeakers = const [];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<Map<String, StageInstance>> listStages(String circleId) async {
    return Map.of(live);
  }

  @override
  Stream<void> stageChanges(String circleId) => _changes.stream;

  @override
  Future<void> startStage({
    required String channelId,
    required String topic,
  }) async {
    calls.add('start:$channelId:$topic');
    live[channelId] = _stage(topic);
  }

  @override
  Future<List<String>> endStage(String channelId) async {
    calls.add('end:$channelId');
    live.remove(channelId);
    return endedSpeakers;
  }

  @override
  Future<void> setHandRaised({
    required String channelId,
    required bool raised,
  }) async {
    calls.add('hand:$channelId:$raised');
  }

  @override
  Future<bool> inviteToSpeak({
    required String channelId,
    required String userId,
  }) async {
    calls.add('invite:$channelId:$userId');
    return true;
  }

  @override
  Future<bool> respondToInvite({
    required String channelId,
    required bool accept,
  }) async {
    calls.add('respond:$channelId:$accept');
    return accept;
  }

  @override
  Future<void> moveToAudience({
    required String channelId,
    required String userId,
  }) async {
    calls.add('audience:$channelId:$userId');
  }
}

class _FakeStageDataSource implements StageDataSource {
  final results = <String, Object?>{};
  final errors = <String, Object>{};
  final calls = <List<Object?>>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add([functionName, params]);
    final error = errors[functionName];
    if (error != null) {
      throw error;
    }
    return results[functionName];
  }

  @override
  Stream<void> stageChanges(String circleId) => const Stream.empty();
}

class _FakeVoiceDataSource implements VoiceDataSource {
  Object? functionResult;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    return null;
  }

  @override
  Future<Object?> invokeFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async => functionResult;

  @override
  Stream<void> voiceStateChanges(String circleId) => const Stream.empty();

  @override
  Stream<void> ownVoiceStateChanges() => const Stream.empty();

  @override
  Stream<void> directCallChanges() => const Stream.empty();
}
