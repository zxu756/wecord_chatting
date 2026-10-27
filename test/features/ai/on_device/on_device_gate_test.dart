import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/on_device/on_device_gate.dart';

AppOnDeviceAiGate _gate({
  bool enabled = true,
  Set<String> locked = const {},
  Map<String, bool> allowed = const {},
  Map<String, String> parents = const {},
  bool offline = false,
  List<String>? asked,
}) {
  return AppOnDeviceAiGate(
    aiEnabled: () => enabled,
    lockedChatIds: () => locked,
    conversationAllowed: (id) async {
      asked?.add(id);
      if (offline) {
        throw Exception('offline');
      }
      return allowed[id] ?? true;
    },
    threadParent: (id) async {
      if (offline) {
        throw Exception('offline');
      }
      return parents[id];
    },
  );
}

void main() {
  test('lets an ordinary chat through', () async {
    await _gate().check(conversationId: 'c1');
  });

  test('lets text that belongs to no chat through, with AI on', () async {
    final asked = <String>[];
    await _gate(asked: asked).check();
    expect(asked, isEmpty);
  });

  test('stops everything when the person turned AI off', () async {
    await expectLater(
      _gate(enabled: false).check(),
      throwsA(isA<AiTurnedOffException>()),
    );
    await expectLater(
      _gate(enabled: false).check(conversationId: 'c1'),
      throwsA(isA<AiTurnedOffException>()),
    );
  });

  test('stops a locked chat (G2)', () async {
    await expectLater(
      _gate(locked: {'c1'}).check(conversationId: 'c1'),
      throwsA(isA<AiChatLockedException>()),
    );
  });

  test('stops a thread of a locked chat (G2)', () async {
    await expectLater(
      _gate(
        locked: {'parent'},
        parents: {'thread': 'parent'},
      ).check(conversationId: 'thread'),
      throwsA(isA<AiChatLockedException>()),
    );
  });

  test('a thread of a chat that is not locked is fine', () async {
    await _gate(
      locked: {'other'},
      parents: {'thread': 'parent'},
    ).check(conversationId: 'thread');
  });

  test(
    'stops a chat the database keeps AI out of (circle, group, G6)',
    () async {
      await expectLater(
        _gate(allowed: {'c1': false}).check(conversationId: 'c1'),
        throwsA(isA<AiDisabledInCircleException>()),
      );
    },
  );

  test('a rule that cannot be checked counts as no', () async {
    await expectLater(
      _gate(offline: true).check(conversationId: 'c1'),
      throwsA(isA<AiFailedException>()),
    );
    await expectLater(
      _gate(offline: true, locked: {'x'}).check(conversationId: 'c1'),
      throwsA(isA<AiFailedException>()),
    );
  });
}
