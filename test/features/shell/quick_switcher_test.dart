import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/shell/keyboard_shortcuts.dart';
import 'package:wecord/features/shell/quick_switcher.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

const _ada = ConversationSummary(
  id: 'dm-ada',
  type: ConversationType.direct,
  unreadCount: 0,
  title: 'Ada Lovelace',
);
const _team = ConversationSummary(
  id: 'group-team',
  type: ConversationType.group,
  unreadCount: 2,
  title: 'Launch team',
);
const _general = ConversationSummary(
  id: 'channel-general',
  type: ConversationType.channel,
  unreadCount: 0,
  title: 'general',
  circleId: 'circle-1',
);
const _thread = ConversationSummary(
  id: 'thread-1',
  type: ConversationType.thread,
  unreadCount: 0,
  title: 'A thread',
  circleId: 'circle-1',
  parentConversationId: 'channel-general',
);
const _circle = CircleSummary(
  id: 'circle-1',
  name: 'Garden Club',
  memberCount: 3,
  channelCount: 1,
);

void main() {
  group('quickSwitchScore', () {
    test('ranks exact, prefix, word, anywhere, then letters in order', () {
      final exact = quickSwitchScore('general', 'general')!;
      final prefix = quickSwitchScore('gen', 'general')!;
      final word = quickSwitchScore('love', 'Ada Lovelace')!;
      final inside = quickSwitchScore('vel', 'Ada Lovelace')!;
      final letters = quickSwitchScore('gnrl', 'general')!;
      expect(exact, greaterThan(prefix));
      expect(prefix, greaterThan(word));
      expect(word, greaterThan(inside));
      expect(inside, greaterThan(letters));
      expect(quickSwitchScore('xyz', 'general'), isNull);
    });
  });

  group('searchQuickSwitchItems', () {
    final items = quickSwitchItems(
      conversations: const [_ada, _team, _general, _thread],
      circles: const [_circle],
    );

    test('lists conversations, channels and circles but not threads', () {
      expect(
        [for (final item in items) item.kind],
        [
          QuickSwitchKind.direct,
          QuickSwitchKind.group,
          QuickSwitchKind.channel,
          QuickSwitchKind.circle,
        ],
      );
      expect(items[2].subtitle, 'Garden Club');
    });

    test('prefixes narrow the kind', () {
      expect(
        searchQuickSwitchItems(items, '#').map((item) => item.id),
        ['channel-general'],
      );
      expect(
        searchQuickSwitchItems(items, '*gard').map((item) => item.id),
        ['circle-1'],
      );
      expect(
        searchQuickSwitchItems(items, '@').map((item) => item.id).toSet(),
        {'dm-ada', 'group-team'},
      );
    });

    test('best matches first; circle names find their channels', () {
      expect(searchQuickSwitchItems(items, 'gen').first.id, 'channel-general');
      expect(
        searchQuickSwitchItems(items, 'garden').map((item) => item.id),
        ['circle-1', 'channel-general'],
      );
    });
  });

  group('appShortcutFor', () {
    const down = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyK,
      logicalKey: LogicalKeyboardKey.keyK,
      timeStamp: Duration.zero,
    );
    test('Ctrl or Cmd+K, Ctrl+/ and Alt+arrows', () {
      AppShortcut? shortcut(
        LogicalKeyboardKey key, {
        bool control = false,
        bool meta = false,
        bool alt = false,
      }) {
        return appShortcutFor(
          KeyDownEvent(
            physicalKey: down.physicalKey,
            logicalKey: key,
            timeStamp: Duration.zero,
          ),
          control: control,
          meta: meta,
          alt: alt,
          shift: false,
        );
      }

      expect(
        shortcut(LogicalKeyboardKey.keyK, control: true),
        AppShortcut.quickSwitcher,
      );
      expect(
        shortcut(LogicalKeyboardKey.keyK, meta: true),
        AppShortcut.quickSwitcher,
      );
      expect(shortcut(LogicalKeyboardKey.keyK), isNull);
      expect(
        shortcut(LogicalKeyboardKey.slash, control: true),
        AppShortcut.shortcutsHelp,
      );
      expect(
        shortcut(LogicalKeyboardKey.arrowUp, alt: true),
        AppShortcut.previous,
      );
      expect(
        shortcut(LogicalKeyboardKey.arrowDown, alt: true),
        AppShortcut.next,
      );
      expect(shortcut(LogicalKeyboardKey.arrowDown), isNull);
    });
  });

  group('adjacentConversations', () {
    test('steps through direct messages, from a thread its channel', () {
      final result = adjacentConversations(
        activeId: 'group-team',
        conversations: const [_ada, _team, _general],
      );
      expect(result.list.map((item) => item.id), ['dm-ada', 'group-team']);
      expect(result.index, 1);

      const circle = CircleDetail(
        circle: _circle,
        members: [],
        posts: [],
        channels: [
          CircleChannel(
            id: 'ch-1',
            circleId: 'circle-1',
            conversationId: 'channel-general',
            name: 'general',
            position: 0,
          ),
          CircleChannel(
            id: 'ch-2',
            circleId: 'circle-1',
            conversationId: 'channel-voice',
            name: 'Voice',
            position: 1,
            kind: CircleChannelKind.voice,
          ),
          CircleChannel(
            id: 'ch-3',
            circleId: 'circle-1',
            conversationId: 'channel-ideas',
            name: 'ideas',
            position: 2,
          ),
        ],
      );
      final inCircle = adjacentConversations(
        activeId: 'thread-1',
        conversations: const [_general, _thread],
        circle: circle,
      );
      expect(inCircle.list.map((item) => item.id), [
        'channel-general',
        'channel-ideas',
      ]);
      expect(inCircle.index, 0);
    });
  });

  testWidgets('arrow keys and Enter pick from the quick switcher', (
    tester,
  ) async {
    QuickSwitchItem? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationsProvider.overrideWith((ref) async => [_ada, _general]),
          circleSummariesProvider.overrideWith((ref) async => [_circle]),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showDialog<QuickSwitchItem>(
                  context: context,
                  builder: (context) => const QuickSwitcherDialog(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('quick-switcher-field')),
      'a',
    );
    await tester.pump();
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Garden Club'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(
      picked!.id,
      searchQuickSwitchItems(
        quickSwitchItems(
          conversations: const [_ada, _general],
          circles: const [_circle],
        ),
        'a',
      )[1].id,
    );
  });
}
