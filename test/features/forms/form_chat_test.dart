import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_builtin.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_registrations.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/forms_chat.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import 'form_fakes.dart';

ChatMessage formMessage() {
  return ChatMessage(
    id: 'form-message',
    conversationId: 'conversation-1',
    senderId: 'user-2',
    type: MessageType.text,
    body: '\u{1F4DD} Hike sign-up',
    createdAt: DateTime.utc(2026, 10, 18, 9),
    attachment: const {
      'kind': 'form',
      'form_id': 'form-1',
      'title': 'Hike sign-up',
    },
  );
}

class _World {
  _World({this.type = ConversationType.group}) {
    chats.conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: type,
        unreadCount: 0,
        title: 'Hike club',
      ),
    ];
  }

  final ConversationType type;
  final chats = chat_fakes.FakeChatsRepository();
  final forms = FakeFormRepository(conversationId: 'conversation-1');

  Widget app() {
    return ProviderScope(
      retry: (count, error) => null,
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        ...formOverrides(forms, conversationId: 'conversation-1'),
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
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: const ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}

void main() {
  testWidgets('a form message is the live card, not its text', (tester) async {
    final world = _World();
    world.forms
      ..settings = const FormSettings(maxResponses: 30)
      ..addSheet('user-3', 'Bob', {'name': 'Bob', 'size': 's'});
    world.chats.messages = [formMessage()];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('form-card-form-1')), findsOneWidget);
    expect(find.text('Hike sign-up'), findsOneWidget);
    expect(find.textContaining('1/30 submitted'), findsOneWidget);
    // The text of the message is not drawn next to the card.
    expect(find.textContaining('\u{1F4DD}'), findsNothing);

    // Somebody answers: the card changes, and no message is added.
    world.forms
      ..addSheet('user-4', 'Cy', {'name': 'Cy', 'size': 'm'})
      ..touch();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.textContaining('2/30 submitted'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the attach menu of a group has Form and it opens the builder', (
    tester,
  ) async {
    final world = _World();
    await tester.pumpWidget(world.app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-form-entry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer-form-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('form-builder-page')), findsOneWidget);
    expect(find.text('New form'), findsOneWidget);
  });

  testWidgets('a circle channel has Form too', (tester) async {
    final world = _World(type: ConversationType.channel);
    await tester.pumpWidget(world.app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-form-entry')), findsOneWidget);
  });

  testWidgets('a direct chat has no Form', (tester) async {
    final world = _World(type: ConversationType.direct);
    await tester.pumpWidget(world.app());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
    await tester.pumpAndSettle();
    expect(find.text('Create poll'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-form-entry')), findsNothing);
  });

  test('the entry sits between Chain and Contact card in the menu', () {
    final registry = ComposerMenuRegistry([
      ...builtInComposerMenu,
      formComposerEntry,
    ]);
    final ids = registry.ids;
    expect(ids.indexOf('form'), ids.indexOf('chain') + 1);
    expect(ids.indexOf('form'), ids.indexOf('contact-card') - 1);
    expect(composerMenuExtensions, contains(formComposerEntry));
  });
}
