import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_polish/quote_reply.dart';
import 'package:wecord/features/chats/chat_polish/voice_playback.dart';
import 'package:wecord/features/chats/chat_polish/voice_trim.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show pendingMessageIdFor;
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../transcribe/transcribe_fakes.dart';

Uint8List _wav(int ms, {int rate = 1000}) {
  final frames = ms * rate ~/ 1000;
  final data = Uint8List(frames * 2);
  final view = ByteData.sublistView(data);
  for (var i = 0; i < frames; i++) {
    view.setInt16(i * 2, i % 2 == 0 ? 16000 : -16000, Endian.little);
  }
  final out = Uint8List(44 + data.length);
  final header = ByteData.sublistView(out);
  void ascii(int at, String text) {
    for (var i = 0; i < text.length; i++) {
      out[at + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  out.setRange(44, out.length, data);
  return out;
}

ChatMessage _voice(
  String id, {
  String sender = 'user-2',
  bool recalled = false,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'c',
    senderId: sender,
    type: MessageType.voice,
    body: '',
    createdAt: DateTime.utc(2026, 10, 19),
    recalledAt: recalled ? DateTime.utc(2026, 10, 20) : null,
  );
}

ChatMessage _text(String id) => ChatMessage(
  id: id,
  conversationId: 'c',
  senderId: 'user-2',
  type: MessageType.text,
  body: 'hi',
  createdAt: DateTime.utc(2026, 10, 19),
);

void main() {
  group('trimming a WAV', () {
    test('cuts by time and keeps a valid header', () {
      final wav = _wav(2000);
      final cut = trimWav(wav, startMs: 500, endMs: 1500)!;

      final layout = WavLayout.parse(cut)!;
      expect(layout.sampleRate, 1000);
      expect(layout.channels, 1);
      expect(layout.bitsPerSample, 16);
      expect(layout.durationMs, 1000);
      expect(cut.length, 44 + 2000);
      expect(cut.sublist(44), wav.sublist(44 + 1000, 44 + 3000));
    });

    test('clamps to the recording and refuses an empty cut', () {
      final wav = _wav(1000);
      expect(
        WavLayout.parse(trimWav(wav, startMs: -50, endMs: 99999)!)!.durationMs,
        1000,
      );
      expect(trimWav(wav, startMs: 600, endMs: 600), isNull);
      expect(trimWav(wav, startMs: 900, endMs: 100), isNull);
      expect(trimWav(Uint8List(10), startMs: 0, endMs: 5), isNull);
    });

    test('works at the sample rate the recorder uses', () {
      final wav = _wav(3000, rate: 44100);
      final cut = trimWav(wav, startMs: 1000, endMs: 2000)!;
      expect(WavLayout.parse(cut)!.durationMs, 1000);
      expect(cut.length, 44 + 44100 * 2);
    });

    test('peaks follow the loudness', () {
      final quiet = Uint8List(44 + 1000 * 2);
      quiet.setRange(0, 44, _wav(1000).sublist(0, 44));
      final peaks = wavPeaks(_wav(1000), 10);
      expect(peaks, hasLength(10));
      expect(peaks.every((p) => p > 0.4 && p <= 1), isTrue);
      expect(wavPeaks(quiet, 10).every((p) => p == 0), isTrue);
      expect(wavPeaks(Uint8List(3), 4), [0, 0, 0, 0]);
    });

    test('the range knows when it keeps all', () {
      const range = VoiceTrimRange(startMs: 0, endMs: 4000);
      expect(range.keepsAll(4000), isTrue);
      expect(range.keepsAll(4100), isFalse);
      expect(
        const VoiceTrimRange(startMs: 10, endMs: 4000).keepsAll(4000),
        isFalse,
      );
      expect(voiceTrimTime(7500), '0:07.5');
      expect(voiceTrimTime(65000), '1:05.0');
    });
  });

  group('the trim sheet', () {
    testWidgets('moves the handles, keeps half a second between them', (
      tester,
    ) async {
      VoiceTrimRange? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showVoiceTrimSheet(context, wav: _wav(4000)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Keeps 0:04.0'), findsOneWidget);
      // Nothing to reset yet.
      final slider = find.byKey(const ValueKey('voice-trim-slider'));
      tester.widget<RangeSlider>(slider).onChanged!(
        const RangeValues(1000, 1100),
      );
      await tester.pump();
      expect(find.text('Keeps 0:00.5'), findsOneWidget);

      tester.widget<RangeSlider>(slider).onChanged!(
        const RangeValues(1000, 3000),
      );
      await tester.pump();
      expect(find.text('0:01.0'), findsOneWidget);
      expect(find.text('0:03.0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('voice-trim-reset')));
      await tester.pump();
      expect(find.text('Keeps 0:04.0'), findsOneWidget);

      tester.widget<RangeSlider>(slider).onChanged!(
        const RangeValues(500, 2500),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-trim-done')));
      await tester.pumpAndSettle();
      expect(result, const VoiceTrimRange(startMs: 500, endMs: 2500));
    });

    testWidgets('listens to the cut it will send', (tester) async {
      final previews = <Uint8List>[];
      final preview = _FakePreview(previews);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: VoiceTrimView(
              wav: _wav(4000),
              initial: const VoiceTrimRange(startMs: 1000, endMs: 3000),
              previewBuilder: () => preview,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('voice-trim-preview')));
      await tester.pump();
      expect(previews, hasLength(1));
      expect(WavLayout.parse(previews.single)!.durationMs, 2000);

      // Moving a handle stops it.
      tester
          .widget<RangeSlider>(find.byKey(const ValueKey('voice-trim-slider')))
          .onChanged!(const RangeValues(1000, 2500));
      await tester.pump();
      expect(preview.stops, greaterThan(0));
    });

    testWidgets('a recording too short to trim cannot be done', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(body: VoiceTrimView(wav: _wav(300))),
        ),
      );
      final done = find.byKey(const ValueKey('voice-trim-done'));
      await tester.tap(done);
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-trim-slider')), findsOneWidget);
    });
  });

  group('playing one voice message after another', () {
    test('the speed goes 1, 1.5, 2 and round', () {
      expect(nextVoiceSpeed(1), 1.5);
      expect(nextVoiceSpeed(1.5), 2);
      expect(nextVoiceSpeed(2), 1);
      expect(voiceSpeedLabel(1), '1×');
      expect(voiceSpeedLabel(1.5), '1.5×');
      expect(voiceSpeedLabel(2), '2×');
    });

    test(
      'the next one is the next voice message from someone else not heard',
      () {
        final messages = [
          _voice('a'),
          _text('t1'),
          _voice('mine', sender: 'me'),
          _voice('gone', recalled: true),
          _voice('b'),
          _voice('c'),
        ];
        String? next(String after, {Set<String> heard = const {}}) =>
            nextUnheardVoiceMessageId(
              messages,
              after,
              heard,
              currentUserId: 'me',
            );

        expect(next('a'), 'b');
        expect(next('a', heard: {'b'}), 'c');
        expect(next('a', heard: {'b', 'c'}), isNull);
        expect(next('c'), isNull);
        expect(next('missing'), isNull);
      },
    );

    test('a message still being sent is not next', () {
      final messages = [
        _voice('a'),
        _voice(pendingMessageIdFor('c1')),
        _voice('b'),
      ];
      expect(
        nextUnheardVoiceMessageId(messages, 'a', const {}, currentUserId: 'me'),
        'b',
      );
    });

    test('playing, pausing and finishing keep the books', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(voicePlaybackProvider.notifier);

      notifier.started('a');
      expect(container.read(voicePlaybackProvider).playingId, 'a');
      expect(container.read(voicePlaybackProvider).heard, {'a'});

      notifier.paused('a', const Duration(seconds: 3));
      expect(container.read(voicePlaybackProvider).playingId, isNull);
      expect(
        container.read(voicePlaybackProvider).positions['a'],
        const Duration(seconds: 3),
      );

      notifier.started('b');
      notifier.paused('a', const Duration(seconds: 4));
      // 'a' pausing does not stop 'b' from being the one playing.
      expect(container.read(voicePlaybackProvider).playingId, 'b');

      notifier.finished('a');
      expect(container.read(voicePlaybackProvider).positions, isEmpty);
      expect(container.read(voicePlaybackProvider).heard, {'a', 'b'});

      notifier.requestPlay('c');
      expect(container.read(voicePlaybackProvider).request?.messageId, 'c');
      notifier.started('c');
      expect(container.read(voicePlaybackProvider).request, isNull);
    });

    test('asking for the same message twice is two requests', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(voicePlaybackProvider.notifier);
      notifier.requestPlay('c');
      final first = container.read(voicePlaybackProvider).request!;
      notifier.requestPlay('c');
      final second = container.read(voicePlaybackProvider).request!;
      expect(second.serial, isNot(first.serial));
    });
  });

  group('the speed button', () {
    Widget app(ProviderContainer container) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VoiceMessagePlayer(attachment: testVoice),
            ),
          ),
        ),
      );
    }

    testWidgets('shows once the speed is not 1 and cycles it', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      expect(find.byKey(const ValueKey('voice-speed-chip')), findsNothing);

      container.read(voicePlaybackSpeedProvider.notifier).cycle();
      await tester.pump();
      expect(find.text('1.5×'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Playback speed 1.5×')),
        findsOneWidget,
      );
      handle.dispose();

      await tester.tap(find.byKey(const ValueKey('voice-speed-chip')));
      await tester.pump();
      expect(find.text('2×'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice-speed-chip')));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-speed-chip')), findsNothing);
      expect(container.read(voicePlaybackSpeedProvider), 1);
    });

    testWidgets('the wave shows where a paused message was left', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(app(container));
      container
          .read(voicePlaybackProvider.notifier)
          .paused(testVoice.path, const Duration(seconds: 2));
      await tester.pump();
      // The wave still draws (as a stream of the position) with no error.
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Play voice message'), findsOneWidget);
    });
  });

  group('quotes from a selection', () {
    test('trims spaces and keeps the offsets of what is left', () {
      final quote = quoteFromSelection('Hello  big world ', 5, 17)!;
      expect(quote.text, 'big world');
      expect(quote.start, 7);
      expect(quote.end, 16);
    });

    test('nothing, or only spaces, is no quote', () {
      expect(quoteFromSelection('abc', 1, 1), isNull);
      expect(quoteFromSelection('a   b', 1, 4), isNull);
      expect(quoteFromSelection('abc', -1, 2), isNull);
      expect(quoteFromSelection('abc', 0, 9), isNull);
    });

    test('a backwards selection is the same selection', () {
      final quote = quoteFromSelection('Hello world', 11, 6)!;
      expect(quote.text, 'world');
    });

    test('is cut at 500 characters, never in the middle of an emoji', () {
      final body = 'a${'😀' * 400}';
      final quote = quoteFromSelection(body, 0, body.length)!;
      // 500 units would end between the two halves of an emoji.
      expect(quote.text.length, 499);
      expect(quote.end, 499);
      expect(quote.text.runes.length, 250);
    });

    test('is found again by offsets, or by the words', () {
      const quote = ReplyQuote(text: 'world', start: 6, end: 11);
      expect(quote.locateIn('Hello world'), (6, 11));
      // The message changed (an edit): found by its words.
      expect(quote.locateIn('Hello big world'), (10, 15));
      expect(quote.locateIn('Hello there'), isNull);
    });

    test('is read from the server preview, and bad ones are ignored', () {
      final preview = ReplyPreview.fromJson({
        'message_id': 'm',
        'sender_name': 'Ada',
        'body': 'Hello world',
        'type': 'text',
        'quote': {'text': 'world', 'start': 6, 'end': 11},
      });
      expect(preview.quote?.text, 'world');
      expect(preview.toJson()['quote'], {
        'text': 'world',
        'start': 6,
        'end': 11,
      });

      for (final bad in [
        null,
        'x',
        3,
        {'text': ''},
        {'text': 4},
        <String, Object?>{},
      ]) {
        expect(ReplyQuote.maybeFromJson(bad), isNull, reason: '$bad');
      }
      final plain = ReplyPreview.fromJson({
        'message_id': 'm',
        'sender_name': 'Ada',
        'body': 'Hello',
        'type': 'text',
      });
      expect(plain.quote, isNull);
      expect(plain.toJson().containsKey('quote'), isFalse);
    });
  });
}

class _FakePreview implements VoiceTrimPreview {
  _FakePreview(this.played);

  final List<Uint8List> played;
  var stops = 0;
  final _playing = StreamController<bool>.broadcast();

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Future<void> play(Uint8List wav) async {
    played.add(wav);
    _playing.add(true);
  }

  @override
  Future<void> stop() async {
    stops++;
    _playing.add(false);
  }

  @override
  Future<void> dispose() async {
    await _playing.close();
  }
}
