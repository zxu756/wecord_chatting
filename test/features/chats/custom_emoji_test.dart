import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../circles/circle_emojis_test.dart';
import 'chat_thread_screen_test.dart' as chat_fakes;
import 'message_markdown_test.dart' show describe;

const _parrot = '<:party_parrot:$partyParrotId>';
const _strangerId = '00000000-0000-4000-8000-0000000000ff';

ChatMessage _message(
  String id,
  String body, {
  int minute = 0,
  String senderId = 'user-2',
  MessageType type = MessageType.text,
  Map<String, dynamic>? attachment,
  List<MessageReaction> reactions = const [],
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: type,
    body: body,
    attachment: attachment,
    reactions: reactions,
    createdAt: DateTime.utc(2026, 10, 14, 9, minute),
  );
}

Map<String, dynamic> _stickerAttachment(String id, String name) {
  return {
    'kind': 'sticker',
    'emoji_id': id,
    'name': name,
    'circle_id': 'circle-1',
  };
}

chat_fakes.FakeChatsRepository _channel(List<ChatMessage> messages) {
  return chat_fakes.FakeChatsRepository()
    ..conversations = [
      const ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.channel,
        unreadCount: 0,
        title: 'general',
        circleId: 'circle-1',
      ),
    ]
    ..messages = messages;
}

Widget _app(
  chat_fakes.FakeChatsRepository chats, {
  FakeCircleEmojiRepository? emojis,
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      circleEmojiRepositoryProvider.overrideWithValue(
        emojis ?? FakeCircleEmojiRepository(),
      ),
      testEmojiImageOverride(),
      settingsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeSettingsRepository(),
      ),
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

void main() {
  group('markdown', () {
    test('custom emoji tokens are atomic, outside code', () {
      expect(
        describe('hi $_parrot!'),
        'hi emoji(party_parrot,$partyParrotId)!',
      );
      // Underscores in names are not emphasis.
      expect(
        describe('_a $_parrot b_'),
        'i(a emoji(party_parrot,$partyParrotId) b)',
      );
      expect(describe('**$_parrot**'), 'b(emoji(party_parrot,$partyParrotId))');
      expect(describe('`$_parrot`'), 'code($_parrot)');
      expect(describe('```\n$_parrot\n```'), 'codeblock[$_parrot]');
      expect(describe(r'\' + _parrot), _parrot);
      // Not a token: uppercase names, short ids.
      expect(describe('<:Party:$partyParrotId>'), '<:Party:$partyParrotId>');
      expect(describe('<:party:1234>'), '<:party:1234>');
    });

    test('plain text shows :name:', () {
      expect(
        plainTextFromMarkdown('so $_parrot much'),
        'so :party_parrot: much',
      );
      expect(firstLinkInMarkdown('$_parrot https://a.test'), 'https://a.test');
    });

    test('emoji-only messages are enlarged, up to 27', () {
      bool emojiOnly(String body) {
        return isEmojiOnlyMarkdown(parseMessageMarkdown(body));
      }

      expect(emojiOnly(_parrot), isTrue);
      expect(emojiOnly('$_parrot 👍 🇳🇿 1️⃣'), isTrue);
      expect(emojiOnly('👍🏽❤️'), isTrue);
      expect(emojiOnly('$_parrot hi'), isFalse);
      expect(emojiOnly('123'), isFalse);
      expect(emojiOnly('**$_parrot**'), isFalse);
      expect(emojiOnly('> $_parrot'), isFalse);
      expect(emojiOnly(List.filled(27, '😀').join()), isTrue);
      expect(emojiOnly(List.filled(28, '😀').join()), isFalse);
      expect(emojiOnly('   '), isFalse);
    });
  });

  group('composer encoding', () {
    final usable = testEmojis();

    test('picked and typed :name: become tokens outside code', () {
      final draft = CustomEmojiDraft();
      final controller = TextEditingController(text: 'hey :par');
      expect(emojiQueryAt(controller.value), 'par');
      expect(draft.insert(controller, usable.first), isTrue);
      expect(controller.text, 'hey :party_parrot: ');

      expect(
        draft.encode(
          ':party_parrot: `:blob_wave:` :blob_wave: :nope: :cat_thumbs:',
          usable: usable,
          circleId: 'circle-1',
        ),
        '$_parrot `:blob_wave:` <:blob_wave:$blobWaveId> :nope: '
        '<:cat_thumbs:$catThumbsId>',
      );
      // Stickers are not emoji; escapes and existing tokens stay.
      expect(
        draft.encode(
          r':wave: \:blob_wave: '
          '$_parrot',
          usable: usable,
        ),
        r':wave: \:blob_wave: '
        '$_parrot',
      );
    });

    test('editing shows known tokens as :name:', () {
      final draft = CustomEmojiDraft();
      final byId = {for (final emoji in usable) emoji.id: emoji};
      final shown = draft.decode('$_parrot and <:gone:$_strangerId>', byId);
      expect(shown, ':party_parrot: and <:gone:$_strangerId>');
      expect(
        draft.encode(shown, usable: const []),
        '$_parrot and <:gone:$_strangerId>',
      );
    });

    test('suggestions: emoji only, prefix and own circle first', () {
      expect(emojiQueryAt(const TextEditingValue(text: 'a:b')), isNull);
      expect(emojiQueryAt(const TextEditingValue(text: 'see :b')), isNull);
      expect(emojiQueryAt(const TextEditingValue(text: ':Bl')), 'bl');
      final names = [
        for (final emoji in customEmojiCandidates(
          usable,
          'a',
          circleId: 'circle-2',
        ))
          emoji.name,
      ];
      expect(names, ['cat_thumbs', 'blob_wave', 'party_parrot']);
      expect(customEmojiCandidates(usable, 'ship'), isEmpty);
    });

    test('stickers, reactions and previews', () {
      final sticker = ChatMessage.fromJson({
        'id': 'm1',
        'conversation_id': 'conversation-1',
        'sender_id': 'user-1',
        'type': 'sticker',
        'body': 'wave',
        'attachment': _stickerAttachment(waveStickerId, 'wave'),
        'created_at': '2026-10-14T09:00:00Z',
        'reactions': [
          {
            'emoji': 'custom:$partyParrotId',
            'count': 2,
            'custom_name': 'party_parrot',
          },
        ],
      });
      expect(sticker.type, MessageType.sticker);
      expect(sticker.stickerAttachment?.emojiId, waveStickerId);
      expect(sticker.reactions.single.customEmojiId, partyParrotId);
      expect(sticker.reactions.single.customName, 'party_parrot');
      expect(stickerPreviewText('wave'), '[Sticker] wave');
      expect(customReactionEmojiId('custom:nope'), isNull);
      expect(customReactionEmojiId('👍'), isNull);
      expect(
        reactionLabel(sticker.reactions.single, const {}),
        ':party_parrot:',
      );
      expect(
        reactionLabel(const MessageReaction(emoji: '👍', count: 1), const {}),
        '👍',
      );
    });
  });

  group('thread', () {
    testWidgets('shows usable custom emoji inline and others as :name:', (
      tester,
    ) async {
      final chats = _channel([
        _message('m1', 'hello $_parrot and <:gone:$_strangerId>'),
        _message('m2', '$_parrot <:blob_wave:$blobWaveId>', minute: 1),
      ]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      final inline = find.byKey(const ValueKey('custom-emoji-$partyParrotId'));
      expect(inline, findsNWidgets(2));
      // Inline in m1, large in m2.
      expect(
        {
          for (final element in inline.evaluate())
            tester.getSize(find.byWidget(element.widget)).height,
        },
        {customEmojiInlineSize, customEmojiJumboSize},
      );
      expect(find.textContaining(':gone:', findRichText: true), findsOneWidget);
      // m2 holds only emoji, so they show large.
      expect(
        tester.getSize(find.byKey(const ValueKey('custom-emoji-$blobWaveId'))),
        const Size.square(customEmojiJumboSize),
      );
    });

    testWidgets('stickers show without a bubble, and are not forwarded', (
      tester,
    ) async {
      final chats = _channel([
        _message(
          'm1',
          'wave',
          type: MessageType.sticker,
          attachment: _stickerAttachment(waveStickerId, 'wave'),
        ),
        _message(
          'm2',
          'secret',
          minute: 1,
          type: MessageType.sticker,
          attachment: _stickerAttachment(_strangerId, 'secret'),
        ),
      ]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      final sticker = find.byKey(
        const ValueKey('sticker-image-$waveStickerId'),
      );
      expect(sticker, findsOneWidget);
      expect(tester.getSize(sticker), const Size.square(stickerSize));
      // Someone else's circle: a placeholder with the name.
      expect(find.byKey(const ValueKey('sticker-placeholder')), findsOneWidget);
      expect(find.text('[Sticker] secret'), findsOneWidget);

      await tester.longPress(sticker);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('custom reactions show the image or :name:', (tester) async {
      final chats = _channel([
        _message(
          'm1',
          'Nice',
          reactions: [
            MessageReaction(emoji: 'custom:$partyParrotId', count: 2),
            const MessageReaction(
              emoji: 'custom:$_strangerId',
              count: 1,
              customName: 'far_away',
            ),
          ],
        ),
      ]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      final chip = find.byKey(
        const ValueKey('reaction-chip-custom:$partyParrotId'),
      );
      expect(
        find.descendant(of: chip, matching: find.byType(CustomEmojiImage)),
        findsOneWidget,
      );
      expect(find.text(':far_away:'), findsOneWidget);

      await tester.tap(chip);
      await tester.pump();
      expect(chats.toggledReactions, [('m1', 'custom:$partyParrotId')]);
    });

    testWidgets('the reaction picker offers this circle\'s and other emoji', (
      tester,
    ) async {
      final chats = _channel([_message('m1', 'React to me')]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('React to me'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More reactions'));
      await tester.pumpAndSettle();

      expect(find.text('This circle'), findsOneWidget);
      expect(find.text('Your emoji'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('custom-emoji-option-$catThumbsId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('custom-emoji-option-$waveStickerId')),
        findsNothing,
        reason: 'stickers are not reactions',
      );
      await tester.tap(
        find.byKey(const ValueKey('custom-emoji-option-$partyParrotId')),
      );
      await tester.pumpAndSettle();
      expect(chats.toggledReactions, [('m1', 'custom:$partyParrotId')]);
    });

    testWidgets('typing :name suggests emoji and sends a token', (
      tester,
    ) async {
      final chats = _channel([_message('m1', 'Hi')]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('chat-composer-field'));
      await tester.enterText(field, 'look :pa');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('custom-emoji-candidates')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('custom-emoji-candidate-$partyParrotId')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('custom-emoji-candidates')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(field).controller!.text,
        'look :party_parrot: ',
      );

      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(chats.sentMessages.single.body, 'look $_parrot');
    });

    testWidgets('editing shows emoji as :name: and saves tokens', (
      tester,
    ) async {
      final chats = _channel([
        _message('m1', 'mine $_parrot', senderId: 'user-1'),
      ]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      await tester.longPress(find.textContaining('mine', findRichText: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('chat-composer-field'));
      expect(
        tester.widget<TextField>(field).controller!.text,
        'mine :party_parrot:',
      );
      await tester.enterText(field, 'mine :party_parrot: :blob_wave:');
      await tester.tap(find.byTooltip('Save edit'));
      await tester.pumpAndSettle();
      expect(chats.editedBody, 'mine $_parrot <:blob_wave:$blobWaveId>');
    });

    testWidgets('the attach menu sends a sticker', (tester) async {
      final chats = _channel([_message('m1', 'Hi')]);
      await tester.pumpWidget(_app(chats));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send sticker'));
      await tester.pumpAndSettle();

      expect(find.text('This circle'), findsOneWidget);
      expect(find.text('Hiking'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('sticker-option-$shipItStickerId')),
      );
      await tester.pumpAndSettle();
      expect(chats.sentStickers, [('conversation-1', shipItStickerId)]);
    });

    testWidgets('without stickers the picker says how to add some', (
      tester,
    ) async {
      final chats = _channel([_message('m1', 'Hi')]);
      await tester.pumpWidget(
        _app(chats, emojis: FakeCircleEmojiRepository(const [])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send sticker'));
      await tester.pumpAndSettle();
      expect(
        find.text('No stickers yet. Circles add them under Emoji & stickers.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('message text renders custom emoji only when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          circleEmojiRepositoryProvider.overrideWithValue(
            FakeCircleEmojiRepository(),
          ),
          testEmojiImageOverride(),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MessageMarkdownText(body: _parrot, color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Not enlarged unless asked.
    expect(
      tester.getSize(find.byKey(const ValueKey('custom-emoji-$partyParrotId'))),
      const Size.square(customEmojiInlineSize),
    );
  });
}
