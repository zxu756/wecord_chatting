import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_polish/chat_polish_settings.dart';
import 'package:wecord/features/chats/chat_polish/message_effects.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show pendingMessageIdFor;
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

final _now = DateTime.utc(2026, 10, 19, 12);

ChatMessage _message(
  String id,
  String body, {
  Duration age = const Duration(seconds: 2),
  MessageType type = MessageType.text,
  String? clientId,
  DateTime? recalledAt,
  MessageReviewState? reviewState,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'c',
    senderId: 'user-2',
    type: type,
    body: body,
    createdAt: _now.subtract(age),
    clientId: clientId,
    recalledAt: recalledAt,
    reviewState: reviewState,
  );
}

class _World {
  _World({Map<String, bool>? values}) : store = InMemoryChatPolishStore(values);

  final InMemoryChatPolishStore store;

  Widget app(List<ChatMessage> messages, {bool reduceMotion = false}) {
    return ProviderScope(
      overrides: [chatPolishStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              MessageEffectsOverlay(messages: messages, now: () => _now),
            ],
          ),
        ),
      ),
    );
  }
}

Finder _effect(String id) => find.byKey(ValueKey('message-effect-$id'));

Future<void> _settle(WidgetTester tester) async {
  // The stored list loads, then the overlay looks at the messages.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('which words call an effect', () {
    test('Chinese and English wishes, whatever the case', () {
      expect(effectForText('生日快乐！')?.id, 'birthday');
      expect(effectForText('Happy Birthday Ada')?.id, 'birthday');
      expect(effectForText('新年快乐')?.id, 'new-year');
      expect(effectForText('CONGRATULATIONS!')?.id, 'congrats');
      expect(effectForText('恭喜你')?.id, 'congrats');
      expect(effectForText('想你了')?.id, 'miss-you');
      expect(effectForText('cheers everyone')?.id, 'cheers');
      expect(effectForText('晚安')?.id, 'good-night');
    });

    test('other words, and very long text, call nothing', () {
      expect(effectForText('see you at noon'), isNull);
      expect(effectForText(''), isNull);
      expect(effectForText('生日快乐${'x' * 2500}'), isNull);
    });

    test('only stored, visible text messages play', () {
      expect(effectForMessage(_message('m', '生日快乐')), isNotNull);
      expect(
        effectForMessage(_message(pendingMessageIdFor('c1'), '生日快乐')),
        isNull,
      );
      expect(
        effectForMessage(_message('m', '生日快乐', type: MessageType.image)),
        isNull,
      );
      expect(effectForMessage(_message('m', '生日快乐', recalledAt: _now)), isNull);
    });

    test('every effect has words and emoji', () {
      for (final effect in messageEffects) {
        expect(effect.keywords, isNotEmpty, reason: effect.id);
        expect(effect.emoji, isNotEmpty, reason: effect.id);
        for (final keyword in effect.keywords) {
          expect(keyword, keyword.toLowerCase(), reason: effect.id);
        }
      }
      expect({
        for (final effect in messageEffects) effect.id,
      }, hasLength(messageEffects.length));
    });

    test('the same message always rains the same way, and not too much', () {
      final effect = messageEffects.first;
      final one = effectParticles(effect, 42);
      final two = effectParticles(effect, 42);
      expect(one.length, two.length);
      expect([for (final p in one) p.lane], [for (final p in two) p.lane]);
      expect(
        effectParticles(effect, 1, count: 500),
        hasLength(maxEffectParticles),
      );
      for (final particle in one) {
        expect(
          particle.emojiIndex,
          inInclusiveRange(0, effect.emoji.length - 1),
        );
        expect(particle.lane, inInclusiveRange(0, 1));
        expect(particle.delay, lessThan(0.5));
      }
    });
  });

  group('the overlay', () {
    testWidgets('plays once for a new message and remembers it', (
      tester,
    ) async {
      final world = _World();
      final messages = [_message('m1', '生日快乐 Ada')];
      await tester.pumpWidget(world.app(messages));
      await _settle(tester);

      expect(_effect('birthday'), findsOneWidget);
      expect(world.store.played, ['m1']);

      // It ends by itself.
      await tester.pump(
        messageEffectDuration + const Duration(milliseconds: 100),
      );
      expect(_effect('birthday'), findsNothing);

      // The same message again (the list rebuilt) does not play again.
      await tester.pumpWidget(world.app([...messages]));
      await _settle(tester);
      expect(_effect('birthday'), findsNothing);
    });

    testWidgets('a message already played on this device stays quiet', (
      tester,
    ) async {
      final world = _World()..store.played = ['m1'];
      await tester.pumpWidget(world.app([_message('m1', '生日快乐')]));
      await _settle(tester);
      expect(_effect('birthday'), findsNothing);
    });

    testWidgets('the sent copy and the stored copy are one message', (
      tester,
    ) async {
      final world = _World()..store.played = ['client-1'];
      await tester.pumpWidget(
        world.app([_message('server-id', '生日快乐', clientId: 'client-1')]),
      );
      await _settle(tester);
      expect(_effect('birthday'), findsNothing);
    });

    testWidgets('history does not play', (tester) async {
      final world = _World();
      await tester.pumpWidget(
        world.app([_message('old', '生日快乐', age: const Duration(minutes: 5))]),
      );
      await _settle(tester);
      expect(_effect('birthday'), findsNothing);
      expect(world.store.played, isEmpty);
    });

    testWidgets('plays for a message that arrives while the chat is open', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(world.app([_message('m0', 'hello')]));
      await _settle(tester);
      expect(_effect('birthday'), findsNothing);

      await tester.pumpWidget(
        world.app([_message('m0', 'hello'), _message('m1', '恭喜！')]),
      );
      await _settle(tester);
      expect(_effect('congrats'), findsOneWidget);
    });

    testWidgets('one effect at a time, the next after it', (tester) async {
      final world = _World();
      await tester.pumpWidget(
        world.app([_message('m1', '生日快乐'), _message('m2', '新年快乐')]),
      );
      await _settle(tester);
      // The newest first.
      expect(_effect('new-year'), findsOneWidget);
      expect(_effect('birthday'), findsNothing);

      await tester.pump(
        messageEffectDuration + const Duration(milliseconds: 100),
      );
      await _settle(tester);
      expect(_effect('birthday'), findsOneWidget);
      expect(world.store.played, ['m2', 'm1']);
    });

    testWidgets('does not play under reduced motion, or tell anyone', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(
        world.app([_message('m1', '生日快乐')], reduceMotion: true),
      );
      await _settle(tester);
      expect(_effect('birthday'), findsNothing);
      // Not remembered either: it was never shown.
      expect(world.store.played, isEmpty);
    });

    testWidgets('is off when the switch is off', (tester) async {
      final world = _World(values: {keywordEffectsKey: false});
      await tester.pumpWidget(world.app([_message('m1', '生日快乐')]));
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_effect('birthday'), findsNothing);
    });

    testWidgets('takes no taps and says nothing to screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final world = _World();
      await tester.pumpWidget(world.app([_message('m1', '生日快乐')]));
      await _settle(tester);
      expect(_effect('birthday'), findsOneWidget);

      final ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: _effect('birthday'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);
      expect(
        find.ancestor(
          of: _effect('birthday'),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('remembers only the last 200', (tester) async {
      final world = _World()
        ..store.played = [for (var i = 0; i < 200; i++) 'old-$i'];
      await tester.pumpWidget(world.app([_message('m1', '生日快乐')]));
      await _settle(tester);
      expect(world.store.played, hasLength(playedEffectsLimit));
      expect(world.store.played.last, 'm1');
      expect(world.store.played.first, 'old-1');
    });
  });
}
