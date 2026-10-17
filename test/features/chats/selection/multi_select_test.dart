import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../file_preview/file_preview_fakes.dart';
import '../../later/later_fakes.dart';
import '../chat_thread_screen_test.dart' as thread_test;
import '../merged_forward/merged_forward_fakes.dart';

ChatMessage _text(String id, String senderId, String body, int minute) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.text,
    body: body,
    createdAt: DateTime.utc(2026, 5, 18, 4, minute),
    sender: Profile(
      id: senderId,
      username: senderId == 'user-1' ? 'me' : 'ada',
      displayName: senderId == 'user-1' ? 'Me' : 'Ada Lovelace',
      bio: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  );
}

void main() {
  late thread_test.FakeChatsRepository chats;
  late FakeMergedForwardRepository merged;
  late FakeSavedMessagesRepository saved;
  String? clipboard;

  setUp(() {
    merged = FakeMergedForwardRepository();
    saved = FakeSavedMessagesRepository();
    clipboard = null;
    chats = thread_test.FakeChatsRepository()
      ..messages = [
        _text('m1', 'user-2', 'Meet at 7?', 10),
        _text('m2', 'user-1', 'Works for me', 11),
        _text('m3', 'user-2', 'Bring snacks', 12),
      ]
      ..conversations = const [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          unreadCount: 0,
          title: 'Ada Lovelace',
          directUserId: 'user-2',
        ),
        ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.group,
          unreadCount: 0,
          title: 'Climbing crew',
        ),
        ConversationSummary(
          id: 'channel-1',
          type: ConversationType.channel,
          unreadCount: 0,
          title: 'general',
        ),
      ];
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        mergedForwardRepositoryProvider.overrideWithValue(merged),
        savedMessagesRepositoryProvider.overrideWithValue(saved),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          thread_test.FakeSettingsRepository(),
        ),
        ...filePreviewOverrides(),
        authRepositoryProvider.overrideWithValue(
          thread_test.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: const MaterialApp(
        home: ChatThreadScreen(
          conversationId: 'conversation-1',
          title: 'Ada Lovelace',
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String text) async {
    await tester.longPress(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-select')));
    await tester.pumpAndSettle();
  }

  Finder countText(int count) => find.text('$count selected');

  group('entering and leaving', () {
    testWidgets('Select in the menu starts selection with that message', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);

      await select(tester, 'Meet at 7?');

      expect(countText(1), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-cancel')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-selection-bar')), findsOneWidget);
      // The composer is replaced by the bar.
      expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);
      expect(find.byKey(const ValueKey('selection-check-on')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('selection-check-off')),
        findsNWidgets(2),
      );
    });

    testWidgets('tapping messages ticks and unticks them', (tester) async {
      await open(tester);
      await select(tester, 'Meet at 7?');

      await tester.tap(find.text('Bring snacks'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(countText(2), findsOneWidget);

      await tester.tap(find.text('Bring snacks'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(countText(1), findsOneWidget);

      // Messages do nothing else meanwhile: no menu on a long press.
      await tester.longPress(find.text('Works for me'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-select')), findsNothing);
    });

    testWidgets('Cancel leaves selection mode', (tester) async {
      await open(tester);
      await select(tester, 'Meet at 7?');

      await tester.tap(find.byKey(const ValueKey('selection-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-selection-bar')), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-check-on')), findsNothing);
    });

    testWidgets('Esc leaves selection mode', (tester) async {
      await open(tester);
      await select(tester, 'Meet at 7?');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-selection-bar')), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
    });

    testWidgets('Shift-click ticks everything from the last one ticked', (
      tester,
    ) async {
      await open(tester);
      await select(tester, 'Meet at 7?');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Bring snacks'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(countText(3), findsOneWidget);
    });
  });

  group('on a desktop', () {
    void useDesktop(WidgetTester tester) {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    }

    testWidgets('right-click Select, Shift-click a range, Esc', (tester) async {
      useDesktop(tester);
      await open(tester);

      await tester.tap(
        find.text('Meet at 7?'),
        buttons: kSecondaryButton,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-select')));
      await tester.pumpAndSettle();

      // The flat bar and header of the wide layout.
      expect(
        find.byKey(const ValueKey('chat-selection-header')),
        findsOneWidget,
      );
      expect(countText(1), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-merge')), findsOneWidget);
      expect(find.text('Merge & forward'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Bring snacks'), warnIfMissed: false);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(countText(3), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-selection-header')), findsNothing);
      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('albums', () {
    testWidgets('pictures sent together are ticked as one', (tester) async {
      chats.messages = [
        for (var i = 1; i <= 3; i++)
          ChatMessage(
            id: 'p$i',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.image,
            body: '',
            createdAt: DateTime.utc(2026, 5, 18, 4, 20, i),
            attachmentGroupId: 'album-1',
            attachment: ImageAttachment(
              bucket: 'chat-images',
              path: 'conversation-1/p$i.jpg',
              mimeType: 'image/jpeg',
              size: 1000,
              width: 800,
              height: 600,
            ).toJson(),
          ),
        _text('m1', 'user-2', 'Meet at 7?', 30),
      ];
      await open(tester);

      await tester.longPress(find.byType(MediaTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-select')));
      await tester.pumpAndSettle();

      expect(countText(3), findsOneWidget);
      // One check box for the album, not one per picture.
      expect(find.byKey(const ValueKey('selection-check-on')), findsOneWidget);
      await tester.tap(find.byType(MediaTile).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(countText(0), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('every message is a labelled check box', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester);
      await select(tester, 'Meet at 7?');

      for (final (text, checked) in [
        ('Meet at 7?', true),
        ('Works for me', false),
        ('Bring snacks', false),
      ]) {
        final node = tester.getSemantics(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('Select message') ??
                    false) &&
                widget.properties.label!.contains(text),
          ),
        );
        final flags = node.getSemanticsData().flagsCollection;
        expect(
          flags.isChecked,
          checked ? ui.CheckedState.isTrue : ui.CheckedState.isFalse,
          reason: text,
        );
        expect(node.label, startsWith('Select message'));
        expect(node.label, contains(text));
      }
      semantics.dispose();
    });
  });

  group('the bar', () {
    testWidgets('Forward sends the messages one by one, oldest first', (
      tester,
    ) async {
      await open(tester);
      await select(tester, 'Bring snacks');
      await tester.tap(find.text('Meet at 7?'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('selection-forward')));
      await tester.pumpAndSettle();
      expect(find.text('Forward to'), findsOneWidget);
      // Channels and the chat itself are not offered... the group is.
      await tester.tap(
        find.byKey(const ValueKey('forward-target-conversation-2')),
      );
      await tester.pumpAndSettle();

      expect(chats.forwardedMessages.map((f) => f.sourceMessageId), [
        'm1',
        'm3',
      ]);
      expect(
        chats.forwardedMessages.map((f) => f.targetConversationId).toSet(),
        {'conversation-2'},
      );
      expect(find.text('2 messages forwarded'), findsOneWidget);
      // Done: back to the composer.
      expect(find.byKey(const ValueKey('chat-selection-bar')), findsNothing);
    });

    testWidgets('Merge & forward sends one chat history to chats only', (
      tester,
    ) async {
      await open(tester);
      await select(tester, 'Bring snacks');
      await tester.tap(find.text('Works for me'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Meet at 7?'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('selection-merge')));
      await tester.pumpAndSettle();
      expect(find.text('Merge & forward to'), findsOneWidget);
      expect(
        find.text('3 messages will be sent as one chat history.'),
        findsOneWidget,
      );
      // A circle channel takes no chat history.
      expect(
        find.byKey(const ValueKey('forward-target-channel-1')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('forward-target-conversation-2')),
      );
      await tester.pumpAndSettle();

      expect(merged.forwards, hasLength(1));
      expect(merged.forwards.single.ids, ['m1', 'm2', 'm3']);
      expect(merged.forwards.single.target, 'conversation-2');
      expect(merged.forwards.single.title, 'Ada Lovelace');
      expect(chats.forwardedMessages, isEmpty);
      expect(find.text('Chat history sent'), findsOneWidget);
    });

    testWidgets('a refused merge says why and stays', (tester) async {
      merged.failWith = const MergedForwardException(
        MergedForwardRefusal.someMessages,
      );
      await open(tester);
      await select(tester, 'Meet at 7?');
      await tester.tap(find.byKey(const ValueKey('selection-merge')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('forward-target-conversation-2')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('cannot be forwarded'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('forward-target-conversation-2')),
        findsOneWidget,
      );
    });

    testWidgets('Save saves every selected message', (tester) async {
      await open(tester);
      await select(tester, 'Meet at 7?');
      await tester.tap(find.text('Bring snacks'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('selection-save')));
      await tester.pumpAndSettle();

      expect(saved.saved, ['m1', 'm3']);
      expect(find.text('2 messages saved'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-selection-bar')), findsNothing);
    });

    testWidgets('Copy puts the words on the clipboard', (tester) async {
      await open(tester);
      await select(tester, 'Meet at 7?');

      await tester.tap(find.byKey(const ValueKey('selection-copy')));
      await tester.pumpAndSettle();
      expect(clipboard, 'Meet at 7?');
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await select(tester, 'Meet at 7?');
      await tester.tap(find.text('Works for me'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('selection-copy')));
      await tester.pumpAndSettle();
      expect(clipboard, 'Ada Lovelace: Meet at 7?\nYou: Works for me');
    });

    testWidgets('Delete takes only my own messages, after asking', (
      tester,
    ) async {
      await open(tester);
      await select(tester, 'Works for me');
      expect(_enabled(tester, 'selection-delete'), isTrue);

      // Someone else's message in the selection turns Delete off.
      await tester.tap(find.text('Meet at 7?'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'selection-delete'), isFalse);
      await tester.tap(find.text('Meet at 7?'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('selection-delete')));
      await tester.pumpAndSettle();
      expect(
        find.text('Delete this message for everyone? This cannot be undone.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('selection-delete-confirm')));
      await tester.pumpAndSettle();

      expect(chats.recalledMessageIds, ['m2']);
      expect(find.byKey(const ValueKey('chat-selection-bar')), findsNothing);
    });

    testWidgets('a moderator can delete everything', (tester) async {
      chats.canModerateMessagesValue = true;
      await open(tester);
      await select(tester, 'Meet at 7?');
      await tester.tap(find.text('Works for me'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bring snacks'), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('selection-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 3 messages'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('selection-delete-confirm')));
      await tester.pumpAndSettle();

      expect(chats.recalledMessageIds, ['m1', 'm2', 'm3']);
    });

    testWidgets('cancelling the delete dialog keeps everything', (
      tester,
    ) async {
      await open(tester);
      await select(tester, 'Works for me');
      await tester.tap(find.byKey(const ValueKey('selection-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(chats.recalledMessageIds, isEmpty);
      expect(find.byKey(const ValueKey('chat-selection-bar')), findsOneWidget);
    });
  });
}

/// Whether the bar's button [key] can be pressed.
bool _enabled(WidgetTester tester, String key) {
  return tester
      .widget<WeCordPressable>(
        find.descendant(
          of: find.descendant(
            of: find.byKey(const ValueKey('chat-selection-bar')),
            matching: find.byKey(ValueKey(key)),
          ),
          matching: find.byType(WeCordPressable),
        ),
      )
      .enabled;
}
