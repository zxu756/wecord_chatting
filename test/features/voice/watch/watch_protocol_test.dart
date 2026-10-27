import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/features/voice/watch/watch_sync.dart';
import 'package:wecord/features/voice/watch/youtube_embed_protocol.dart';

import 'watch_fakes.dart';

WatchPacket? decode(List<int> data) =>
    decodeWatchPacket(data, conversationId: 'conv-lounge');

void main() {
  group('packets', () {
    test('a start packet round-trips with its source and playback', () {
      final packet =
          decode(
                encodeWatchStart(
                  WatchStartPacket(
                    sessionId: 'abcDEF123456',
                    source: sampleFile(),
                    title: 'Film night',
                    controlOpen: true,
                    position: const Duration(seconds: 73, milliseconds: 500),
                    playing: true,
                  ),
                ),
              )
              as WatchStartPacket;
      expect(packet.sessionId, 'abcDEF123456');
      expect(packet.source, sampleFile());
      expect(packet.title, 'Film night');
      expect(packet.controlOpen, isTrue);
      expect(packet.position, const Duration(seconds: 73, milliseconds: 500));
      expect(packet.playing, isTrue);
    });

    test('a start packet without a title falls back to the source', () {
      final packet =
          decode(
                encodeWatchStart(
                  WatchStartPacket(
                    sessionId: 'abcDEF123456',
                    source: WatchEmbedSource.tryCreate(
                      WatchEmbedProvider.youtube,
                      'dQw4w9WgXcQ',
                    )!,
                    title: ' ',
                    controlOpen: false,
                    position: Duration.zero,
                    playing: false,
                  ),
                ),
              )
              as WatchStartPacket;
      expect(packet.title, 'YouTube');
    });

    test('a state packet carries the host’s control switch only when sent', () {
      final withOpen =
          decode(
                encodeWatchState(
                  const WatchStatePacket(
                    sessionId: 'abcDEF123456',
                    position: Duration(seconds: 5),
                    playing: false,
                    controlOpen: true,
                  ),
                ),
              )
              as WatchStatePacket;
      expect(withOpen.controlOpen, isTrue);
      expect(withOpen.position, const Duration(seconds: 5));

      final without =
          decode(
                encodeWatchState(
                  const WatchStatePacket(
                    sessionId: 'abcDEF123456',
                    position: Duration.zero,
                    playing: true,
                  ),
                ),
              )
              as WatchStatePacket;
      expect(without.controlOpen, isNull);
      expect(without.playing, isTrue);
    });

    test('stop, request and cue round-trip', () {
      expect(
        (decode(encodeWatchStop('abcDEF123456')) as WatchStopPacket).sessionId,
        'abcDEF123456',
      );
      expect(decode(encodeWatchRequest()), isA<WatchRequestPacket>());
      final cue =
          decode(encodeWatchCue('abcDEF123456', WatchCueAction.pause))
              as WatchCuePacket;
      expect(cue.action, WatchCueAction.pause);
    });

    test('anything malformed is dropped', () {
      List<int> bytes(Object? json) => utf8.encode(jsonEncode(json));
      expect(decode(utf8.encode('not json')), isNull);
      expect(decode(bytes([1, 2])), isNull);
      expect(decode(bytes({'v': 2, 'k': 'req'})), isNull);
      expect(
        decode(bytes({'v': 1, 'k': 'nope', 'sid': 'abcDEF123456'})),
        isNull,
      );
      // A session id that is not a plain token.
      expect(decode(bytes({'v': 1, 'k': 'stop', 'sid': '../../x'})), isNull);
      expect(decode(bytes({'v': 1, 'k': 'stop'})), isNull);
      // Positions must be sane.
      expect(
        decode(
          bytes({
            'v': 1,
            'k': 'st',
            'sid': 'abcDEF123456',
            'p': -1,
            'pl': true,
          }),
        ),
        isNull,
      );
      expect(
        decode(
          bytes({
            'v': 1,
            'k': 'st',
            'sid': 'abcDEF123456',
            'p': 1e12,
            'pl': true,
          }),
        ),
        isNull,
      );
      expect(
        decode(
          bytes({
            'v': 1,
            'k': 'st',
            'sid': 'abcDEF123456',
            'p': 5,
            'pl': 'yes',
          }),
        ),
        isNull,
      );
      expect(
        decode(
          bytes({'v': 1, 'k': 'cue', 'sid': 'abcDEF123456', 'a': 'explode'}),
        ),
        isNull,
      );
      // Too big.
      expect(decode(List.filled(maxWatchPacketBytes + 1, 0x20)), isNull);
    });

    test('a start packet for a file outside the call’s chat is dropped', () {
      final packet = decodeWatchPacket(
        encodeWatchStart(
          WatchStartPacket(
            sessionId: 'abcDEF123456',
            source: sampleFile(),
            title: 'x',
            controlOpen: false,
            position: Duration.zero,
            playing: false,
          ),
        ),
        conversationId: 'conv-other',
      );
      expect(packet, isNull);
    });
  });

  test('a flood of packets from one person is limited', () {
    var now = DateTime(2026, 10, 28);
    final limits = WatchRateLimits(max: 3, now: () => now);
    expect(limits.allow('a'), isTrue);
    expect(limits.allow('a'), isTrue);
    expect(limits.allow('a'), isTrue);
    expect(limits.allow('a'), isFalse);
    expect(limits.allow('b'), isTrue);
    now = now.add(const Duration(seconds: 5));
    expect(limits.allow('a'), isTrue);
  });

  test('session ids are valid tokens', () {
    var n = 0;
    final id = newWatchSessionId((max) => n++ % max);
    expect(id, matches(RegExp(r'^[A-Za-z0-9]{12}$')));
  });

  group('sync math', () {
    final t0 = DateTime(2026, 10, 28, 20);

    test('a playing video moves on with the clock', () {
      expect(
        expectedWatchPosition(
          anchor: const Duration(seconds: 10),
          anchorAt: t0,
          now: t0.add(const Duration(seconds: 4)),
          playing: true,
        ),
        const Duration(seconds: 14),
      );
    });

    test('a paused video stays', () {
      expect(
        expectedWatchPosition(
          anchor: const Duration(seconds: 10),
          anchorAt: t0,
          now: t0.add(const Duration(seconds: 40)),
          playing: false,
        ),
        const Duration(seconds: 10),
      );
    });

    test('never past the end, never before the start', () {
      expect(
        expectedWatchPosition(
          anchor: const Duration(seconds: 58),
          anchorAt: t0,
          now: t0.add(const Duration(seconds: 10)),
          playing: true,
          duration: const Duration(minutes: 1),
        ),
        const Duration(minutes: 1),
      );
      // A clock that went backwards does not rewind the video.
      expect(
        expectedWatchPosition(
          anchor: const Duration(seconds: 10),
          anchorAt: t0,
          now: t0.subtract(const Duration(seconds: 3)),
          playing: true,
        ),
        const Duration(seconds: 10),
      );
    });

    test('more than a second of drift is corrected, less is forgiven', () {
      expect(
        watchCorrection(
          expected: const Duration(seconds: 30),
          actual: const Duration(milliseconds: 30900),
          playing: true,
        ),
        isNull,
      );
      expect(
        watchCorrection(
          expected: const Duration(seconds: 30),
          actual: const Duration(milliseconds: 28900),
          playing: true,
        ),
        const Duration(seconds: 30),
      );
      expect(
        watchCorrection(
          expected: const Duration(seconds: 30),
          actual: const Duration(seconds: 33),
          playing: true,
        ),
        const Duration(seconds: 30),
      );
    });

    test('a paused video must land on the spot', () {
      expect(
        watchCorrection(
          expected: const Duration(seconds: 30),
          actual: const Duration(milliseconds: 30200),
          playing: false,
        ),
        isNull,
      );
      expect(
        watchCorrection(
          expected: const Duration(seconds: 30),
          actual: const Duration(milliseconds: 30700),
          playing: false,
        ),
        const Duration(seconds: 30),
      );
    });

    test('a moved player gets time to settle', () {
      final gate = WatchSettleGate();
      expect(gate.isSettled(t0), isTrue);
      gate.moved(t0);
      expect(gate.isSettled(t0.add(const Duration(seconds: 1))), isFalse);
      expect(gate.isSettled(t0.add(const Duration(seconds: 4))), isTrue);
      gate.moved(t0);
      gate.clear();
      expect(gate.isSettled(t0), isTrue);
    });
  });

  group('YouTube’s player messages', () {
    test('commands are what its own script sends', () {
      expect(jsonDecode(youtubeCommandMessage('seekTo', [12.5, true])), {
        'event': 'command',
        'func': 'seekTo',
        'args': [12.5, true],
      });
      expect(jsonDecode(youtubeListeningMessage())['event'], 'listening');
    });

    test('time, length and state are read from deliveries', () {
      final info = parseYoutubeMessage(
        jsonEncode({
          'event': 'infoDelivery',
          'info': {'currentTime': 12.5, 'duration': 212, 'playerState': 1},
        }),
      )!;
      expect(info.currentTime, 12.5);
      expect(info.duration, 212);
      expect(info.playerState, YoutubeInfo.statePlaying);

      expect(
        parseYoutubeMessage(
          jsonEncode({'event': 'onStateChange', 'info': 2}),
        )!.playerState,
        YoutubeInfo.statePaused,
      );
      expect(
        parseYoutubeMessage(jsonEncode({'event': 'onReady'}))!.ready,
        isTrue,
      );
    });

    test('anything else is ignored', () {
      expect(parseYoutubeMessage(null), isNull);
      expect(parseYoutubeMessage(42), isNull);
      expect(parseYoutubeMessage('nope'), isNull);
      expect(parseYoutubeMessage(jsonEncode({'event': 'other'})), isNull);
      expect(
        parseYoutubeMessage(jsonEncode({'event': 'infoDelivery', 'info': {}})),
        isNull,
      );
      expect(parseYoutubeMessage('x' * 30000), isNull);
    });
  });
}
