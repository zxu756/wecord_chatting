import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import '../file_preview/file_preview_fakes.dart';
import 'ai_fakes.dart';

/// A chat with three messages (the reader has read the first), wired to a
/// [FakeAiRepository].
class AiChatHarness {
  AiChatHarness(
    this.ai, {
    int unread = 0,
    this.enabledStore,
    ConversationType type = ConversationType.direct,
    String? circleId,
    List<ChatMessage>? messages,
    this.extraOverrides = const [],
  }) {
    chats = chat_fakes.FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: type,
          unreadCount: unread,
          circleId: circleId,
        ),
      ]
      ..messages =
          messages ??
          [
            message('message-1', 'user-1', 'Read already', 1),
            message('message-2', 'user-2', 'First unread', 2),
            message('message-3', 'user-2', 'Second unread', 3),
          ]
      ..readMarkers = const [
        ConversationReadMarker(
          userId: 'user-1',
          lastReadMessageId: 'message-1',
        ),
      ];
  }

  final FakeAiRepository ai;
  final AiEnabledStore? enabledStore;

  /// More provider overrides, for features that ride on this chat.
  final List<Override> extraOverrides;
  late final chat_fakes.FakeChatsRepository chats;

  static ChatMessage message(
    String id,
    String sender,
    String body,
    int minute,
  ) {
    return ChatMessage(
      id: id,
      conversationId: 'conversation-1',
      senderId: sender,
      type: MessageType.text,
      body: body,
      createdAt: DateTime.utc(2026, 5, 18, 4, minute),
    );
  }

  Widget build({ThemeData? theme, String title = 'Ada Lovelace'}) {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          chat_fakes.FakeSettingsRepository(),
        ),
        ...filePreviewOverrides(),
        authRepositoryProvider.overrideWithValue(
          chat_fakes.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
        aiRepositoryProvider.overrideWithValue(ai),
        aiEnabledStoreProvider.overrideWithValue(
          enabledStore ?? InMemoryAiEnabledStore(),
        ),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: theme ?? WeCordTheme.light(),
        home: ChatThreadScreen(conversationId: 'conversation-1', title: title),
      ),
    );
  }
}
