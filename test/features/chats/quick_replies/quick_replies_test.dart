import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/quick_replies/away_reply_sheet.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_models.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_repository.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_screen.dart';
import 'package:wecord/features/chats/quick_replies/quick_reply_picker.dart';
import 'package:wecord/features/chats/slash_commands.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../circles/circle_detail_screen_test.dart' as circle_fakes;
import '../chat_thread_screen_test.dart' as chat_fakes;
import 'quick_replies_fakes.dart';

const _addr = QuickReply(id: 'r1', shortcut: 'addr', body: '12 Main Street');
const _pay = QuickReply(
  id: 'r2',
  shortcut: 'pay',
  body: 'Bank 12-3456\nPlease add your name.',
);
const _shrug = QuickReply(id: 'r3', shortcut: 'shrug', body: 'No idea');

void main() {
  group('the rules', () {
    test('a shortcut is trimmed, lower-cased and loses its slash', () {
      expect(normalizeQuickReplyShortcut(' /Addr '), 'addr');
      expect(normalizeQuickReplyShortcut('地址'), '地址');
    });

    test('checkQuickReply names the first thing wrong', () {
      expect(checkQuickReply('addr', 'x'), isNull);
      expect(checkQuickReply('', 'x'), QuickReplyProblem.shortcut);
      expect(checkQuickReply('two words', 'x'), QuickReplyProblem.shortcut);
      expect(checkQuickReply('a/b', 'x'), QuickReplyProblem.shortcut);
      expect(checkQuickReply('x' * 33, 'x'), QuickReplyProblem.shortcut);
      expect(checkQuickReply('x' * 32, 'x'), isNull);
      expect(checkQuickReply('ok', '   '), QuickReplyProblem.body);
      expect(checkQuickReply('ok', 'y' * 2001), QuickReplyProblem.body);
      expect(checkQuickReply('ok', 'y' * 2000), isNull);
    });

    test('slashQueryAt reads what is typed after a leading slash', () {
      expect(slashQueryAt('/'), '');
      expect(slashQueryAt('/Ad'), 'ad');
      expect(slashQueryAt('/地址'), '地址');
      expect(slashQueryAt('/a-1_b'), 'a-1_b');
      expect(slashQueryAt('/addr '), isNull);
      expect(slashQueryAt('hi /addr'), isNull);
      expect(slashQueryAt('/a/b'), isNull);
      // The command-name reader is not widened.
      expect(slashCommandQueryAt('/sh1'), isNull);
    });

    test('candidates start with what is typed, in the order kept', () {
      const all = [_addr, _pay, _shrug];
      expect(quickReplyCandidates('', all), all);
      expect(quickReplyCandidates('a', all), [_addr]);
      expect(quickReplyCandidates('P', all), [_pay]);
      expect(quickReplyCandidates('zzz', all), isEmpty);
    });

    test('a lone /shortcut names its phrase', () {
      const all = [_addr, _pay];
      expect(quickReplyNamedBy('/addr', all), _addr);
      expect(quickReplyNamedBy('  /PAY ', all), _pay);
      expect(quickReplyNamedBy('/ad', all), isNull);
      expect(quickReplyNamedBy('/addr now', all), isNull);
      expect(quickReplyNamedBy('/', all), isNull);
      expect(quickReplyNamedBy('addr', all), isNull);
    });

    test('the away reply is on until its end time', () {
      final now = DateTime(2026, 10, 28, 12);
      expect(const AwayReply().isOn(now), isFalse);
      expect(const AwayReply(enabled: true, message: 'Away').isOn(now), isTrue);
      expect(const AwayReply(enabled: true, message: '  ').isOn(now), isFalse);
      expect(
        AwayReply(
          enabled: true,
          message: 'Away',
          until: now.add(const Duration(hours: 1)),
        ).isOn(now),
        isTrue,
      );
      expect(
        AwayReply(
          enabled: true,
          message: 'Away',
          until: now.subtract(const Duration(minutes: 1)),
        ).isOn(now),
        isFalse,
      );
    });

    test('the away reply reads the settings row', () {
      final away = AwayReply.fromJson({
        'away_enabled': true,
        'away_message': 'Back Monday',
        'away_until': '2026-11-02T00:00:00Z',
        'away_in_quiet_hours': true,
      });
      expect(away.enabled, isTrue);
      expect(away.message, 'Back Monday');
      expect(away.until, DateTime.utc(2026, 11, 2).toLocal());
      expect(away.duringQuietHours, isTrue);
      expect(AwayReply.fromJson(null).enabled, isFalse);
    });

    test('a message the server wrote for an away person says so', () {
      final json = {
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u1',
        'type': 'text',
        'body': 'Back Monday',
        'created_at': '2026-10-28T01:00:00Z',
        'auto_reply': true,
      };
      expect(ChatMessage.fromJson(json).autoReply, isTrue);
      expect(
        ChatMessage.fromJson({...json, 'auto_reply': false}).autoReply,
        isFalse,
      );
      expect(
        ChatMessage.fromJson(json).copyWith(body: 'x').autoReply,
        isTrue,
        reason: 'a copy keeps the label',
      );
    });
  });

  group('settings', () {
    Future<FakeQuickRepliesRepository> open(
      WidgetTester tester, {
      List<QuickReply> replies = const [],
      AwayReply away = const AwayReply(),
    }) async {
      // Tall enough for the sheets to show their buttons.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeQuickRepliesRepository(
        replies: replies,
        away: away,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            quickRepliesRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const QuickRepliesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('lists the phrases and the away reply', (tester) async {
      await open(tester, replies: [_addr, _pay]);
      expect(find.text('/addr'), findsOneWidget);
      expect(find.text('/pay'), findsOneWidget);
      // A line break in a phrase does not break the row.
      expect(find.text('Bank 12-3456 Please add your name.'), findsOneWidget);
      expect(find.byKey(const ValueKey('away-reply-row')), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('an empty list invites the first one', (tester) async {
      final repository = await open(tester);
      expect(find.text('No quick replies yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-replies-empty-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-shortcut')),
        ' /Hours ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-body')),
        'Open 9 to 5',
      );
      await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
      await tester.pumpAndSettle();
      expect(repository.replies.single.shortcut, 'hours');
      expect(repository.replies.single.body, 'Open 9 to 5');
      expect(find.text('/hours'), findsOneWidget);
    });

    testWidgets('a bad shortcut and a taken one say why', (tester) async {
      final repository = await open(tester, replies: [_addr]);
      await tester.tap(find.byKey(const ValueKey('quick-replies-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-shortcut')),
        'two words',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-body')),
        'x',
      );
      await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Use up to 32 characters, with no spaces or slashes.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-shortcut')),
        'ADDR',
      );
      await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
      await tester.pumpAndSettle();
      expect(find.text('You already use that shortcut.'), findsOneWidget);
      expect(repository.replies, [_addr]);
    });

    testWidgets('edits and deletes a phrase', (tester) async {
      final repository = await open(tester, replies: [_addr, _pay]);
      await tester.tap(find.byKey(const ValueKey('quick-reply-row-addr')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-body')),
        '99 High Road',
      );
      await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
      await tester.pumpAndSettle();
      expect(repository.replies.first.body, '99 High Road');

      await tester.tap(find.byKey(const ValueKey('quick-reply-row-pay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-reply-delete')));
      await tester.pumpAndSettle();
      expect(repository.replies.map((reply) => reply.shortcut), ['addr']);
      expect(find.text('/pay'), findsNothing);
    });

    testWidgets('a failed save keeps the sheet and says so', (tester) async {
      final repository = await open(tester);
      await tester.tap(find.byKey(const ValueKey('quick-replies-empty-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-shortcut')),
        'x',
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick-reply-body')),
        'y',
      );
      repository.failWrites = StateError('offline');
      await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the quick reply. Try again.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('quick-reply-save')));
      await tester.pumpAndSettle();
      expect(repository.replies.single.shortcut, 'x');
    });

    testWidgets('at 50 phrases there is no New button', (tester) async {
      await open(
        tester,
        replies: [
          for (var i = 0; i < maxQuickReplies; i++)
            QuickReply(id: 'r$i', shortcut: 's$i', body: 'b$i'),
        ],
      );
      expect(find.byKey(const ValueKey('quick-replies-new')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('You can keep up to 50 quick replies.'),
        400,
      );
      expect(find.text('You can keep up to 50 quick replies.'), findsOneWidget);
    });

    testWidgets('sets the away reply with an end time', (tester) async {
      final repository = await open(tester);
      await tester.tap(find.byKey(const ValueKey('away-reply-row')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('away-reply-message')),
        'Back Monday',
      );
      await tester.tap(find.byKey(const ValueKey('away-reply-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('away-reply-duration-oneDay')),
      );
      await tester.pumpAndSettle();
      final before = DateTime.now();
      await tester.tap(find.byKey(const ValueKey('away-reply-save')));
      await tester.pumpAndSettle();

      final saved = repository.savedAway.single;
      expect(saved.enabled, isTrue);
      expect(saved.message, 'Back Monday');
      expect(saved.until!.difference(before).inHours, inInclusiveRange(23, 24));
      expect(find.text('On until', findRichText: true), findsNothing);
      expect(find.textContaining('On until'), findsOneWidget);
    });

    testWidgets('switching on needs a message', (tester) async {
      final repository = await open(tester);
      await tester.tap(find.byKey(const ValueKey('away-reply-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('away-reply-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('away-reply-save')));
      await tester.pumpAndSettle();
      expect(find.text('Write what the reply says first.'), findsOneWidget);
      expect(repository.savedAway, isEmpty);
    });

    testWidgets('an end time already set can be kept or turned off', (
      tester,
    ) async {
      final until = DateTime.now().add(const Duration(hours: 5));
      final repository = await open(
        tester,
        away: AwayReply(enabled: true, message: 'Away', until: until),
      );
      expect(find.textContaining('On until'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('away-reply-row')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('away-reply-duration-keep')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('away-reply-enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('away-reply-save')));
      await tester.pumpAndSettle();
      final saved = repository.savedAway.single;
      expect(saved.enabled, isFalse);
      expect(saved.message, 'Away', reason: 'the words are kept for later');
      expect(saved.until, isNull);
    });

    testWidgets('the summary tells the three states', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final now = DateTime(2026, 10, 28, 12);
      expect(awayReplySummary(context, const AwayReply(), now), 'Off');
      expect(
        awayReplySummary(
          context,
          const AwayReply(duringQuietHours: true, message: 'x'),
          now,
        ),
        'Off, except in quiet hours',
      );
      expect(
        awayReplySummary(
          context,
          const AwayReply(enabled: true, message: 'x'),
          now,
        ),
        'On',
      );
    });
  });

  group('in a chat', () {
    testWidgets('typing a slash lists the phrases before the commands', (
      tester,
    ) async {
      final world = _World(replies: [_addr, _pay]);
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();

      await tester.enterText(_field, '/');
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-reply-addr')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-reply-pay')), findsOneWidget);
      expect(find.byKey(const ValueKey('slash-command-shrug')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('quick-reply-pay'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('slash-command-shrug')))
              .dy,
        ),
      );

      await tester.enterText(_field, '/ad');
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-reply-addr')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-reply-pay')), findsNothing);
      expect(find.byKey(const ValueKey('slash-command-shrug')), findsNothing);

      await tester.enterText(_field, '/nothing');
      await tester.pump();
      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
    });

    testWidgets('a shortcut with digits and Chinese is found', (tester) async {
      final world = _World(
        replies: [const QuickReply(id: 'z', shortcut: '地址2', body: '朝阳路 1 号')],
      );
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();
      await tester.enterText(_field, '/地');
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-reply-地址2')), findsOneWidget);
    });

    testWidgets('tapping a phrase puts it in the box and sends nothing', (
      tester,
    ) async {
      final world = _World(replies: [_addr, _pay]);
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();

      await tester.enterText(_field, '/pa');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quick-reply-pay')));
      await tester.pump();

      expect(_composerText(tester), _pay.body);
      expect(find.byKey(const ValueKey('slash-command-list')), findsNothing);
      expect(world.chats.sentMessages, isEmpty);

      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(world.chats.sentMessages.map((m) => m.body), [_pay.body]);
    });

    testWidgets('arrow keys and Enter pick through phrases and commands', (
      tester,
    ) async {
      final world = _World(replies: [_addr, _shrug]);
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();

      await tester.showKeyboard(_field);
      await tester.enterText(_field, '/s');
      await tester.pump();
      ListTile tile(String key) =>
          tester.widget<ListTile>(find.byKey(ValueKey(key)));
      // The phrase named like a command comes first, then the commands.
      expect(tile('quick-reply-shrug').selected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tile('slash-command-shrug').selected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_composerText(tester), 'No idea');

      await tester.enterText(_field, '/s');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_composerText(tester), '/shrug ', reason: 'the command itself');
    });

    testWidgets('sending a lone /shortcut sends the phrase', (tester) async {
      final world = _World(replies: [_addr, _shrug]);
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();

      await _send(tester, '/addr');
      expect(world.chats.sentMessages.map((m) => m.body), ['12 Main Street']);

      // A command with the same name still runs as the command.
      await _send(tester, '/shrug');
      expect(world.chats.sentMessages.last.body, r'¯\\\_(ツ)\_/¯');

      // An unknown one, or one with more after it, is sent as written.
      await _send(tester, '/unknown');
      expect(world.chats.sentMessages.last.body, '/unknown');
      await _send(tester, '/addr please');
      expect(world.chats.sentMessages.last.body, '/addr please');
    });

    testWidgets('editing a message offers no phrases', (tester) async {
      final world = _World(replies: [_addr]);
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
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Typo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(_field, '/addr');
      await tester.pump();
      expect(find.byKey(const ValueKey('quick-reply-addr')), findsNothing);
    });

    testWidgets('the + menu opens the phrases and puts one in the box', (
      tester,
    ) async {
      final world = _World(replies: [_addr, _pay]);
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();

      await tester.enterText(_field, 'Hi, ');
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('composer-quick-replies-entry')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('quick-reply-pick-addr')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('quick-reply-pick-addr')));
      await tester.pumpAndSettle();
      expect(_composerText(tester), 'Hi, 12 Main Street');
    });

    testWidgets('the picker says when there are none and offers to manage', (
      tester,
    ) async {
      final world = _World();
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('composer-quick-replies-entry')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No quick replies yet.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-reply-manage')));
      await tester.pumpAndSettle();
      expect(find.byType(QuickRepliesScreen), findsOneWidget);
    });

    testWidgets('an auto-reply is labelled under its bubble', (tester) async {
      final world = _World();
      world.chats.messages = [
        ChatMessage(
          id: 'message-1',
          conversationId: 'conversation-1',
          senderId: 'user-2',
          type: MessageType.text,
          body: 'Back Monday',
          createdAt: DateTime.utc(2026, 10, 13, 9),
          autoReply: true,
        ),
        ChatMessage(
          id: 'message-2',
          conversationId: 'conversation-1',
          senderId: 'user-2',
          type: MessageType.text,
          body: 'A real message',
          createdAt: DateTime.utc(2026, 10, 13, 10),
        ),
      ];
      await tester.pumpWidget(world.app());
      await tester.pumpAndSettle();
      expect(find.text('Back Monday'), findsOneWidget);
      expect(find.byKey(const ValueKey('auto-reply-mark')), findsOneWidget);
      expect(find.text('Auto-reply'), findsOneWidget);
    });
  });

  group('the + menu entry', () {
    test('is registered at the end of the menu', () {
      expect(quickRepliesComposerEntry.id, 'quick-replies');
      expect(quickRepliesComposerEntry.order, greaterThan(1350));
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

class _World {
  _World({List<QuickReply> replies = const []})
    : quick = FakeQuickRepliesRepository(replies: replies) {
    chats.conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.direct,
        unreadCount: 0,
        title: 'Ada Lovelace',
      ),
    ];
  }

  final chats = chat_fakes.FakeChatsRepository();
  final circles = circle_fakes.FakeCirclesRepository();
  final settings = chat_fakes.FakeSettingsRepository();
  final FakeQuickRepliesRepository quick;

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        circlesRepositoryProvider.overrideWithValue(circles),
        settingsRepositoryProvider.overrideWithValue(settings),
        quickRepliesRepositoryProvider.overrideWithValue(quick),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        authRepositoryProvider.overrideWithValue(
          chat_fakes.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}
