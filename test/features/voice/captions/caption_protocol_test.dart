import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';

void main() {
  final at = DateTime.fromMillisecondsSinceEpoch(1760000000000);

  test('a line survives the trip, speaker and time included', () {
    final packet = decodeCaptionPacket(
      encodeCaptionLine(id: 7, text: ' Hello  there ', at: at, isFinal: true),
    );
    expect(packet, isA<CaptionLinePacket>());
    final line = packet! as CaptionLinePacket;
    expect(line.id, 7);
    expect(line.text, 'Hello there');
    expect(line.at, at);
    expect(line.isFinal, isTrue);
    final partial =
        decodeCaptionPacket(
              encodeCaptionLine(id: 8, text: '你好', at: at, isFinal: false),
            )!
            as CaptionLinePacket;
    expect(partial.isFinal, isFalse);
    expect(partial.text, '你好');
  });

  test('control and support messages', () {
    expect(
      (decodeCaptionPacket(encodeCaptionControl(on: true))! as CaptionControl)
          .on,
      isTrue,
    );
    expect(
      (decodeCaptionPacket(encodeCaptionControl(on: false))! as CaptionControl)
          .on,
      isFalse,
    );
    expect(
      (decodeCaptionPacket(encodeCaptionSupport(supported: false))!
              as CaptionSupportPacket)
          .supported,
      isFalse,
    );
    expect(
      (decodeCaptionPacket(encodeCaptionSupport(supported: true))!
              as CaptionSupportPacket)
          .supported,
      isTrue,
    );
  });

  test('a sender can not send more than a line holds', () {
    final packet =
        decodeCaptionPacket(
              encodeCaptionLine(
                id: 1,
                text: 'x' * (maxCaptionChars + 50),
                at: at,
                isFinal: true,
              ),
            )!
            as CaptionLinePacket;
    expect(packet.text.runes.length, maxCaptionChars);
    // A receiver drops a line that is too long to start with.
    final big = utf8.encode(
      jsonEncode({
        'v': 1,
        'k': 'f',
        'i': 1,
        't': 'y' * (maxCaptionChars + 1),
        'ts': at.millisecondsSinceEpoch,
      }),
    );
    expect(decodeCaptionPacket(big), isNull);
  });

  test('anything that is not a caption is dropped', () {
    List<int> raw(Object? value) => utf8.encode(jsonEncode(value));
    expect(decodeCaptionPacket(utf8.encode('not json')), isNull);
    expect(decodeCaptionPacket(raw([1, 2])), isNull);
    expect(decodeCaptionPacket(raw({'v': 2, 'k': 'on'})), isNull);
    expect(decodeCaptionPacket(raw({'v': 1, 'k': 'boom'})), isNull);
    expect(decodeCaptionPacket(raw({'v': 1, 'k': 'f', 'i': 'x'})), isNull);
    expect(
      decodeCaptionPacket(raw({'v': 1, 'k': 'f', 'i': -1, 't': 'a', 'ts': 1})),
      isNull,
    );
    expect(
      decodeCaptionPacket(raw({'v': 1, 'k': 'f', 'i': 1, 't': '  ', 'ts': 1})),
      isNull,
    );
    expect(decodeCaptionPacket(List.filled(5000, 65)), isNull);
  });

  test('control characters and direction marks are removed', () {
    final packet =
        decodeCaptionPacket(
              encodeCaptionLine(
                id: 1,
                text: 'a\u202Eb\u0007c​d',
                at: at,
                isFinal: true,
              ),
            )!
            as CaptionLinePacket;
    expect(packet.text, 'abcd');
  });

  test('one person can not flood the call', () {
    var now = DateTime(2026, 10, 19, 12);
    final limits = CaptionRateLimits(max: 3, now: () => now);
    expect(
      [for (var i = 0; i < 5; i++) limits.allow('a')],
      [true, true, true, false, false],
    );
    expect(limits.allow('b'), isTrue);
    now = now.add(const Duration(seconds: 5));
    expect(limits.allow('a'), isTrue);
  });

  test('a line is timed by when it arrived, within reason', () {
    final received = DateTime(2026, 10, 19, 12, 0, 30);
    expect(
      clampCaptionTime(DateTime(2026, 10, 19, 12, 0, 28), received),
      DateTime(2026, 10, 19, 12, 0, 28),
    );
    expect(clampCaptionTime(DateTime(2030), received), received);
    expect(
      clampCaptionTime(DateTime(2020), received),
      received.subtract(const Duration(seconds: 30)),
    );
  });
}
