import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/composer_shortcuts.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/message.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;

ChatMessage _message(
  String id, {
  String senderId = 'user-1',
  String body = 'hello',
  int minute = 0,
  MessageType type = MessageType.text,
  DateTime? recalledAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: type,
    body: body,
    createdAt: DateTime.utc(2026, 10, 16, 9, minute),
    recalledAt: recalledAt,
  );
}

Widget _app(
  chat_fakes.FakeChatsRepository repository,
  ComposerDraftStore store, {
  String conversationId = 'conversation-1',
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(repository),
      composerDraftStoreProvider.overrideWithValue(store),
      onlineUserIdsProvider.overrideWith(
        (ref) => const Stream<Set<String>>.empty(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        chat_fakes.FakeSettingsRepository(),
      ),
      authRepositoryProvider.overrideWithValue(
        chat_fakes.FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(home: _Switcher(initial: conversationId)),
  );
}

/// Swaps the open conversation in place, like the wide circle layout.
class _Switcher extends StatefulWidget {
  const _Switcher({required this.initial});

  final String initial;

  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  late String conversationId = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() {
            conversationId = conversationId == 'conversation-1'
                ? 'conversation-2'
                : 'conversation-1';
          }),
          child: const Text('switch'),
        ),
        Expanded(child: ChatThreadScreen(conversationId: conversationId)),
      ],
    );
  }
}

final _composer = find.byKey(const ValueKey('chat-composer-field'));

String _composerText(WidgetTester tester) {
  return tester.widget<TextField>(_composer).controller!.text;
}

void main() {
  group('drafts', () {
    test('encode and decode round trip, dropping junk', () {
      final drafts = {
        'a': const ComposerDraft(
          text: 'hi @ada',
          replyToMessageId: 'm1',
          mentions: [
            DraftMention(userId: 'u1', username: 'ada', displayName: 'Ada'),
          ],
        ),
      };
      final decoded = decodeComposerDrafts(encodeComposerDrafts(drafts));
      expect(decoded.keys, ['a']);
      expect(decoded['a']!.text, 'hi @ada');
      expect(decoded['a']!.replyToMessageId, 'm1');
      expect(decoded['a']!.mentions.single.username, 'ada');

      expect(decodeComposerDrafts('not json'), isEmpty);
      expect(decodeComposerDrafts('{"a": {"text": "  "}, "b": 3}'), isEmpty);
      expect(decodeComposerDrafts(null), isEmpty);
    });

    test('the controller loads, keeps and removes drafts per user', () async {
      final store = InMemoryComposerDraftStore({
        'user-1': {'c1': const ComposerDraft(text: 'saved')},
      });
      final container = ProviderContainer(
        overrides: [
          composerDraftStoreProvider.overrideWithValue(store),
          authRepositoryProvider.overrideWithValue(
            chat_fakes.FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(composerDraftsProvider.notifier);
      await controller.loaded;
      expect(container.read(composerDraftsProvider)['c1']?.text, 'saved');

      controller.set('c2', const ComposerDraft(text: 'new'));
      controller.set('c1', const ComposerDraft(text: ''));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(composerDraftsProvider).keys, ['c2']);
      expect(store.drafts['user-1']!.keys, ['c2']);
    });
  });

  group('lastEditableMessage', () {
    test('picks the newest own text message that is not deleted', () {
      final messages = [
        _message('old', minute: 1),
        _message('newest-own', minute: 3),
        _message('theirs', senderId: 'user-2', minute: 5),
        _message('image', type: MessageType.image, minute: 6),
        _message('deleted', minute: 7, recalledAt: DateTime.utc(2026)),
      ];
      expect(lastEditableMessage(messages, 'user-1')?.id, 'newest-own');
      expect(lastEditableMessage(messages, null), isNull);
    });
  });

  testWidgets('a typed draft comes back after switching conversations', (
    tester,
  ) async {
    final store = InMemoryComposerDraftStore();
    final repository = chat_fakes.FakeChatsRepository();
    await tester.pumpWidget(_app(repository, store));
    await tester.pump();

    await tester.enterText(_composer, 'half written');
    await tester.pump();
    expect(store.drafts['user-1']?['conversation-1']?.text, 'half written');

    await tester.tap(find.text('switch'));
    await tester.pump();
    await tester.pump();
    expect(_composerText(tester), isEmpty);

    await tester.tap(find.text('switch'));
    await tester.pump();
    await tester.pump();
    expect(_composerText(tester), 'half written');
  });

  testWidgets('a saved draft and its reply are restored on open', (
    tester,
  ) async {
    final store = InMemoryComposerDraftStore({
      'user-1': {
        'conversation-1': const ComposerDraft(
          text: 'restored',
          replyToMessageId: 'message-1',
        ),
      },
    });
    final repository = chat_fakes.FakeChatsRepository()
      ..messages = [_message('message-1', senderId: 'user-2', body: 'Hi')];
    await tester.pumpWidget(_app(repository, store));
    await tester.pump();
    await tester.pump();

    expect(_composerText(tester), 'restored');
    expect(find.textContaining('Replying to'), findsOneWidget);

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(repository.sentReplyToMessageId, 'message-1');
    expect(store.drafts['user-1']?['conversation-1'], isNull);
  });

  testWidgets('Up in an empty composer edits the last message; Esc cancels', (
    tester,
  ) async {
    final repository = chat_fakes.FakeChatsRepository()
      ..messages = [
        _message('message-1', body: 'first', minute: 1),
        _message('message-2', body: 'second', minute: 2),
      ];
    await tester.pumpWidget(_app(repository, InMemoryComposerDraftStore()));
    await tester.pump();

    await tester.tap(_composer);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('Editing message'), findsOneWidget);
    expect(_composerText(tester), 'second');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(find.text('Editing message'), findsNothing);
    expect(_composerText(tester), isEmpty);

    // Nothing to cancel: Esc marks the conversation read.
    repository.markReadCalls.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(repository.markReadCalls, ['conversation-1']);
  });
}
