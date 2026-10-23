import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_registrations.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_providers.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';
import 'package:wecord/features/group_space/space_actions.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import 'group_space_fakes.dart';

ChatMessage _image(
  String id, {
  String conversation = 'conversation-1',
  Map<String, dynamic>? extra,
  DateTime? expiresAt,
  List<ChatMessage>? album,
  MessageType type = MessageType.image,
  DateTime? recalledAt,
}) {
  final isImage = type == MessageType.image;
  return ChatMessage(
    id: id,
    conversationId: conversation,
    senderId: 'user-2',
    type: type,
    body: '',
    createdAt: DateTime.utc(2026, 10, 20, 9),
    expiresAt: expiresAt,
    album: album,
    recalledAt: recalledAt,
    attachment: {
      'kind': isImage ? 'image' : 'video',
      'bucket': isImage ? 'chat-images' : 'chat-files',
      'path': '$conversation/$id.${isImage ? 'jpg' : 'mp4'}',
      'mime_type': isImage ? 'image/jpeg' : 'video/mp4',
      'size': 1000,
      ...?extra,
    },
  );
}

ChatMessage _file(String id) => ChatMessage(
  id: id,
  conversationId: 'conversation-1',
  senderId: 'user-2',
  type: MessageType.file,
  body: '',
  createdAt: DateTime.utc(2026, 10, 20, 9),
  attachment: {
    'kind': 'file',
    'bucket': 'chat-files',
    'path': 'conversation-1/$id.pdf',
    'name': 'plan.pdf',
    'mime_type': 'application/pdf',
    'size': 2000,
  },
);

void main() {
  /// The labels the menu would show for [message] once the page has loaded
  /// what the space allows.
  Future<List<String>> menuFor(
    WidgetTester tester,
    ChatMessage message, {
    GroupSpaceInfo? info,
    bool loaded = true,
    String? circleId,
  }) async {
    final world = GroupSpaceWorld(
      repository: FakeGroupSpaceRepository(
        info:
            info ??
            const GroupSpaceInfo(supported: true, canAdd: true, canTidy: true),
      ),
    );
    late BuildContext captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: world.overrides,
        child: MaterialApp(
          theme: WeCordTheme.light(),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(captured);
    if (loaded) {
      // The header keeps this loaded while the page is open.
      container.listen(
        groupSpaceInfoProvider('conversation-1'),
        (previous, next) {},
      );
      await tester.pumpAndSettle();
    }
    final ctx = MessageActionContext(
      context: captured,
      message: message,
      isCurrentUser: false,
      canCompose: true,
      canPin: false,
      canStartThread: false,
      canModerate: false,
      isSaved: false,
      circleId: circleId,
      previewUrl: null,
      onReply: (_) {},
      onEdit: (_) {},
      onForward: (_) {},
      onDelete: (_) async {},
      onPreviewImage: (_) async {},
      onTogglePin: (_) async {},
      onRemoveEmbed: (_) async {},
    );
    return [
      for (final contribution in [addToAlbumAction, saveToGroupFilesAction])
        for (final action in contribution.build(ctx)) action.label,
    ];
  }

  group('the message menu', () {
    testWidgets('a picture can go in an album and in the group files', (
      tester,
    ) async {
      expect(await menuFor(tester, _image('m1')), [
        'Add to album',
        'Save to group files',
      ]);
    });

    testWidgets('a video the same, a file only to the files', (tester) async {
      expect(await menuFor(tester, _image('m1', type: MessageType.file)), [
        'Add to album',
        'Save to group files',
      ]);
      expect(await menuFor(tester, _file('m2')), ['Save to group files']);
    });

    testWidgets('nothing before the page has loaded what the space allows', (
      tester,
    ) async {
      expect(await menuFor(tester, _image('m1'), loaded: false), isEmpty);
    });

    testWidgets('nothing in a chat without a space or when adding is off', (
      tester,
    ) async {
      expect(
        await menuFor(tester, _image('m1'), info: const GroupSpaceInfo()),
        isEmpty,
      );
      expect(
        await menuFor(
          tester,
          _image('m1'),
          info: const GroupSpaceInfo(
            supported: true,
            enabled: false,
            canAdd: false,
            canTidy: true,
          ),
        ),
        isEmpty,
      );
      expect(
        await menuFor(
          tester,
          _image('m1'),
          info: const GroupSpaceInfo(supported: true),
        ),
        isEmpty,
      );
    });

    testWidgets('nothing for what cannot be kept', (tester) async {
      // View-once.
      expect(
        await menuFor(tester, _image('m1', extra: {'view_once': true})),
        isEmpty,
      );
      // Expiring.
      expect(
        await menuFor(
          tester,
          _image('m1', expiresAt: DateTime.utc(2026, 10, 21)),
        ),
        isEmpty,
      );
      // Deleted.
      expect(
        await menuFor(
          tester,
          _image('m1', recalledAt: DateTime.utc(2026, 10, 21)),
        ),
        isEmpty,
      );
      // From another chat (a forwarded picture keeps the file there).
      expect(
        await menuFor(
          tester,
          ChatMessage(
            id: 'm9',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.image,
            body: '',
            createdAt: DateTime.utc(2026, 10, 20),
            attachment: const {
              'kind': 'image',
              'bucket': 'chat-images',
              'path': 'conversation-2/elsewhere.jpg',
              'mime_type': 'image/jpeg',
              'size': 10,
            },
          ),
        ),
        isEmpty,
      );
      // A text message.
      expect(
        await menuFor(
          tester,
          ChatMessage(
            id: 'm10',
            conversationId: 'conversation-1',
            senderId: 'user-2',
            type: MessageType.text,
            body: 'hello',
            createdAt: DateTime.utc(2026, 10, 20),
          ),
        ),
        isEmpty,
      );
    });

    testWidgets('not in a circle channel', (tester) async {
      expect(
        await menuFor(tester, _image('m1'), circleId: 'circle-1'),
        isEmpty,
      );
    });
  });

  group('registrations', () {
    test('the entries are registered between Forward and Translate', () {
      expect(
        messageActionExtensions.map((c) => c.id),
        containsAll(['add-to-album', 'save-to-group-files']),
      );
      expect(addToAlbumAction.order, inInclusiveRange(301, 399));
      expect(saveToGroupFilesAction.order, inInclusiveRange(301, 399));
      expect(addToAlbumAction.order, lessThan(saveToGroupFilesAction.order));
      expect(headerActionExtensions.map((c) => c.id), contains('group-space'));
    });
  });

  group('the header', () {
    testWidgets('a group chat lists the space in its More menu', (
      tester,
    ) async {
      final world = PhoneWorld();
      final space = GroupSpaceWorld();
      world.extraOverrides = [
        groupSpaceRepositoryProvider.overrideWithValue(space.repository),
      ];
      usePhoneViewport(tester, notchedPhone);
      await world.open(
        tester,
        '/chats/group-1',
        extra: ChatThreadRouteExtra(
          title: groupDetail.title,
          type: ConversationType.group,
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Group space'), findsOneWidget);
    });

    testWidgets('a direct chat does not', (tester) async {
      final world = PhoneWorld();
      final space = GroupSpaceWorld();
      world.extraOverrides = [
        groupSpaceRepositoryProvider.overrideWithValue(space.repository),
      ];
      usePhoneViewport(tester, notchedPhone);
      await world.open(
        tester,
        '/chats/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Group space'), findsNothing);
      expect(find.text('Media'), findsOneWidget);
    });
  });
}
