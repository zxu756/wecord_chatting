import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice_input/voice_input_controller.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';
import 'package:wecord/shared/l10n/l10n.dart';

import 'fake_voice_recognizer.dart';

class _Setup {
  _Setup({FakeVoiceRecognizer? recognizer, bool browserConsent = false})
    : recognizer = recognizer ?? FakeVoiceRecognizer(),
      store = InMemoryVoiceInputStore(browserConsent: browserConsent) {
    container = ProviderContainer(
      overrides: [
        voiceRecognizerProvider.overrideWithValue(this.recognizer),
        voiceInputStoreProvider.overrideWithValue(store),
      ],
    );
  }

  final FakeVoiceRecognizer recognizer;
  final InMemoryVoiceInputStore store;
  late final ProviderContainer container;

  VoiceInputController get controller =>
      container.read(voiceInputProvider.notifier);
  VoiceInputState get state => container.read(voiceInputProvider);

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<TextEditingController> listen({
    String text = '',
    int? caret,
    String owner = 'chat-1',
  }) async {
    final field = TextEditingController(text: text);
    if (caret != null) {
      field.selection = TextSelection.collapsed(offset: caret);
    }
    await controller.start(owner: owner, field: field);
    await settle();
    return field;
  }
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('writing into the field', () {
    test('words appear live and are kept by Done', () async {
      final setup = _Setup();
      final field = await setup.listen();
      expect(setup.state.phase, VoicePhase.listening);
      expect(setup.recognizer.starts.single.locale, 'en-US');

      setup.recognizer.session.say('hello');
      expect(field.text, 'hello');
      setup.recognizer.session.say('hello there');
      expect(field.text, 'hello there');
      expect(setup.state.partial, 'hello there');
      // The caret follows the words.
      expect(field.selection, const TextSelection.collapsed(offset: 11));

      await setup.controller.done();
      await setup.settle();
      expect(setup.recognizer.session.stopped, isTrue);
      expect(setup.state.phase, VoicePhase.idle);
      expect(field.text, 'hello there');
    });

    test('they go in at the caret, spaced like the language', () async {
      final setup = _Setup();
      final field = await setup.listen(text: 'Meet me at the gate', caret: 11);
      // "Meet me at |the gate"
      setup.recognizer.session.say('around');
      expect(field.text, 'Meet me at around the gate');
      await setup.controller.done();
      await setup.settle();
    });

    test('after text that ends in a space there is no second space', () async {
      final setup = _Setup();
      final field = await setup.listen(text: 'Hi ');
      setup.recognizer.session.say('Ada');
      expect(field.text, 'Hi Ada');
    });

    test('Chinese runs together', () async {
      AppStrings.isChinese = true;
      final setup = _Setup();
      expect(setup.state.language, VoiceInputLanguage.chinese);
      final field = await setup.listen(text: '你好');
      expect(setup.recognizer.starts.single.locale, 'zh-CN');
      setup.recognizer.session.say('今天去爬山');
      expect(field.text, '你好今天去爬山');
    });

    test('Cancel puts the field back as it was', () async {
      final setup = _Setup();
      final field = await setup.listen(text: 'draft', caret: 5);
      setup.recognizer.session.say('something else');
      expect(field.text, 'draft something else');

      await setup.controller.cancel();
      expect(setup.state.phase, VoicePhase.idle);
      expect(field.text, 'draft');
      expect(field.selection, const TextSelection.collapsed(offset: 5));
      expect(setup.recognizer.session.cancelled, isTrue);
    });

    test('typing while listening ends it and keeps what was typed', () async {
      final setup = _Setup();
      final field = await setup.listen(text: 'a');
      setup.recognizer.session.say('spoken');
      expect(field.text, 'a spoken');
      field.text = 'a spoken!';
      await setup.settle();
      expect(setup.state.phase, VoicePhase.idle);
      expect(setup.recognizer.session.cancelled, isTrue);
      // Words that arrive late do not overwrite the typing.
      setup.recognizer.session.say('late words');
      await setup.settle();
      expect(field.text, 'a spoken!');
    });

    test('Done waits for the last words, but not forever', () async {
      final setup = _Setup();
      final field = await setup.listen();
      setup.recognizer.session
        ..endsOnStop = false
        ..say('almost');
      await setup.controller.done();
      expect(setup.state.phase, VoicePhase.stopping);
      await Future<void>.delayed(
        VoiceInputController.finishTimeout + const Duration(milliseconds: 50),
      );
      expect(setup.state.phase, VoicePhase.idle);
      expect(field.text, 'almost');
    });

    test(
      'a session the recognizer ends goes on after the words so far',
      () async {
        final setup = _Setup();
        final field = await setup.listen();
        setup.recognizer.session
          ..say('first part')
          ..end();
        await setup.settle();
        expect(setup.recognizer.sessions, hasLength(2));
        expect(setup.state.phase, VoicePhase.listening);
        setup.recognizer.session.say('second part');
        expect(field.text, 'first part second part');
      },
    );

    test('silence over and over ends with a message', () async {
      final setup = _Setup();
      final field = await setup.listen(text: 'kept');
      setup.recognizer.session.end();
      await setup.settle();
      setup.recognizer.session.end();
      await setup.settle();
      expect(setup.state.phase, VoicePhase.error);
      expect(setup.state.failure, VoiceInputFailure.noSpeech);
      expect(field.text, 'kept');
    });

    test('it stops by itself when nothing new is heard', () {
      fakeAsync((async) {
        final setup = _Setup();
        final field = TextEditingController();
        setup.controller.start(owner: 'chat-1', field: field);
        async.flushMicrotasks();
        setup.recognizer.session.say('hello');
        async.elapse(
          VoiceInputController.idleTimeout - const Duration(seconds: 1),
        );
        expect(setup.state.phase, VoicePhase.listening);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(setup.recognizer.session.stopped, isTrue);
        expect(setup.state.phase, VoicePhase.idle);
        expect(field.text, 'hello');
      });
    });
  });

  group('language', () {
    test(
      'switching while listening listens again in the new language',
      () async {
        final setup = _Setup();
        final field = await setup.listen();
        setup.recognizer.session.say('good morning');

        await setup.controller.setLanguage(VoiceInputLanguage.chinese);
        await setup.settle();
        expect(setup.recognizer.sessions.first.cancelled, isTrue);
        expect(setup.recognizer.starts.last.locale, 'zh-CN');
        expect(setup.state.phase, VoicePhase.listening);
        expect(setup.state.language, VoiceInputLanguage.chinese);

        setup.recognizer.session.say('你好');
        expect(field.text, 'good morning你好');
      },
    );

    test('a language with no recognizer says so', () async {
      final recognizer = FakeVoiceRecognizer()..unsupportedLocales.add('zh-CN');
      final setup = _Setup(recognizer: recognizer);
      await setup.listen();
      await setup.controller.setLanguage(VoiceInputLanguage.chinese);
      await setup.settle();
      expect(setup.state.phase, VoicePhase.error);
      expect(setup.state.failure, VoiceInputFailure.unsupportedLanguage);
      // Back to the other language works from the same message.
      await setup.controller.setLanguage(VoiceInputLanguage.english);
      await setup.settle();
      expect(setup.state.phase, VoicePhase.listening);
    });

    test(
      'choosing a language at rest is remembered for the next time',
      () async {
        final setup = _Setup();
        await setup.controller.setLanguage(VoiceInputLanguage.chinese);
        final field = await setup.listen();
        expect(setup.recognizer.starts.single.locale, 'zh-CN');
        await setup.controller.cancel();
        expect(field.text, '');
        expect(setup.state.language, VoiceInputLanguage.chinese);
      },
    );
  });

  group('permission and consent', () {
    test('on-device recognition needs no question', () async {
      final setup = _Setup();
      await setup.listen();
      expect(setup.state.phase, VoicePhase.listening);
      expect(setup.recognizer.starts.single.allowServer, isFalse);
    });

    test('a server language waits for the person to agree', () async {
      final recognizer = FakeVoiceRecognizer(
        engine: VoiceInputEngine.appleServer,
      );
      final setup = _Setup(recognizer: recognizer);
      await setup.listen();
      expect(setup.state.phase, VoicePhase.consent);
      expect(setup.state.engine, VoiceInputEngine.appleServer);
      expect(recognizer.starts, isEmpty);

      await setup.controller.grantConsent();
      await setup.settle();
      expect(setup.state.phase, VoicePhase.listening);
      expect(recognizer.starts.single.allowServer, isTrue);
    });

    test('declining listens to nothing and leaves the field alone', () async {
      final recognizer = FakeVoiceRecognizer(
        engine: VoiceInputEngine.appleServer,
      );
      final setup = _Setup(recognizer: recognizer);
      final field = await setup.listen(text: 'draft');
      await setup.controller.cancel();
      expect(setup.state.phase, VoicePhase.idle);
      expect(recognizer.starts, isEmpty);
      expect(field.text, 'draft');
    });

    test('the browser asks once, then remembers', () async {
      final recognizer = FakeVoiceRecognizer(engine: VoiceInputEngine.browser);
      final setup = _Setup(recognizer: recognizer);
      await setup.listen();
      expect(setup.state.phase, VoicePhase.consent);
      await setup.controller.grantConsent();
      await setup.settle();
      expect(await setup.store.loadBrowserConsent(), isTrue);
      await setup.controller.cancel();

      // A new run of the app still has the agreement.
      final again = _Setup(recognizer: recognizer, browserConsent: true);
      await again.listen();
      expect(again.state.phase, VoicePhase.listening);
    });

    test(
      'a language the system turns out to need a server for asks too',
      () async {
        final setup = _Setup();
        setup.recognizer.startError = const VoiceInputException(
          VoiceInputFailure.unavailable,
          needsServer: true,
        );
        await setup.listen();
        expect(setup.state.phase, VoicePhase.consent);
      },
    );

    test('a refused microphone is explained and can be tried again', () async {
      final setup = _Setup();
      setup.recognizer.startError = const VoiceInputException(
        VoiceInputFailure.micDenied,
      );
      await setup.listen();
      expect(setup.state.phase, VoicePhase.error);
      expect(setup.state.failure, VoiceInputFailure.micDenied);

      await setup.controller.retry();
      await setup.settle();
      expect(setup.state.phase, VoicePhase.listening);
    });

    test('a recognizer that is not there says so', () async {
      final setup = _Setup(recognizer: FakeVoiceRecognizer(available: false));
      await setup.listen();
      expect(setup.state.failure, VoiceInputFailure.unavailable);
      setup.controller.dismissError();
      expect(setup.state.phase, VoicePhase.idle);
    });

    test('an error from the recognizer keeps the words so far', () async {
      final setup = _Setup();
      final field = await setup.listen();
      setup.recognizer.session
        ..say('half a sentence')
        ..fail(VoiceInputFailure.failed);
      expect(setup.state.phase, VoicePhase.error);
      expect(field.text, 'half a sentence');
      setup.controller.dismissError();
      expect(field.text, 'half a sentence');
    });
  });

  group('who it belongs to', () {
    test('only one dictation at a time: a new one cancels the old', () async {
      final setup = _Setup();
      final first = await setup.listen(text: 'one', owner: 'chat-1');
      setup.recognizer.session.say('spoken');
      final second = await setup.listen(text: 'two', owner: 'chat-2');
      expect(first.text, 'one', reason: 'the first field is put back');
      expect(setup.state.owner, 'chat-2');
      expect(setup.recognizer.sessions, hasLength(2));
      setup.recognizer.session.say('words');
      expect(second.text, 'two words');
    });

    test('starting again in the same chat does nothing', () async {
      final setup = _Setup();
      final field = await setup.listen(owner: 'chat-1');
      await setup.controller.start(owner: 'chat-1', field: field);
      expect(setup.recognizer.sessions, hasLength(1));
    });

    test('levels keep the latest readings for the waveform', () async {
      final setup = _Setup();
      await setup.listen();
      for (var i = 0; i < voiceWaveBars + 10; i++) {
        setup.recognizer.session.level(i / 100);
      }
      expect(setup.state.levels, hasLength(voiceWaveBars));
      expect(setup.state.levels.last, closeTo((voiceWaveBars + 9) / 100, 1e-9));
    });
  });
}
