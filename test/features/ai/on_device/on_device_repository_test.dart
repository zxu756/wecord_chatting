import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';
import 'package:wecord/features/ai/on_device/on_device_ai_repository.dart';
import 'package:wecord/features/ai/on_device/on_device_chat_reader.dart';
import 'package:wecord/features/ai/translate_repository.dart';

import '../ai_fakes.dart';
import 'on_device_fakes.dart';

class _Setup {
  _Setup({this.prefer = true, bool supported = true}) {
    backend = FakeOnDeviceBackend(supported: supported);
    repository = OnDeviceFirstAiRepository(
      server: server,
      serverTranslate: server,
      backend: backend,
      gate: gate,
      reader: reader,
      prefersOnDevice: () => prefer,
    );
  }

  final server = FakeAiRepository();
  late final FakeOnDeviceBackend backend;
  final gate = FakeOnDeviceGate();
  final reader = FakeOnDeviceReader();
  bool prefer;
  late final OnDeviceFirstAiRepository repository;
}

OnDeviceMessageText _text(String id, String body, {String type = 'text'}) =>
    OnDeviceMessageText(id: id, type: type, body: body);

void main() {
  group('rewrite and translate', () {
    test('run on the device when it prefers and can', () async {
      final s = _Setup();
      final result = await s.repository.rewrite(
        mode: AiRewriteMode.polite,
        text: 'give me the file',
        conversationId: 'c1',
      );
      expect(result, 'device: give me the file');
      expect(s.backend.rewriteCalls.single.mode, AiRewriteMode.polite);
      expect(
        s.server.rewriteCalls,
        isEmpty,
        reason: 'nothing leaves the device',
      );
      expect(s.gate.checks, ['c1']);
    });

    test('a rewrite that translates uses the translate request', () async {
      final s = _Setup();
      final result = await s.repository.rewrite(
        mode: AiRewriteMode.translate,
        text: 'hello',
        target: AiLanguage.japanese,
      );
      expect(result, 'ja: hello');
      expect(s.backend.rewriteCalls, isEmpty);
      expect(s.server.rewriteCalls, isEmpty);
    });

    test('translate runs on the device', () async {
      final s = _Setup();
      expect(
        await s.repository.translate(text: 'hi', target: AiLanguage.chinese),
        'zh: hi',
      );
      expect(s.server.translateCalls, isEmpty);
    });

    test('goes to the server when the preference is off', () async {
      final s = _Setup(prefer: false);
      final result = await s.repository.translate(
        text: 'hi',
        target: AiLanguage.chinese,
      );
      expect(result, 'Translated text.');
      expect(s.backend.translateCalls, isEmpty);
      expect(s.backend.availabilityCalls, 0);
      expect(s.gate.checks, isEmpty, reason: 'the server enforces its own');
    });

    test('goes to the server where there is no on-device model', () async {
      final s = _Setup(supported: false);
      await s.repository.rewrite(mode: AiRewriteMode.fix, text: 'teh');
      expect(s.server.rewriteCalls, hasLength(1));
      expect(s.backend.availabilityCalls, 0);
    });

    for (final reason in OnDeviceAiUnavailable.values) {
      test(
        'goes to the server when the model is unavailable: $reason',
        () async {
          final s = _Setup();
          s.backend.status = OnDeviceAiStatus.unavailable(reason);
          final result = await s.repository.rewrite(
            mode: AiRewriteMode.fix,
            text: 'teh',
            conversationId: 'c1',
          );
          expect(result, 'Polished text.');
          expect(s.server.rewriteCalls.single.text, 'teh');
          expect(s.backend.rewriteCalls, isEmpty);
        },
      );
    }

    test('goes to the server when the model goes away mid-request', () async {
      final s = _Setup();
      s.backend.error = const OnDeviceAiUnavailableException(
        OnDeviceAiUnavailable.modelNotReady,
      );
      expect(
        await s.repository.translate(text: 'hi', target: AiLanguage.chinese),
        'Translated text.',
      );
    });

    test('a failed request is an error, never sent to the server', () async {
      final s = _Setup();
      s.backend.error = const OnDeviceAiFailedException(
        OnDeviceAiFailureKind.refused,
      );
      await expectLater(
        s.repository.rewrite(mode: AiRewriteMode.fix, text: 'text'),
        throwsA(
          isA<AiOnDeviceFailedException>().having(
            (e) => e.kind,
            'kind',
            OnDeviceAiFailureKind.refused,
          ),
        ),
      );
      expect(s.server.rewriteCalls, isEmpty);
    });

    test('a long text goes in pieces and comes back joined', () async {
      final s = _Setup();
      final text = List.generate(
        120,
        (i) => 'Sentence number $i is part of a long draft.',
      ).join(' ');
      final result = await s.repository.rewrite(
        mode: AiRewriteMode.shorter,
        text: text,
      );
      expect(s.backend.rewriteCalls.length, greaterThan(1));
      expect(
        s.backend.rewriteCalls.map((c) => c.text).join(' '),
        text,
        reason: 'every piece is sent once, in order',
      );
      expect(result, startsWith('device: Sentence number 0'));
    });

    test('empty text is rejected', () async {
      final s = _Setup();
      await expectLater(
        s.repository.translate(text: '   ', target: AiLanguage.english),
        throwsA(isA<AiRejectedException>()),
      );
    });
  });

  group('the server\'s rules still hold on the device', () {
    final refusals = <String, Object>{
      'the person turned AI off': const AiTurnedOffException(),
      'the chat is locked': const AiChatLockedException(),
      'the circle turned AI off': const AiDisabledInCircleException(),
      'the rules could not be checked': const AiFailedException(),
    };
    for (final MapEntry(key: name, value: error) in refusals.entries) {
      test('$name: nothing is processed, read or sent', () async {
        final s = _Setup()..gate.error = error;
        await expectLater(
          s.repository.rewrite(
            mode: AiRewriteMode.fix,
            text: 'secret',
            conversationId: 'c1',
          ),
          throwsA(same(error)),
        );
        await expectLater(
          s.repository.translate(
            text: 'secret',
            target: AiLanguage.english,
            conversationId: 'c1',
          ),
          throwsA(same(error)),
        );
        await expectLater(
          s.repository.summarize(conversationId: 'c1', recent: true),
          throwsA(same(error)),
        );
        await expectLater(
          s.repository.translateBatch(
            conversationId: 'c1',
            messageIds: ['m1'],
            target: AiLanguage.english,
          ),
          throwsA(same(error)),
        );
        expect(s.backend.rewriteCalls, isEmpty);
        expect(s.backend.translateCalls, isEmpty);
        expect(s.backend.summarizeCalls, isEmpty);
        expect(s.reader.logRequests, isEmpty);
        expect(s.reader.messageRequests, isEmpty);
        expect(s.server.rewriteCalls, isEmpty);
        expect(s.server.translateCalls, isEmpty);
        expect(s.server.summarizeCalls, isEmpty);
        expect(s.server.batchCalls, isEmpty);
      });
    }
  });

  group('summarize', () {
    test('summarizes the chat on the device', () async {
      final s = _Setup();
      final summary = await s.repository.summarize(
        conversationId: 'c1',
        afterMessageId: 'm0',
        language: AiLanguage.chinese,
      );
      expect(summary, isNotNull);
      expect(summary!.text, '- Summary 1');
      expect(summary.messageCount, 2);
      expect(summary.summarizedCount, 2);
      expect(summary.firstMessageId, 'm1');
      expect(s.backend.summarizeCalls.single.lines, [
        'Ana: Lunch at noon?',
        'Ben: Yes.',
      ]);
      expect(s.backend.summarizeCalls.single.language, AiLanguage.chinese);
      expect(s.reader.logRequests.single.afterMessageId, 'm0');
      expect(s.server.summarizeCalls, isEmpty);
    });

    test('is null when there is nothing to summarize', () async {
      final s = _Setup()
        ..reader.log = const OnDeviceChatLog(lines: [], total: 0);
      expect(await s.repository.summarize(conversationId: 'c1'), isNull);
      expect(s.backend.summarizeCalls, isEmpty);
    });

    test('a chat that cannot be read is rejected', () async {
      final s = _Setup()..reader.log = null;
      await expectLater(
        s.repository.summarize(conversationId: 'c1'),
        throwsA(isA<AiRejectedException>()),
      );
    });

    test('a long chat is summarized in parts and merged', () async {
      final s = _Setup();
      s.reader.log = OnDeviceChatLog(
        lines: [
          for (var i = 0; i < 400; i++)
            'Ana: this is message number $i of the long catch-up chat',
        ],
        total: 400,
        firstMessageId: 'm1',
      );
      s.backend.summaryFor = (request, lines, merge) => merge
          ? '- Merged ${lines.length}'
          : '- Part $request\n- More $request';
      final summary = await s.repository.summarize(conversationId: 'c1');
      final calls = s.backend.summarizeCalls;
      final parts = calls.where((c) => !c.merge).toList();
      expect(parts.length, greaterThan(1));
      expect(
        parts.expand((c) => c.lines).toList(),
        s.reader.log!.lines,
        reason: 'every message is read once, in order',
      );
      expect(calls.last.merge, isTrue);
      expect(summary!.text, startsWith('- Merged'));
      expect(summary.summarizedCount, 400);
    });

    test('goes to the server when the model is not available', () async {
      final s = _Setup();
      s.backend.status = const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.deviceNotEligible,
      );
      final summary = await s.repository.summarize(
        conversationId: 'c1',
        recent: true,
      );
      expect(summary!.messageCount, 24);
      expect(s.server.summarizeCalls.single.recent, isTrue);
      expect(s.reader.logRequests, isEmpty);
    });
  });

  group('translateBatch', () {
    test('translates readable text messages on the device', () async {
      final s = _Setup();
      s.reader.messages = [
        _text('m1', 'Let us meet at noon'),
        _text('m2', 'See you there'),
      ];
      final result = await s.repository.translateBatch(
        conversationId: 'c1',
        messageIds: ['m1', 'm2'],
        target: AiLanguage.chinese,
      );
      expect(result.translations['m1']!.text, 'zh: Let us meet at noon');
      expect(result.translations['m2']!.text, 'zh: See you there');
      expect(s.server.batchCalls, isEmpty);
    });

    test('follows the server\'s skip rules', () async {
      final s = _Setup();
      s.server.storedSettings = const AiTranslateSettings(
        noTranslate: {AiLanguage.japanese},
      );
      s.reader.messages = [
        _text('plain', 'Hello there'),
        OnDeviceMessageText(
          id: 'gone',
          type: 'text',
          body: 'x',
          recalled: true,
        ),
        OnDeviceMessageText(id: 'old', type: 'text', body: 'x', expired: true),
        OnDeviceMessageText(
          id: 'held',
          type: 'text',
          body: 'x',
          underReview: true,
        ),
        OnDeviceMessageText(
          id: 'once',
          type: 'text',
          body: 'x',
          viewOnce: true,
        ),
        _text('pic', 'caption', type: 'image'),
        _text('blank', '   '),
        _text('emoji', '😀 https://example.com'),
        _text('zh', '我们中午见面吧'),
        _text('ja', 'こんにちは、元気ですか'),
        _text('long', 'x' * 1600),
      ];
      final result = await s.repository.translateBatch(
        conversationId: 'c1',
        messageIds: [
          'plain',
          'gone',
          'old',
          'held',
          'once',
          'pic',
          'blank',
          'emoji',
          'zh',
          'ja',
          'long',
          'missing',
        ],
        target: AiLanguage.chinese,
      );
      expect(result.translations.keys, ['plain']);
      expect(result.skipped, {
        'gone': TranslateSkip.unavailable,
        'old': TranslateSkip.unavailable,
        'held': TranslateSkip.unavailable,
        'once': TranslateSkip.unavailable,
        'pic': TranslateSkip.notText,
        'blank': TranslateSkip.nothingToTranslate,
        'emoji': TranslateSkip.nothingToTranslate,
        'zh': TranslateSkip.sameLanguage,
        'ja': TranslateSkip.skipLanguage,
        'long': TranslateSkip.tooLong,
        'missing': TranslateSkip.unavailable,
      });
      expect(s.backend.translateCalls, hasLength(1));
    });

    test('a manual request skips the language rules', () async {
      final s = _Setup();
      s.reader.messages = [_text('zh', '我们中午见面吧')];
      final result = await s.repository.translateBatch(
        conversationId: 'c1',
        messageIds: ['zh'],
        target: AiLanguage.chinese,
        manual: true,
      );
      expect(result.translations.keys, ['zh']);
    });

    test('a message the model fails on is skipped as failed', () async {
      final s = _Setup();
      s.reader.messages = [_text('a', 'Hello world'), _text('b', 'Good night')];
      s.backend
        ..errorOnNth = const OnDeviceAiFailedException(
          OnDeviceAiFailureKind.refused,
        )
        ..errorOnCall = 1;
      final result = await s.repository.translateBatch(
        conversationId: 'c1',
        messageIds: ['a', 'b'],
        target: AiLanguage.chinese,
      );
      expect(result.skipped['a'], TranslateSkip.failed);
      expect(result.translations.keys, ['b']);
      expect(s.server.batchCalls, isEmpty);
    });

    test('goes to the server when the model is unavailable', () async {
      final s = _Setup();
      s.backend.status = const OnDeviceAiStatus.unavailable(
        OnDeviceAiUnavailable.notEnabled,
      );
      final result = await s.repository.translateBatch(
        conversationId: 'c1',
        messageIds: ['m1'],
        target: AiLanguage.english,
        manual: true,
      );
      expect(result.translations.keys, ['m1']);
      expect(s.server.batchCalls.single.manual, isTrue);
      expect(s.reader.messageRequests, isEmpty);
    });

    test(
      'goes to the server when the model goes away before any answer',
      () async {
        final s = _Setup();
        s.reader.messages = [_text('a', 'Hello world')];
        s.backend.error = const OnDeviceAiUnavailableException(
          OnDeviceAiUnavailable.modelNotReady,
        );
        final result = await s.repository.translateBatch(
          conversationId: 'c1',
          messageIds: ['a'],
          target: AiLanguage.chinese,
        );
        expect(result.translations.keys, ['a']);
        expect(s.server.batchCalls, hasLength(1));
      },
    );
  });

  group('everything else is the server\'s', () {
    test('status, transcription and the translation choices', () async {
      final s = _Setup();
      expect((await s.repository.status()).dailyLimit, 50);
      expect(
        await s.repository.transcribe(messageId: 'v1'),
        'Server transcript.',
      );
      await s.repository.syncAiEnabled(enabled: false);
      expect(s.server.syncedEnabled, [false]);
      expect(s.backend.availabilityCalls, 0);
    });
  });
}
