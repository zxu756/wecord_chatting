import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/reactions/reaction_message.dart';

void main() {
  group('reaction messages', () {
    test('every offered emoji survives the round trip', () {
      for (final emoji in callReactionEmojis) {
        expect(decodeReaction(encodeReaction(emoji)), emoji);
      }
    });

    test('anything else is dropped', () {
      expect(decodeReaction(utf8.encode('hello')), isNull);
      expect(decodeReaction(utf8.encode('{"v":2,"e":"👍"}')), isNull);
      expect(decodeReaction(utf8.encode('{"v":1,"e":"💩"}')), isNull);
      expect(decodeReaction(utf8.encode('{"v":1,"e":"<script>"}')), isNull);
      expect(decodeReaction(utf8.encode('{"v":1,"e":3}')), isNull);
      expect(decodeReaction(utf8.encode('[1,2]')), isNull);
      expect(decodeReaction(const [0xff, 0xfe]), isNull);
      expect(decodeReaction(List.filled(500, 0x41)), isNull);
    });
  });

  group('rate limits', () {
    test('five reactions in three seconds, then wait', () {
      var now = DateTime.utc(2026, 10, 17, 9);
      final limiter = ReactionRateLimiter(now: () => now);
      for (var i = 0; i < 5; i++) {
        expect(limiter.allow(), isTrue, reason: 'reaction $i');
        now = now.add(const Duration(milliseconds: 100));
      }
      expect(limiter.allow(), isFalse);
      // Held back ones are not counted: room frees up as the first ones
      // (at 0 and 100 ms) leave the three second window.
      now = now.add(const Duration(milliseconds: 2600));
      expect(limiter.allow(), isTrue);
      expect(limiter.allow(), isTrue);
      expect(limiter.allow(), isFalse);
    });

    test('each sender has their own allowance', () {
      var now = DateTime.utc(2026, 10, 17, 9);
      final limits = ReactionRateLimits(max: 2, now: () => now);
      expect(limits.allow('ada'), isTrue);
      expect(limits.allow('ada'), isTrue);
      expect(limits.allow('ada'), isFalse);
      expect(limits.allow('bob'), isTrue);
      now = now.add(const Duration(seconds: 4));
      expect(limits.allow('ada'), isTrue);
    });
  });

  group('what a room delivers', () {
    test('a reaction from a person on the reaction topic', () {
      final receiver = ReactionReceiver();
      expect(
        receiver.receive(
          senderId: 'user-2',
          topic: reactionTopic,
          data: encodeReaction('🎉'),
        ),
        const VoiceReaction(userId: 'user-2', emoji: '🎉'),
      );
    });

    test('other topics, the server and unknown emoji are dropped', () {
      final receiver = ReactionReceiver();
      final data = encodeReaction('👍');
      expect(
        receiver.receive(senderId: 'user-2', topic: 'chat', data: data),
        isNull,
      );
      expect(
        receiver.receive(senderId: 'user-2', topic: null, data: data),
        isNull,
      );
      expect(
        receiver.receive(senderId: null, topic: reactionTopic, data: data),
        isNull,
      );
      expect(
        receiver.receive(
          senderId: 'user-2',
          topic: reactionTopic,
          data: utf8.encode('{"v":1,"e":"evil"}'),
        ),
        isNull,
      );
    });

    test('someone flooding is cut off, others are not', () {
      var now = DateTime.utc(2026, 10, 17, 9);
      final receiver = ReactionReceiver(now: () => now);
      final data = encodeReaction('😂');
      var delivered = 0;
      for (var i = 0; i < 20; i++) {
        if (receiver.receive(
              senderId: 'spammer',
              topic: reactionTopic,
              data: data,
            ) !=
            null) {
          delivered++;
        }
      }
      expect(delivered, 8);
      expect(
        receiver.receive(senderId: 'friend', topic: reactionTopic, data: data),
        isNotNull,
      );
      now = now.add(const Duration(seconds: 4));
      expect(
        receiver.receive(senderId: 'spammer', topic: reactionTopic, data: data),
        isNotNull,
      );
    });
  });
}
