import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/voice/soundboard_player.dart';
import 'package:wecord/features/voice/soundboard_repository.dart';
import 'package:wecord/features/voice/soundboard_sheet.dart';
import 'package:wecord/features/voice/voice_channel_view.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_settings.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';
import 'package:wecord/shared/models/circle_sound.dart';
import 'package:wecord/shared/models/voice.dart';

import 'audio_fixtures.dart';
import 'voice_fakes.dart';

/// The soundboard: uploads, plays, playback for everyone and its volume.
void main() {
  group('soundboard repository', () {
    test('checks, uploads and registers a clip', () async {
      final source = _FakeSoundboardDataSource()
        ..results['create_circle_sound'] = _soundJson('sound-1', 'Airhorn');
      final repository = SupabaseSoundboardRepository(
        source,
        newId: () => '11111111-2222-4333-8444-555555555555',
      );

      final sound = await repository.addSound(
        circleId: 'circle-1',
        name: ' Airhorn ',
        emoji: '📯',
        bytes: mp3Bytes(frames: 60),
      );

      expect(sound.name, 'Airhorn');
      expect(source.uploads, [
        'circle-1/11111111-2222-4333-8444-555555555555.mp3 audio/mpeg',
      ]);
      final create = source.calls.single;
      expect(create[0], 'create_circle_sound');
      final params = create[1] as Map<String, dynamic>;
      expect(params['sound_name'], 'Airhorn');
      expect(params['sound_emoji'], '📯');
      expect(params['mime_type'], 'audio/mpeg');
      expect(params['duration_ms'], 1567);
    });

    test('refuses other files, long clips and bad names', () async {
      final source = _FakeSoundboardDataSource();
      final repository = SupabaseSoundboardRepository(source);
      Future<void> add(String name, Uint8List bytes) {
        return repository.addSound(
          circleId: 'circle-1',
          name: name,
          bytes: bytes,
        );
      }

      await expectLater(
        add('Ding', Uint8List.fromList('not audio'.codeUnits)),
        throwsA(isA<SoundboardException>()),
      );
      await expectLater(
        add('Ding', wavBytes(seconds: 5.5)),
        throwsA(
          isA<SoundboardException>().having(
            (error) => error.message,
            'message',
            'Sounds can be at most 5 seconds long.',
          ),
        ),
      );
      await expectLater(
        add('   ', wavBytes()),
        throwsA(isA<SoundboardException>()),
      );
      await expectLater(
        add('Ding', Uint8List(maxCircleSoundBytes + 1)),
        throwsA(isA<SoundboardException>()),
      );
      expect(source.uploads, isEmpty);
    });

    test('a refused registration removes the upload and says why', () async {
      final source = _FakeSoundboardDataSource()
        ..errors['create_circle_sound'] = const PostgrestException(
          message: 'That name is already taken',
          code: '23505',
        );
      final repository = SupabaseSoundboardRepository(
        source,
        newId: () => 'id-1',
      );
      await expectLater(
        repository.addSound(
          circleId: 'circle-1',
          name: 'Ding',
          bytes: wavBytes(),
        ),
        throwsA(
          isA<SoundboardException>().having(
            (error) => error.message,
            'message',
            'That name is already taken.',
          ),
        ),
      );
      await pumpEventQueue();
      expect(source.removed, ['circle-1/id-1.wav']);

      source.errors['create_circle_sound'] = const PostgrestException(
        message: 'This circle has no room for more sounds',
        code: '54000',
      );
      await expectLater(
        repository.addSound(
          circleId: 'circle-1',
          name: 'Ding',
          bytes: wavBytes(),
        ),
        throwsA(
          isA<SoundboardException>().having(
            (error) => error.message,
            'message',
            'This circle already has 24 sounds.',
          ),
        ),
      );
    });

    test('plays, deletes and reports the cooldown', () async {
      final source = _FakeSoundboardDataSource()
        ..results['delete_circle_sound'] = 'circle-1/a.mp3';
      final repository = SupabaseSoundboardRepository(source);

      await repository.play(channelId: 'ch-lounge', soundId: 'sound-1');
      expect(source.calls.last, [
        'play_soundboard_sound',
        {'target_channel_id': 'ch-lounge', 'target_sound_id': 'sound-1'},
      ]);

      source.errors['play_soundboard_sound'] = const PostgrestException(
        message: 'Wait a moment before playing another sound',
        code: 'P0001',
        details: 'soundboard_cooldown_ms=1200',
      );
      await expectLater(
        repository.play(channelId: 'ch-lounge', soundId: 'sound-1'),
        throwsA(isA<SoundboardCooldownException>()),
      );

      await repository.deleteSound('sound-1');
      expect(source.removed, ['circle-1/a.mp3']);
    });

    test('plays arrive for their channel only', () async {
      final source = _FakeSoundboardDataSource();
      final repository = SupabaseSoundboardRepository(source);
      final plays = <String>[];
      final subscription = repository
          .plays('ch-lounge')
          .listen((play) => plays.add('${play.userId}:${play.soundId}'));
      source.inserts.add({
        'channel_id': 'ch-lounge',
        'sound_id': 'sound-1',
        'user_id': 'user-2',
      });
      source.inserts.add({
        'channel_id': 'ch-other',
        'sound_id': 'sound-1',
        'user_id': 'user-2',
      });
      source.inserts.add({'channel_id': 'ch-lounge'});
      await pumpEventQueue();
      expect(plays, ['user-2:sound-1']);
      await subscription.cancel();
    });
  });

  group('playback', () {
    late _FakeSoundboardRepository repository;
    late _FakeSoundboardPlayer player;
    late SoundboardPlayback playback;
    var volume = 0.5;

    setUp(() {
      repository = _FakeSoundboardRepository();
      player = _FakeSoundboardPlayer();
      volume = 0.5;
      playback = SoundboardPlayback(
        repository: repository,
        player: player,
        volume: () => volume,
      );
    });

    tearDown(() => playback.dispose());

    VoiceSession lounge({bool deafened = false}) => VoiceSession(
      circleId: 'circle-1',
      channelId: 'ch-lounge',
      conversationId: 'conv-lounge',
      channelName: 'Lounge',
      status: VoiceSessionStatus.connected,
      selfDeaf: deafened,
    );

    test('plays sounds in the channel at the chosen volume', () async {
      playback.follow(lounge());
      repository.emitPlay('ch-lounge', 'sound-1');
      await pumpEventQueue();
      expect(player.played, ['url:circle-1/sound-1.mp3@0.5']);

      // Deafened members don't hear them; 0% turns them off.
      playback.follow(lounge(deafened: true));
      repository.emitPlay('ch-lounge', 'sound-1');
      await pumpEventQueue();
      playback.follow(lounge());
      volume = 0;
      repository.emitPlay('ch-lounge', 'sound-1');
      await pumpEventQueue();
      expect(player.played, hasLength(1));

      // Unknown sounds are skipped; the URL is signed once.
      volume = 1;
      repository.emitPlay('ch-lounge', 'missing');
      repository.emitPlay('ch-lounge', 'sound-1');
      await pumpEventQueue();
      expect(player.played, [
        'url:circle-1/sound-1.mp3@0.5',
        'url:circle-1/sound-1.mp3@1.0',
      ]);
      expect(repository.signed, 1);
    });

    test('stops listening when the session ends', () async {
      playback.follow(lounge());
      expect(repository.listening, ['ch-lounge']);
      playback.follow(null);
      repository.emitPlay('ch-lounge', 'sound-1');
      await pumpEventQueue();
      expect(player.played, isEmpty);
      expect(repository.cancelled, 1);
    });
  });

  group('soundboard panel', () {
    late FakeVoiceRepository voice;
    late _FakeSoundboardRepository sounds;
    late ProviderContainer container;
    PickedSoundFile? picked;

    Future<void> pumpView(
      WidgetTester tester, {
      required bool canManage,
    }) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      voice = FakeVoiceRepository();
      sounds = _FakeSoundboardRepository();
      container = ProviderContainer(
        overrides: [
          voiceRepositoryProvider.overrideWithValue(voice),
          voiceCallConnectorProvider.overrideWithValue(
            FakeVoiceCallConnector(),
          ),
          soundboardRepositoryProvider.overrideWithValue(sounds),
          soundboardPlayerProvider.overrideWithValue(_FakeSoundboardPlayer()),
          soundFilePickerProvider.overrideWithValue(() async => picked),
          voiceSettingsStoreProvider.overrideWithValue(
            InMemoryVoiceSettingsStore(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: VoiceChannelView(
              circleId: 'circle-1',
              channelId: 'ch-lounge',
              conversationId: 'conv-lounge',
              channelName: 'Lounge',
              canManageSounds: canManage,
            ),
          ),
        ),
      );
      await container
          .read(voiceSessionProvider.notifier)
          .join(
            circleId: 'circle-1',
            channelId: 'ch-lounge',
            conversationId: 'conv-lounge',
            channelName: 'Lounge',
          );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await container.read(voiceSessionProvider.notifier).leave();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('members play sounds for everyone, then wait a moment', (
      tester,
    ) async {
      await pumpView(tester, canManage: false);

      await tester.tap(find.byKey(const ValueKey('voice-control-soundboard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('soundboard-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('soundboard-add')), findsNothing);
      expect(find.text('Airhorn'), findsOneWidget);

      final chip = find.byKey(const ValueKey('soundboard-sound-sound-1'));
      await tester.tap(chip);
      await tester.pump();
      expect(sounds.played, ['ch-lounge:sound-1']);
      // Cooling down.
      expect(tester.widget<ActionChip>(chip).onPressed, isNull);
      await tester.pump(soundboardCooldown);
      expect(tester.widget<ActionChip>(chip).onPressed, isNotNull);

      sounds.playError = SoundboardCooldownException();
      await tester.tap(chip);
      await tester.pump();
      expect(
        find.text('Wait a moment before playing another sound.'),
        findsOneWidget,
      );
      await tester.pump(soundboardCooldown);
      await close(tester);
    });

    testWidgets('server-muted members cannot play', (tester) async {
      await pumpView(tester, canManage: false);
      voice.ownState = const OwnVoiceState(
        channelId: 'ch-lounge',
        circleId: 'circle-1',
        serverMute: true,
      );
      await container.read(voiceSessionProvider.notifier).syncOwnState();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('voice-control-soundboard')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('soundboard-cannot-play')),
        findsOneWidget,
      );
      final chip = find.byKey(const ValueKey('soundboard-sound-sound-1'));
      expect(tester.widget<ActionChip>(chip).onPressed, isNull);
      await close(tester);
    });

    testWidgets('managers add and delete sounds', (tester) async {
      await pumpView(tester, canManage: true);
      picked = PickedSoundFile(name: 'big_bell.wav', bytes: wavBytes());

      await tester.tap(find.byKey(const ValueKey('voice-control-soundboard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('soundboard-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('soundboard-add-dialog')), findsOne);
      final name = tester.widget<TextField>(
        find.byKey(const ValueKey('soundboard-name-field')),
      );
      expect(name.controller!.text, 'big bell');
      await tester.enterText(
        find.byKey(const ValueKey('soundboard-emoji-field')),
        '🔔',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('soundboard-upload')));
      await tester.pumpAndSettle();
      expect(sounds.added, ['circle-1:big bell:🔔']);
      expect(find.text('big bell'), findsOneWidget);

      await tester.longPress(
        find.byKey(const ValueKey('soundboard-sound-sound-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('soundboard-menu-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('soundboard-delete-confirm')));
      await tester.pumpAndSettle();
      expect(sounds.deleted, ['sound-1']);
      expect(find.text('Airhorn'), findsNothing);
      await close(tester);
    });
  });

  test('only connected members who may speak can play', () {
    const lounge = VoiceSession(
      circleId: 'circle-1',
      channelId: 'ch-lounge',
      conversationId: 'conv-lounge',
      channelName: 'Lounge',
      status: VoiceSessionStatus.connected,
    );
    expect(canPlaySoundsIn(lounge, 'ch-lounge'), isTrue);
    expect(canPlaySoundsIn(lounge, 'ch-other'), isFalse);
    expect(canPlaySoundsIn(null, 'ch-lounge'), isFalse);
    expect(
      canPlaySoundsIn(lounge.copyWith(serverMute: true), 'ch-lounge'),
      isFalse,
    );
    expect(
      canPlaySoundsIn(
        lounge.copyWith(status: VoiceSessionStatus.connecting),
        'ch-lounge',
      ),
      isFalse,
    );
    final stage = lounge.copyWith(stage: true);
    expect(canPlaySoundsIn(stage, 'ch-lounge'), isFalse);
    expect(
      canPlaySoundsIn(stage.copyWith(stageSpeaker: true), 'ch-lounge'),
      isTrue,
    );
  });

  group('soundboard volume', () {
    test('is saved with the voice settings', () {
      const settings = VoiceSettings(soundboardVolume: 0.25);
      final restored = VoiceSettings.fromJson(settings.toJson());
      expect(restored.soundboardVolume, 0.25);
      expect(restored, settings);
      expect(
        VoiceSettings.fromJson(const {}).soundboardVolume,
        defaultSoundboardVolume,
      );
      expect(
        VoiceSettings.fromJson(const {'soundboard_volume': 3}).soundboardVolume,
        1,
      );
    });

    testWidgets('Settings → Voice has a slider for it', (tester) async {
      final store = InMemoryVoiceSettingsStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [voiceSettingsStoreProvider.overrideWithValue(store)],
          child: const MaterialApp(home: VoiceSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('voice-soundboard-volume'));
      await tester.scrollUntilVisible(slider, 100);
      expect(find.text('80%'), findsOneWidget);
      await tester.drag(slider, const Offset(-2000, 0));
      await tester.pumpAndSettle();
      expect(store.saved?.soundboardVolume, 0);
      expect(
        find.byKey(const ValueKey('voice-soundboard-volume-value')),
        findsOneWidget,
      );
      expect(find.text('0%'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _soundJson(String id, String name, {String? emoji}) => {
  'id': id,
  'circle_id': 'circle-1',
  'name': name,
  'emoji': emoji,
  'storage_path': 'circle-1/$id.mp3',
  'mime_type': 'audio/mpeg',
  'duration_ms': 1200,
};

class _FakeSoundboardRepository implements SoundboardRepository {
  final sounds = <CircleSound>[
    CircleSound.fromJson(_soundJson('sound-1', 'Airhorn', emoji: '📯')),
  ];
  final played = <String>[];
  final added = <String>[];
  final deleted = <String>[];
  final listening = <String>[];
  var cancelled = 0;
  var signed = 0;
  Object? playError;
  final _plays = StreamController<SoundboardPlay>.broadcast();

  void emitPlay(String channelId, String soundId) {
    _plays.add(
      SoundboardPlay(channelId: channelId, soundId: soundId, userId: 'user-2'),
    );
  }

  @override
  Future<List<CircleSound>> listSounds(String circleId) async =>
      List.of(sounds);

  @override
  Future<CircleSound> addSound({
    required String circleId,
    required String name,
    String? emoji,
    required Uint8List bytes,
  }) async {
    added.add('$circleId:$name:$emoji');
    final sound = CircleSound.fromJson(
      _soundJson('sound-${sounds.length + 1}', name, emoji: emoji),
    );
    sounds.add(sound);
    return sound;
  }

  @override
  Future<void> deleteSound(String soundId) async {
    deleted.add(soundId);
    sounds.removeWhere((sound) => sound.id == soundId);
  }

  @override
  Future<String> createSoundUrl(String storagePath) async {
    signed++;
    return 'url:$storagePath';
  }

  @override
  Future<void> play({
    required String channelId,
    required String soundId,
  }) async {
    final error = playError;
    if (error != null) {
      throw error;
    }
    played.add('$channelId:$soundId');
  }

  @override
  Stream<SoundboardPlay> plays(String channelId) {
    listening.add(channelId);
    late StreamSubscription<SoundboardPlay> subscription;
    late StreamController<SoundboardPlay> controller;
    controller = StreamController<SoundboardPlay>(
      onListen: () {
        subscription = _plays.stream
            .where((play) => play.channelId == channelId)
            .listen(controller.add);
      },
      onCancel: () async {
        cancelled++;
        await subscription.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<void> soundChanges(String circleId) => const Stream.empty();
}

class _FakeSoundboardPlayer implements SoundboardPlayer {
  final played = <String>[];

  @override
  Future<void> play(String url, {required double volume}) async {
    played.add('$url@$volume');
  }
}

class _FakeSoundboardDataSource implements SoundboardDataSource {
  final results = <String, Object?>{};
  final errors = <String, Object>{};
  final calls = <List<Object?>>[];
  final uploads = <String>[];
  final removed = <String>[];
  final inserts = StreamController<Map<String, dynamic>>.broadcast();

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
  Future<void> uploadBinary({
    required String path,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    uploads.add('$path $mimeType');
  }

  @override
  Future<void> remove(String path) async => removed.add(path);

  @override
  Future<String> createSignedUrl(String path, Duration expiresIn) async {
    return 'signed:$path';
  }

  @override
  Stream<Map<String, dynamic>> playInserts(String channelId) => inserts.stream;

  @override
  Stream<void> soundChanges(String circleId) => const Stream.empty();
}
