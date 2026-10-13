import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../circles/circle_detail_screen_test.dart' as circle_fakes;
import 'chat_thread_screen_test.dart' as chat_fakes;

const _direct = SlashCommandContext();
const _circle = SlashCommandContext(isCircleConversation: true);

void main() {
  group('slashCommandQueryAt', () {
    test('reads the command name typed after a leading slash', () {
      expect(slashCommandQueryAt('/'), '');
      expect(slashCommandQueryAt('/Sh'), 'sh');
      expect(slashCommandQueryAt('/shrug '), isNull);
      expect(slashCommandQueryAt('hi /shrug'), isNull);
      expect(slashCommandQueryAt(' /shrug'), isNull);
      expect(slashCommandQueryAt('/sh1'), isNull);
    });
  });

  group('slashCommandCandidates', () {
    test('filters by prefix and hides unavailable commands', () {
      expect(
        slashCommandCandidates('', _direct).map((command) => command.name),
        ['shrug', 'tableflip', 'unflip', 'me', 'spoiler', 'roll', 'status'],
      );
      expect(
        slashCommandCandidates('', _circle).map((command) => command.name),
        contains('nick'),
      );
      expect(slashCommandCandidates('s', _direct), [
        SlashCommand.shrug,
        SlashCommand.spoiler,
        SlashCommand.status,
      ]);
      expect(slashCommandCandidates('nick', _direct), isEmpty);
      expect(slashCommandCandidates('poll', _circle), isEmpty);
      expect(
        slashCommandCandidates(
          'p',
          const SlashCommandContext(canCreatePolls: true),
        ),
        [SlashCommand.poll],
      );
    });
  });

  group('parseSlashCommand', () {
    SlashCommandAction? parse(
      String input, {
      SlashCommandContext context = _direct,
      math.Random? random,
    }) {
      return parseSlashCommand(input, context: context, random: random);
    }

    String sent(String input) {
      final action = parse(input);
      expect(action, isA<SlashSendText>(), reason: input);
      return (action! as SlashSendText).body;
    }

    test('leaves ordinary text and unknown commands alone', () {
      expect(parse('hello'), isNull);
      expect(parse('/unknown thing'), isNull);
      expect(parse('/ shrug'), isNull);
      expect(parse('/nick Ada'), isNull, reason: 'not in a circle');
      expect(parse('/poll'), isNull, reason: 'polls are not offered');
    });

    test('appends faces escaped so markdown shows them as written', () {
      expect(sent('/shrug'), r'¯\\\_(ツ)\_/¯');
      expect(sent('/shrug  oh well '), r'oh well ¯\\\_(ツ)\_/¯');
      expect(plainTextFromMarkdown(sent('/shrug')), shrugText);
      expect(plainTextFromMarkdown(sent('/shrug ok')), 'ok $shrugText');
      expect(sent('/tableflip'), tableflipText);
      expect(sent('/TABLEFLIP argh'), 'argh $tableflipText');
      expect(sent('/unflip'), r'┬─┬ノ( º \_ ºノ)');
      expect(plainTextFromMarkdown(sent('/unflip')), unflipText);
    });

    test('formats /me and /spoiler and needs their text', () {
      expect(sent('/me waves'), '*waves*');
      expect(sent('/spoiler the end'), '||the end||');
      expect(parse('/me'), isA<SlashCommandError>());
      expect(parse('/spoiler   '), isA<SlashCommandError>());
    });

    test('rolls between 1 and the number of sides', () {
      expect(
        (parse('/roll', random: math.Random(1))! as SlashSendText).body,
        matches(RegExp(r'^🎲 rolled [1-6] \(1–6\)$')),
      );
      for (var seed = 0; seed < 20; seed++) {
        final body =
            (parse('/roll 20', random: math.Random(seed))! as SlashSendText)
                .body;
        final rolled = int.parse(RegExp(r'rolled (\d+)').firstMatch(body)![1]!);
        expect(rolled, inInclusiveRange(1, 20));
        expect(body, endsWith('(1–20)'));
      }
      expect(sent('/roll 1000'), endsWith('(1–1000)'));
      for (final input in ['/roll 1', '/roll 1001', '/roll six', '/roll 2.5']) {
        expect(parse(input), isA<SlashCommandError>(), reason: input);
      }
    });

    test('/nick sets or resets the circle nickname', () {
      final set = parse('/nick  Captain Ada ', context: _circle);
      expect((set! as SlashSetNickname).nickname, 'Captain Ada');
      final reset = parse('/nick', context: _circle);
      expect((reset! as SlashSetNickname).nickname, isNull);
      expect(
        parse('/nick ${'x' * 33}', context: _circle),
        isA<SlashCommandError>(),
      );
    });

    test('/status reads an optional emoji, text, or clear', () {
      final both = parse('/status 🎯 Deep work')! as SlashSetStatus;
      expect(both.emoji, '🎯');
      expect(both.text, 'Deep work');
      final textOnly = parse('/status Deep work')! as SlashSetStatus;
      expect(textOnly.emoji, isNull);
      expect(textOnly.text, 'Deep work');
      final emojiOnly = parse('/status 👩‍💻')! as SlashSetStatus;
      expect(emojiOnly.emoji, '👩‍💻');
      expect(emojiOnly.text, isNull);
      expect((parse('/status clear')! as SlashSetStatus).clears, isTrue);
      expect(parse('/status'), isA<SlashCommandError>());
      expect(parse('/status ${'a' * 65}'), isA<SlashCommandError>());
    });
  });

  group('composer', () {
    testWidgets('typing a slash lists commands and filters them', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.enterText(_field, '/');
      await tester.pump();
      expect(find.byKey(const ValueKey('slash-command-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('slash-command-shrug')), findsOneWidget);
      expect(find.byKey(const ValueKey('slash-command-nick')), findsNothing);
      expect(find.byKey(const ValueKey('slash-command-poll')), findsNothing);

      await tester.enterText(_field, '/ta');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('slash-command-tableflip')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('slash-command-shrug')), findsNothing);

      await tester.enterText(_field, '/tableflip ');
      await tester.pump();
      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
    });

    testWidgets('tapping a command puts it in the composer', (tester) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.enterText(_field, '/sp');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('slash-command-spoiler')));
      await tester.pump();

      expect(_composerText(tester), '/spoiler ');
      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
    });

    testWidgets('arrow keys move through the list and Enter picks', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.showKeyboard(_field);
      await tester.enterText(_field, '/s');
      await tester.pump();
      ListTile tile(String name) =>
          tester.widget<ListTile>(find.byKey(ValueKey('slash-command-$name')));
      expect(tile('shrug').selected, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tile('shrug').selected, isFalse);
      expect(tile('spoiler').selected, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(tile('status').selected, isTrue, reason: 'wraps around');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_composerText(tester), '/status ');
      expect(world.chats.sentMessages, isEmpty);

      await tester.enterText(_field, '/tab');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_composerText(tester), '/tableflip ');
    });

    final sends = {
      '/shrug': r'¯\\\_(ツ)\_/¯',
      '/tableflip so done': 'so done $tableflipText',
      '/unflip': r'┬─┬ノ( º \_ ºノ)',
      '/me is here': '*is here*',
      '/spoiler snape': '||snape||',
      '/roll 20': '🎲 rolled 3 (1–20)',
    };
    for (final MapEntry(key: input, value: body) in sends.entries) {
      testWidgets('$input sends a text message', (tester) async {
        final world = _World();
        await tester.pumpWidget(world.app());
        await tester.pump();

        await _send(tester, input);

        expect(world.chats.sentMessages.map((message) => message.body), [body]);
        expect(_composerText(tester), isEmpty);
      });
    }

    testWidgets('a misused command shows why and sends nothing', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await _send(tester, '/roll 1');

      expect(world.chats.sentMessages, isEmpty);
      expect(find.text('Choose between 2 and 1000 sides.'), findsOneWidget);
      expect(_composerText(tester), '/roll 1');
    });

    testWidgets('/nick changes the circle nickname in channels', (
      tester,
    ) async {
      final world = _World(inCircle: true);
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.enterText(_field, '/n');
      await tester.pump();
      expect(find.byKey(const ValueKey('slash-command-nick')), findsOneWidget);

      await _send(tester, '/nick Countess');
      expect(world.circles.nicknameUpdates, [
        (userId: 'user-1', nickname: 'Countess'),
      ]);
      expect(find.text('Your nickname is now Countess.'), findsOneWidget);
      expect(world.chats.sentMessages, isEmpty);
      expect(_composerText(tester), isEmpty);

      ScaffoldMessenger.of(
        tester.element(find.byType(ChatThreadScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await _send(tester, '/nick');
      expect(world.circles.nicknameUpdates.last, (
        userId: 'user-1',
        nickname: null,
      ));
      expect(find.text('Your nickname was reset.'), findsOneWidget);
    });

    testWidgets('/nick is plain text outside circles', (tester) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await _send(tester, '/nick Countess');

      expect(world.circles.nicknameUpdates, isEmpty);
      expect(world.chats.sentMessages.single.body, '/nick Countess');
    });

    testWidgets('/status sets and clears the custom status', (tester) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pump();

      await _send(tester, '/status 🎯 Deep work');
      expect(world.settings.statuses, [
        (emoji: '🎯', text: 'Deep work', expiresAt: null),
      ]);
      expect(find.text('Status set to 🎯 Deep work.'), findsOneWidget);

      await _send(tester, '/status clear');
      expect(world.settings.statuses.last, (
        emoji: null,
        text: null,
        expiresAt: null,
      ));
      expect(world.chats.sentMessages, isEmpty);
    });

    testWidgets('editing a message offers no commands', (tester) async {
      final world = _World();
      world.chats.messages = [
        ChatMessage(
          id: 'message-1',
          conversationId: 'conversation-1',
          senderId: 'user-1',
          type: MessageType.text,
          body: 'Typo',
          createdAt: DateTime.utc(2026, 10, 13, 9),
        ),
      ];
      await tester.pumpWidget(world.app());
      await tester.pump();

      await tester.longPress(find.text('Typo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(_field, '/shrug');
      await tester.pump();

      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
      await tester.tap(find.byTooltip('Save edit'));
      await tester.pump();
      expect(world.chats.editedBody, '/shrug');
      expect(world.chats.sentMessages, isEmpty);
    });
  });
}

final _field = find.byKey(const ValueKey('chat-composer-field'));

String _composerText(WidgetTester tester) {
  return tester.widget<TextField>(_field).controller!.text;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
  await tester.pump();
}

class _RecordingSettingsRepository extends chat_fakes.FakeSettingsRepository {
  final statuses = <({String? emoji, String? text, DateTime? expiresAt})>[];

  @override
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  }) async {
    statuses.add((emoji: emoji, text: text, expiresAt: expiresAt));
  }
}

/// Always rolls 3 on a 20-sided die (and 3 or less otherwise).
class _FixedRandom implements math.Random {
  @override
  int nextInt(int max) => math.min(2, max - 1);

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

class _World {
  _World({bool inCircle = false}) {
    chats.conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: inCircle ? ConversationType.channel : ConversationType.direct,
        unreadCount: 0,
        title: inCircle ? 'general' : 'Ada Lovelace',
        circleId: inCircle ? 'circle-1' : null,
      ),
    ];
  }

  final chats = chat_fakes.FakeChatsRepository();
  final circles = circle_fakes.FakeCirclesRepository();
  final settings = _RecordingSettingsRepository();

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        circlesRepositoryProvider.overrideWithValue(circles),
        settingsRepositoryProvider.overrideWithValue(settings),
        slashCommandRandomProvider.overrideWithValue(_FixedRandom()),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        authRepositoryProvider.overrideWithValue(
          chat_fakes.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: const MaterialApp(
        home: ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}
