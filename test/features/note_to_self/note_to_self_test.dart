import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../../mobile/phone_test_support.dart';

const _noteId = 'note-1';

const _desktop = PhoneViewport(
  name: '1280x800',
  size: Size(1280, 800),
  devicePixelRatio: 1,
);

/// The summary the server sends for the note to self.
final _note = ConversationSummary(
  id: _noteId,
  type: ConversationType.direct,
  unreadCount: 0,
  title: 'Note to self',
  memberCount: 1,
  isNoteToSelf: true,
  pinnedAt: minutesAgo(5000),
  lastMessageBody: 'laptop link: example.com',
  lastMessageType: MessageType.text,
  lastMessageSenderId: 'user-1',
  lastMessageAt: minutesAgo(60),
);

class FakeNoteToSelfRepository implements NoteToSelfRepository {
  var ensured = 0;
  Object? fail;

  @override
  Future<String> ensure() async {
    ensured++;
    if (fail case final error?) {
      throw error;
    }
    return _noteId;
  }
}

ChatMessage _mine(String id, String body, {int minutes = 5}) {
  return phoneMessage(
    id,
    me,
    body,
    minutesAgo: minutes,
    conversationId: _noteId,
  );
}

void main() {
  tearDown(() => AppStrings.isChinese = false);

  group('the list', () {
    test('puts the note to self first, making a placeholder when needed', () {
      final a = ConversationSummary(
        id: 'a',
        type: ConversationType.direct,
        unreadCount: 0,
      );
      final b = ConversationSummary(
        id: 'b',
        type: ConversationType.group,
        unreadCount: 2,
      );
      expect(withNoteToSelfFirst([a, b]).map((c) => c.id), [
        noteToSelfPlaceholderId,
        'a',
        'b',
      ]);
      expect(withNoteToSelfFirst([a, _note, b]).map((c) => c.id), [
        _noteId,
        'a',
        'b',
      ]);
      expect(withNoteToSelfFirst(const []).single.isNoteToSelf, isTrue);
      expect(noteToSelfPlaceholder.unreadCount, 0);
    });

    test('the server flag is read, and kept by copyWith', () {
      final summary = ConversationSummary.fromJson({
        'id': _noteId,
        'type': 'direct',
        'title': 'Note to self',
        'unread_count': 0,
        'member_count': 1,
        'is_note_to_self': true,
      });
      expect(summary.isNoteToSelf, isTrue);
      expect(summary.copyWith(isMuted: true).isNoteToSelf, isTrue);
      expect(
        ConversationSummary.fromJson({
          'id': 'x',
          'type': 'direct',
          'unread_count': 0,
        }).isNoteToSelf,
        isFalse,
      );
    });

    test('is called 文件传输助手 in Chinese', () {
      expect(noteToSelfTitle(), 'Note to self');
      AppStrings.isChinese = true;
      expect(noteToSelfTitle(), '文件传输助手');
    });

    testWidgets('shows a placeholder row first, before the chat exists', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      await world.open(tester, '/home');

      final rows = tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'home-dm-',
                  ) &&
                  !(widget.key! as ValueKey<String>).value.contains('age'),
            ),
          )
          .toList();
      expect(
        (rows.first.key! as ValueKey<String>).value,
        'home-dm-$noteToSelfPlaceholderId',
      );
      expect(find.text('Note to self'), findsOneWidget);
      expect(
        find.text('Send text, photos and files to your devices'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('note-to-self-avatar')), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('tapping the placeholder makes the chat and opens it', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      final notes = FakeNoteToSelfRepository();
      world.extraOverrides = [
        noteToSelfRepositoryProvider.overrideWithValue(notes),
      ];
      world.chats.messages = [_mine('n1', 'link for later')];
      await world.open(tester, '/home');

      await tester.tap(
        find.byKey(const ValueKey('home-dm-$noteToSelfPlaceholderId')),
      );
      await settle(tester);

      expect(notes.ensured, 1);
      expect(world.router.state.uri.path, '/chats/$_noteId');
      expect(find.text('Note to self'), findsWidgets);
      await world.close(tester);
    });

    testWidgets('a failure to make it is said, and the list stays', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      final notes = FakeNoteToSelfRepository()..fail = StateError('offline');
      world.extraOverrides = [
        noteToSelfRepositoryProvider.overrideWithValue(notes),
      ];
      await world.open(tester, '/home');

      await tester.tap(
        find.byKey(const ValueKey('home-dm-$noteToSelfPlaceholderId')),
      );
      await settle(tester);

      expect(find.text("Couldn't open your note to self."), findsOneWidget);
      expect(world.router.state.uri.path, '/home');
      await world.close(tester);
    });

    testWidgets('the real chat is first too, and never unread', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats.conversations = [
        ...world.chats.conversations,
        _note.copyWith(unreadCount: 7),
      ];
      await world.open(tester, '/home');

      expect(find.byKey(const ValueKey('home-dm-$_noteId')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-dm-$noteToSelfPlaceholderId')),
        findsNothing,
      );
      final row = find.byKey(const ValueKey('home-dm-$_noteId'));
      final dm1 = find.byKey(const ValueKey('home-dm-dm-1'));
      expect(tester.getTopLeft(row).dy, lessThan(tester.getTopLeft(dm1).dy));
      // What it last held, no presence dot, no pin.
      expect(
        find.descendant(
          of: row,
          matching: find.text('You: laptop link: example.com'),
        ),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('has no actions menu: nothing to pin, mute or delete', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats.conversations = [..._withNote(world)];
      await world.open(tester, '/home');

      await tester.longPress(find.byKey(const ValueKey('home-dm-$_noteId')));
      await settle(tester);
      expect(find.text('Pin chat'), findsNothing);
      expect(find.text('Delete conversation'), findsNothing);

      // Another chat does.
      await tester.longPress(find.byKey(const ValueKey('home-dm-dm-1')));
      await settle(tester);
      expect(find.text('Delete conversation'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('is first in the desktop sidebar too', (tester) async {
      usePhoneViewport(tester, _desktop);
      final world = PhoneWorld();
      await world.open(tester, '/home');

      expect(
        find.byKey(const ValueKey('home-dm-$noteToSelfPlaceholderId')),
        findsOneWidget,
      );
      expect(find.text('Note to self'), findsOneWidget);
      await world.close(tester);
    });
  });

  group('the chat', () {
    Future<PhoneWorld> openNote(WidgetTester tester) async {
      final world = PhoneWorld();
      world.chats
        ..conversations = [..._withNote(world)]
        ..messages = [
          _mine('n1', 'link for my laptop', minutes: 30),
          _mine('n2', 'second note', minutes: 20),
        ]
        // Somebody else's read position must not show as a receipt.
        ..readMarkers = const [];
      await world.open(
        tester,
        '/chats/$_noteId',
        extra: const ChatThreadRouteExtra(
          title: 'Note to self',
          type: ConversationType.direct,
        ),
      );
      return world;
    }

    testWidgets('is titled, and says only you see it', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = await openNote(tester);

      expect(find.text('Note to self'), findsWidgets);
      expect(find.text('Only you can see this chat'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-to-self-avatar')), findsOneWidget);
      expect(find.text('link for my laptop'), findsOneWidget);
      // Not "Offline": there is nobody to be online.
      expect(find.text('Offline'), findsNothing);
      await world.close(tester);
    });

    testWidgets('offers no calls or events', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = await openNote(tester);

      expect(find.byTooltip('Start voice call'), findsNothing);
      expect(find.byTooltip('Start video call'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-header-more')));
      await settle(tester);
      expect(find.text('Events'), findsNothing);
      await world.close(tester);
    });

    testWidgets('a chat with a friend does offer them (control)', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats.messages = richMessages();
      await world.open(tester, '/chats/dm-1');
      expect(find.byTooltip('Start voice call'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('shares no typing', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = await openNote(tester);

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'a draft that only I see',
      );
      await tester.pump(const Duration(seconds: 4));
      expect(world.chats.typingUpdates, isEmpty);
      await world.close(tester);
    });

    testWidgets('typing is shared in a chat with a friend (control)', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats.messages = richMessages();
      await world.open(tester, '/chats/dm-1');

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'hello',
      );
      await tester.pump(const Duration(seconds: 4));
      expect(world.chats.typingUpdates, isNotEmpty);
      await world.close(tester);
    });

    testWidgets('shows no read receipt', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats
        ..conversations = [..._withNote(world)]
        ..messages = [_mine('n1', 'one'), _mine('n2', 'two', minutes: 1)]
        // A receipt would show here if anybody had read the latest message.
        ..readMarkers = const [
          ConversationReadMarker(userId: 'user-1', lastReadMessageId: 'n1'),
          ConversationReadMarker(userId: 'user-2', lastReadMessageId: 'n2'),
        ];
      await world.open(tester, '/chats/$_noteId');

      expect(find.text('two'), findsOneWidget);
      expect(find.text('Read'), findsNothing);
      await world.close(tester);
    });

    testWidgets('sends text like any chat', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final world = await openNote(tester);

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'from my phone',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);

      expect(world.chats.sentMessages.single.conversationId, _noteId);
      expect(world.chats.sentMessages.single.body, 'from my phone');
      await world.close(tester);
    });
  });
}

List<ConversationSummary> _withNote(PhoneWorld world) => [
  ...world.chats.conversations,
  _note,
];
