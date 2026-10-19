import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice_input/voice_input_controller.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

import '../../voice_input/fake_voice_recognizer.dart';
import '../voice_fakes.dart';

/// The data a fake call was asked to publish on the caption topic.
List<Map<String, Object?>> sent(FakeVoiceCall call) => [
  for (final message in call.published)
    if (message.topic == captionTopic)
      {
        ...jsonDecode(utf8.decode(message.data)) as Map<String, Object?>,
        '_reliable': message.reliable,
      },
];

class _Setup {
  _Setup({this.host = true, FakeVoiceRecognizer? recognizer})
    : recognizer = recognizer ?? FakeVoiceRecognizer() {
    repository = FakeVoiceRepository();
    connector = FakeVoiceCallConnector();
    connector.prepare = (call) {
      call.localCaptionsHost = host;
      call.remotes = remotes;
    };
    container = ProviderContainer(
      overrides: [
        voiceRepositoryProvider.overrideWithValue(repository),
        voiceCallConnectorProvider.overrideWithValue(connector),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'user-1')),
        ),
        voiceRecognizerProvider.overrideWithValue(this.recognizer),
        voiceInputStoreProvider.overrideWithValue(InMemoryVoiceInputStore()),
        captionClockProvider.overrideWithValue(() => now),
      ],
    );
    _current = this;
    container.listen(captionsProvider, (previous, next) {});
    container.listen(voiceSessionProvider, (previous, next) {});
  }

  final bool host;
  final remotes = const [
    VoiceCallParticipant(userId: 'user-2', name: 'Bart'),
    VoiceCallParticipant(userId: 'user-3', name: 'Grace'),
  ];
  final FakeVoiceRecognizer recognizer;
  late final FakeVoiceRepository repository;
  late final FakeVoiceCallConnector connector;
  late final ProviderContainer container;
  var now = DateTime(2026, 10, 19, 12);

  CaptionsController get captions => container.read(captionsProvider.notifier);
  CaptionsState get state => container.read(captionsProvider);
  FakeVoiceCall get call => connector.last;

  late WidgetTester tester;

  Future<void> join(WidgetTester tester) async {
    this.tester = tester;
    await container
        .read(voiceSessionProvider.notifier)
        .join(
          circleId: 'circle-1',
          channelId: 'ch-lounge',
          conversationId: 'conv-lounge',
          channelName: 'Lounge',
        );
    await tester.pump();
  }

  /// Someone else sends a caption message.
  Future<void> receive(
    String userId,
    List<int> data, {
    String topic = captionTopic,
  }) async {
    call.receiveData(userId, topic, data);
    // The message crosses two streams before the controller sees it.
    await tester.pump();
    await tester.pump();
  }

  /// [userId] starts listening as someone who may turn captions on.
  void makeHost(String userId) {
    call.remotes = [
      for (final remote in call.remotes)
        VoiceCallParticipant(
          userId: remote.userId,
          name: remote.name,
          captionsHost: remote.userId == userId,
        ),
    ];
    call.update();
  }

  /// Leaves the call (which stops its timers) and drops the providers.
  Future<void> shutdown(WidgetTester tester) async {
    await container.read(voiceSessionProvider.notifier).leave();
    await tester.pump();
    container.dispose();
    await tester.pump();
  }
}

_Setup? _current;

void captionsTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    _current = null;
    await body(tester);
    await _current?.shutdown(tester);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  captionsTest('the host turns captions on and everyone is told', (
    tester,
  ) async {
    final setup = _Setup();
    await setup.join(tester);
    expect(setup.state.active, isFalse);
    expect(setup.captions.canHost, isTrue);

    await setup.captions.start();
    await settle(tester);

    expect(setup.state.active, isTrue);
    expect(setup.state.hostId, 'user-1');
    expect(sent(setup.call).first['k'], 'on');
    // The host listens too, on this device.
    expect(setup.recognizer.starts.single.locale, 'en-US');
    expect(setup.recognizer.startsInCall.single, isTrue);
    expect(setup.state.mic, CaptionMic.listening);

    // Joining people hear about it again.
    final before = sent(setup.call).length;
    setup.call.remotes = [
      ...setup.call.remotes,
      const VoiceCallParticipant(userId: 'user-4', name: 'Dan'),
    ];
    setup.call.update();
    await settle(tester);
    expect(sent(setup.call).length, before + 1);
    expect(sent(setup.call).last['k'], 'on');

    // And it is repeated while it lasts.
    setup.now = setup.now.add(const Duration(seconds: 21));
    await tester.pump(const Duration(seconds: 5));
    expect(sent(setup.call).length, before + 2);
  });

  captionsTest('someone who may not host can not turn captions on', (
    tester,
  ) async {
    final setup = _Setup(host: false);
    await setup.join(tester);
    expect(setup.captions.canHost, isFalse);
    await setup.captions.start();
    expect(setup.state.active, isFalse);
    expect(sent(setup.call), isEmpty);
    expect(setup.recognizer.starts, isEmpty);
  });

  captionsTest('what you say becomes a caption line sent to the room', (
    tester,
  ) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);

    final session = setup.recognizer.session;
    session.say('Hello everyone');
    expect(setup.state.live['user-1']!.text, 'Hello everyone');
    final partial = sent(setup.call).last;
    expect(partial['k'], 'p');
    expect(partial['t'], 'Hello everyone');
    expect(partial['_reliable'], isFalse);

    // A pause settles it.
    setup.now = setup.now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(setup.state.lines.single.text, 'Hello everyone');
    expect(setup.state.lines.single.speakerId, 'user-1');
    expect(setup.state.live, isEmpty);
    final settled = sent(setup.call).last;
    expect(settled['k'], 'f');
    expect(settled['_reliable'], isTrue);
    expect(settled['i'], 0);

    // The next line is the next id.
    session.say('Hello everyone second line');
    setup.now = setup.now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(setup.state.lines.last.text, 'second line');
    expect(sent(setup.call).last['i'], 1);
  });

  captionsTest(
    'lines from others are put together, only from people in the call',
    (tester) async {
      final setup = _Setup();
      await setup.join(tester);
      await setup.captions.start();
      await settle(tester);

      await setup.receive(
        'user-2',
        encodeCaptionLine(
          id: 0,
          text: 'I am talking',
          at: setup.now,
          isFinal: false,
        ),
      );
      expect(setup.state.live['user-2']!.text, 'I am talking');
      await setup.receive(
        'user-2',
        encodeCaptionLine(
          id: 0,
          text: 'I am talking now.',
          at: setup.now,
          isFinal: true,
        ),
      );
      expect(setup.state.live.containsKey('user-2'), isFalse);
      expect(setup.state.lines.single.text, 'I am talking now.');
      expect(setup.state.lines.single.speakerId, 'user-2');
      expect(setup.state.nameOf('user-2'), 'Bart');

      // A stranger to the room, or the wrong topic, is ignored.
      await setup.receive(
        'user-9',
        encodeCaptionLine(
          id: 0,
          text: 'Intruder',
          at: setup.now,
          isFinal: true,
        ),
      );
      await setup.receive(
        'user-2',
        encodeCaptionLine(
          id: 1,
          text: 'Elsewhere',
          at: setup.now,
          isFinal: true,
        ),
        topic: 'wecord.other',
      );
      await setup.receive('user-2', utf8.encode('garbage'));
      expect(setup.state.lines, hasLength(1));

      // A late, older partial does not replace a newer one.
      await setup.receive(
        'user-3',
        encodeCaptionLine(id: 5, text: 'newer', at: setup.now, isFinal: false),
      );
      await setup.receive(
        'user-3',
        encodeCaptionLine(id: 4, text: 'older', at: setup.now, isFinal: false),
      );
      expect(setup.state.live['user-3']!.text, 'newer');
    },
  );

  captionsTest('nobody can turn captions on by sending a message', (
    tester,
  ) async {
    final setup = _Setup(host: false);
    await setup.join(tester);

    await setup.receive('user-2', encodeCaptionControl(on: true));
    expect(setup.state.active, isFalse);
    expect(setup.recognizer.starts, isEmpty);

    // Someone the voice server says may, can.
    setup.makeHost('user-2');
    await setup.receive('user-2', encodeCaptionControl(on: true));
    await settle(tester);
    expect(setup.state.active, isTrue);
    expect(setup.state.hostId, 'user-2');
    // This device starts listening to its own microphone.
    expect(setup.recognizer.starts, hasLength(1));
    expect(setup.state.mic, CaptionMic.listening);

    // Another person who may not host can not turn them off.
    await setup.receive('user-3', encodeCaptionControl(on: false));
    expect(setup.state.active, isTrue);
    await setup.receive('user-2', encodeCaptionControl(on: false));
    expect(setup.state.active, isFalse);
    expect(setup.state.lines, isEmpty);
    expect(
      setup.recognizer.session.stopped || setup.recognizer.session.cancelled,
      isTrue,
    );
  });

  captionsTest('captions end when the host leaves or goes quiet', (
    tester,
  ) async {
    final setup = _Setup(host: false);
    await setup.join(tester);
    setup.makeHost('user-2');
    await setup.receive('user-2', encodeCaptionControl(on: true));
    await settle(tester);
    expect(setup.state.active, isTrue);

    // Still heard from: stays on.
    setup.now = setup.now.add(const Duration(seconds: 60));
    await setup.receive('user-2', encodeCaptionControl(on: true));
    setup.now = setup.now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 5));
    expect(setup.state.active, isTrue);

    // Not heard from for too long: off.
    setup.now = setup.now.add(captionHostTimeout + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 5));
    expect(setup.state.active, isFalse);

    // The host leaving the call also ends them.
    await setup.receive('user-2', encodeCaptionControl(on: true));
    await settle(tester);
    expect(setup.state.active, isTrue);
    setup.call.remotes = [setup.remotes[1]];
    setup.call.update();
    await settle(tester);
    expect(setup.state.active, isFalse);
  });

  captionsTest('a muted microphone is not listened to', (tester) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.listening);

    await setup.container.read(voiceSessionProvider.notifier).toggleMute();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.paused);
    expect(
      setup.recognizer.session.stopped || setup.recognizer.session.cancelled,
      isTrue,
    );

    await setup.container.read(voiceSessionProvider.notifier).toggleMute();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(setup.state.mic, CaptionMic.listening);
    expect(setup.recognizer.starts, hasLength(2));
  });

  captionsTest('not sharing means nothing is listened to or sent', (
    tester,
  ) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.setSharing(false);
    await setup.captions.start();
    await settle(tester);
    expect(setup.state.active, isTrue);
    expect(setup.recognizer.starts, isEmpty);
    expect(setup.state.mic, CaptionMic.off);

    // Others' captions still show.
    await setup.receive(
      'user-2',
      encodeCaptionLine(id: 0, text: 'Hi', at: setup.now, isFinal: true),
    );
    expect(setup.state.lines.single.text, 'Hi');

    // Choosing to share starts listening; choosing not to stops it.
    await setup.captions.setSharing(true);
    await settle(tester);
    expect(setup.recognizer.starts, hasLength(1));
    setup.recognizer.session.say('half a sentence');
    await setup.captions.setSharing(false);
    await settle(tester);
    expect(setup.state.live, isEmpty);
    final lastSent = sent(setup.call).where((m) => m['k'] == 'f');
    expect(lastSent, isEmpty);
  });

  captionsTest('a device that can not make captions says so', (tester) async {
    final setup = _Setup(recognizer: FakeVoiceRecognizer(supported: false));
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.unsupported);
    expect(sent(setup.call).map((m) => m['k']), contains('no'));

    // What others say about their devices is kept.
    await setup.receive('user-2', encodeCaptionSupport(supported: false));
    expect(setup.state.unsupported, {'user-2'});
    await setup.receive('user-2', encodeCaptionSupport(supported: true));
    expect(setup.state.unsupported, isEmpty);
  });

  captionsTest('a recognizer that needs a service asks first', (tester) async {
    final setup = _Setup(
      recognizer: FakeVoiceRecognizer(engine: VoiceInputEngine.appleServer),
    );
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.needsConsent);
    expect(setup.recognizer.starts, isEmpty);

    await setup.captions.allowServer();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.listening);
    expect(setup.recognizer.starts.single.allowServer, isTrue);
  });

  captionsTest('permission denied is shown and can be tried again', (
    tester,
  ) async {
    final recognizer = FakeVoiceRecognizer()
      ..startError = const VoiceInputException(VoiceInputFailure.speechDenied);
    final setup = _Setup(recognizer: recognizer);
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.denied);
    expect(sent(setup.call).map((m) => m['k']), contains('no'));

    setup.captions.retry();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.listening);
    expect(sent(setup.call).map((m) => m['k']), contains('ok'));
  });

  captionsTest('voice input in a chat takes the recognizer for a while', (
    tester,
  ) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    expect(setup.state.mic, CaptionMic.listening);

    final field = TextEditingController();
    final starting = setup.container
        .read(voiceInputProvider.notifier)
        .start(owner: 'chat-1', field: field);
    await settle(tester);
    expect(setup.state.mic, CaptionMic.paused);

    await starting;
    await setup.container.read(voiceInputProvider.notifier).cancel();
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(setup.state.mic, CaptionMic.listening);
  });

  captionsTest('stopping hands the host the words and tells everyone', (
    tester,
  ) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    setup.recognizer.session.say('We ship on Friday');
    await setup.receive(
      'user-2',
      encodeCaptionLine(
        id: 0,
        text: 'I will write the notes',
        at: setup.now,
        isFinal: true,
      ),
    );

    final transcript = await setup.captions.stop();
    await settle(tester);

    expect(setup.state.active, isFalse);
    expect(sent(setup.call).last['k'], 'off');
    expect(transcript, isNotNull);
    expect(transcript!.conversationId, 'conv-lounge');
    expect(transcript.circleId, 'circle-1');
    expect(
      transcript.lines.map((l) => l.text),
      unorderedEquals(['I will write the notes', 'We ship on Friday']),
    );
    expect(transcript.speakerCount, 2);
    final entries = transcript.toRequestEntries();
    expect(entries.map((e) => e['speaker']).toSet(), {'user-1', 'user-2'});
    expect(entries.every((e) => (e['at']! as int) >= 0), isTrue);
    // Nothing of it stays.
    expect(setup.state.lines, isEmpty);
    expect(setup.state.startedAt, isNull);
  });

  captionsTest('ending the call forgets everything', (tester) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    await setup.receive(
      'user-2',
      encodeCaptionLine(id: 0, text: 'Bye', at: setup.now, isFinal: true),
    );
    expect(setup.state.lines, hasLength(1));

    await setup.container.read(voiceSessionProvider.notifier).leave();
    await settle(tester);
    expect(setup.state.active, isFalse);
    expect(setup.state.lines, isEmpty);
    expect(setup.state.callKey, isNull);
  });

  captionsTest('the language can be switched while listening', (tester) async {
    final setup = _Setup();
    await setup.join(tester);
    await setup.captions.start();
    await settle(tester);
    await setup.captions.setLanguage(VoiceInputLanguage.chinese);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(setup.recognizer.starts.map((s) => s.locale), ['en-US', 'zh-CN']);
  });
}
