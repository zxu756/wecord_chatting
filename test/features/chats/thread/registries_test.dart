import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_builtin.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu.dart';
import 'package:wecord/features/chats/thread/registry/composer_menu_builtin.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/thread/registry/header_actions_builtin.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_builtin.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

ChatMessage _message({DateTime? editedAt}) => ChatMessage(
  id: 'm1',
  conversationId: 'c1',
  senderId: 'u1',
  type: MessageType.text,
  body: 'hello',
  createdAt: DateTime.utc(2026, 10, 18),
  editedAt: editedAt,
);

Future<void> _noop() async {}

Future<BuildContext> _context(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('message action registry', () {
    test('the built-in actions keep the menu order', () {
      expect(MessageActionRegistry(builtInMessageActions).ids, [
        'reply',
        'copy',
        'forward',
        'translate',
        'transcribe',
        'edit',
        'create-task',
        'pin',
        'thread',
        'remind',
        'save',
        'select',
        'preview-image',
        'copy-image-text',
        'publish',
        'remove-embed',
        'delete',
      ]);
    });

    testWidgets('contributions are collected by order, then by position', (
      tester,
    ) async {
      final context = await _context(tester);
      MessageActionContribution contribution(
        String id,
        int order,
        String label,
      ) => MessageActionContribution(
        id: id,
        order: order,
        build: (ctx) => [
          MessageAction(icon: Icons.add, label: label, onSelected: () {}),
        ],
      );
      final registry = MessageActionRegistry([
        contribution('c', 300, 'C'),
        contribution('a', 100, 'A'),
        MessageActionContribution(
          id: 'none',
          order: 150,
          build: (ctx) => const [],
        ),
        contribution('b2', 200, 'B2'),
        contribution('b1', 200, 'B1'),
      ]);
      final ctx = MessageActionContext(
        context: context,
        message: _message(),
        isCurrentUser: true,
        canCompose: true,
        canPin: false,
        canStartThread: false,
        canModerate: false,
        isSaved: false,
        circleId: null,
        previewUrl: null,
        onReply: (_) {},
        onEdit: (_) {},
        onForward: (_) {},
        onDelete: (_) async {},
        onPreviewImage: (_) async {},
        onTogglePin: (_) async {},
        onRemoveEmbed: (_) async {},
      );
      expect(
        [for (final action in registry.actionsFor(ctx)) action.label],
        ['A', 'B2', 'B1', 'C'],
      );
    });
  });

  group('bubble footer registry', () {
    test('the built-in entries keep their order', () {
      final registry = BubbleFooterRegistry(builtInBubbleFooterEntries);
      expect(registry.ids, [
        'task-chip',
        'link-preview',
        'edited',
        'thread-chip',
        'published',
        'reactions',
        'disappearing',
        'review',
        'read-receipt',
      ]);
    });

    testWidgets('inside and below entries are split and ordered', (
      tester,
    ) async {
      final context = await _context(tester);
      final registry = BubbleFooterRegistry([
        BubbleFooterEntry.below(
          id: 'late',
          order: 200,
          build: (ctx) => const Text('late'),
        ),
        BubbleFooterEntry.below(
          id: 'early',
          order: 100,
          wrap: BubbleFooterWrap.pill,
          build: (ctx) => const Text('early'),
        ),
        BubbleFooterEntry.below(id: 'none', order: 150, build: (ctx) => null),
        BubbleFooterEntry.inside(
          id: 'inside',
          order: 100,
          build: (ctx) => [const Text('inside')],
        ),
      ]);
      final ctx = BubbleFooterContext(
        context: context,
        message: _message(),
        isCurrentUser: false,
        cards: false,
        desktop: false,
        textColor: Colors.black,
        previewUrl: null,
        showReadReceipt: false,
        onToggleReaction: (_, _) async {},
        onShowReactors: (_, _) {},
      );
      expect(registry.inside(ctx), hasLength(1));
      final below = registry.below(ctx);
      expect([for (final item in below) item.entry.id], ['early', 'late']);
      expect(below.first.entry.wrap, BubbleFooterWrap.pill);
    });

    testWidgets('edited shows only for an edited message', (tester) async {
      final context = await _context(tester);
      final registry = BubbleFooterRegistry(builtInBubbleFooterEntries);
      BubbleFooterContext ctxFor(ChatMessage message) => BubbleFooterContext(
        context: context,
        message: message,
        isCurrentUser: true,
        cards: false,
        desktop: false,
        textColor: Colors.black,
        previewUrl: null,
        showReadReceipt: false,
        onToggleReaction: (_, _) async {},
        onShowReactors: (_, _) {},
      );
      // The task chip is always there; "edited" adds a gap and the mark.
      final plain = registry.inside(ctxFor(_message()));
      final edited = registry.inside(
        ctxFor(_message(editedAt: DateTime.utc(2026, 10, 19))),
      );
      expect(edited.length, plain.length + 2);
    });
  });

  group('composer menu registry', () {
    final actions = ComposerMenuActions(
      pickPhotosAndVideos: _noop,
      pickFiles: _noop,
      createPoll: _noop,
      createChain: _noop,
      sendContactCard: _noop,
      sendLocation: _noop,
      shareLiveLocation: _noop,
      scheduleMessage: _noop,
      insertTime: _noop,
      showEvents: _noop,
      changeWallpaper: () {},
      pickSticker: _noop,
      pickGif: _noop,
    );

    Future<List<String>> labels(
      WidgetTester tester,
      ConversationType type, {
      required bool compact,
    }) async {
      final context = await _context(tester);
      final registry = ComposerMenuRegistry(builtInComposerMenu);
      return [
        for (final entry in registry.entriesFor(
          ComposerMenuContext(
            context: context,
            conversationId: 'c1',
            conversationType: type,
            compact: compact,
            gifAvailable: true,
            actions: actions,
          ),
        ))
          entry.label,
      ];
    }

    testWidgets('a direct chat on a phone', (tester) async {
      expect(await labels(tester, ConversationType.direct, compact: true), [
        'Photos and videos',
        'Files',
        'Create poll',
        'Contact card',
        'Location',
        'Share live location',
        'Schedule message',
        'Insert time',
        'Events',
        'Send sticker',
        'Send GIF',
      ]);
    });

    testWidgets('a group on a wide screen', (tester) async {
      expect(await labels(tester, ConversationType.group, compact: false), [
        'Photos and videos',
        'Files',
        'Create poll',
        'Chain',
        'Contact card',
        'Location',
        'Share live location',
        'Schedule message',
        'Insert time',
        'Events',
        'Wallpaper',
        'Send sticker',
      ]);
    });

    testWidgets('a channel on a phone', (tester) async {
      expect(await labels(tester, ConversationType.channel, compact: true), [
        'Photos and videos',
        'Files',
        'Create poll',
        'Chain',
        'Contact card',
        'Location',
        'Schedule message',
        'Insert time',
        'Send sticker',
        'Send GIF',
      ]);
    });
  });

  group('header action registry', () {
    test('the built-in actions keep the More menu order', () {
      expect(HeaderActionRegistry(builtInHeaderActions).ids, [
        'search',
        'call',
        'video-call',
        'pinned',
        'notes',
        'lists',
        'disappearing',
        'wallpaper',
        'media',
        'group-details',
        'archive',
        'summarize',
        'events',
      ]);
    });

    test('the parent\'s extra actions sit before order 1500 and after', () {
      ChatThreadAction action(String id) => ChatThreadAction(
        id: id,
        tooltip: id,
        icon: Icons.add,
        onPressed: null,
      );
      HeaderActionContribution contribution(String id, int order) =>
          HeaderActionContribution(
            id: id,
            order: order,
            build: (ctx) => id == 'skipped' ? null : action(id),
          );
      final registry = HeaderActionRegistry([
        contribution('events', 2000),
        contribution('skipped', 50),
        contribution('search', 100),
        contribution('media', 900),
      ]);
      // A real context is not needed: these contributions ignore it.
      final result = registry.actionsFor(
        _FakeHeaderContext(),
        extras: [action('extra')],
      );
      expect(
        [for (final a in result) a.id],
        ['search', 'media', 'extra', 'events'],
      );
    });
  });
}

class _FakeHeaderContext implements HeaderActionContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
