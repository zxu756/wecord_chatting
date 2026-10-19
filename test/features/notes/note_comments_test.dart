import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_comments_controller.dart';
import 'package:wecord/features/notes/note_comments_panel.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'notes2_fakes.dart';

var _ids = 0;

NoteCommentsController newComments(FakeNotes2Repository repository) {
  return NoteCommentsController(
    repository: repository,
    noteId: 'note-plan',
    newId: () => 'new-${_ids++}',
    reloadDelay: const Duration(milliseconds: 10),
  );
}

void main() {
  group('threads', () {
    test('group replies under their comment, oldest first', () {
      final threads = groupCommentThreads([
        sampleComment('a', at: DateTime(2026, 10, 24, 9)),
        sampleComment('b', at: DateTime(2026, 10, 24, 9, 5)),
        sampleComment('r2', parentId: 'a', at: DateTime(2026, 10, 24, 9, 30)),
        sampleComment('r1', parentId: 'a', at: DateTime(2026, 10, 24, 9, 10)),
        // A reply whose comment is hidden or gone is left out.
        sampleComment('lost', parentId: 'zzz'),
      ]);
      expect(threads.map((t) => t.root.id), ['a', 'b']);
      expect(threads.first.replies.map((r) => r.id), ['r1', 'r2']);
      expect(threads.first.length, 3);
      expect(threads.first.lastActivity, DateTime(2026, 10, 24, 9, 30));
      expect(threads.last.lastActivity, DateTime(2026, 10, 24, 9, 5));
    });

    test('anchor only where the words are still the same', () {
      const block = NoteBlock(id: 'b1', pos: 'a', text: 'Hello plan world');
      final comment = sampleComment(
        'c',
        blockId: 'b1',
        start: 6,
        end: 10,
        quote: 'plan',
      );
      final anchor = anchorIn(block, comment);
      expect(anchor?.start, 6);
      expect(anchor?.end, 10);
      expect(
        anchorIn(block.copyWith(text: 'Hello PLAN world'), comment),
        isNull,
      );
      expect(anchorIn(block.copyWith(text: 'Hi'), comment), isNull);
      expect(anchorIn(const NoteBlock(id: 'other', pos: 'a'), comment), isNull);
      // A comment on a whole block has no stretch to highlight.
      expect(anchorIn(block, sampleComment('d', blockId: 'b1')), isNull);
    });
  });

  group('the controller', () {
    test('loads, adds, replies, resolves and deletes', () async {
      final repository = FakeNotes2Repository();
      repository.comments.add(
        sampleComment('c1', blockId: 'b1', start: 0, end: 5, quote: 'Hello'),
      );
      final controller = newComments(repository);
      await controller.open();
      expect(controller.loading, isFalse);
      expect(controller.canComment, isTrue);
      expect(controller.openCount, 1);
      expect(controller.openThreadsOn('b1'), hasLength(1));
      expect(controller.openThreadsOn('other'), isEmpty);

      final added = await controller.add(
        'On the note',
        mentions: const ['user-2'],
      );
      expect(controller.comments, hasLength(2));
      expect(repository.mentionsSent.last, ['user-2']);
      expect(added.id, startsWith('new-'));

      await controller.reply(controller.comments.first, 'Agreed');
      expect(controller.threads.first.replies, hasLength(1));
      // A reply to a reply goes under the same comment.
      await controller.reply(controller.threads.first.replies.first, 'Thanks');
      expect(controller.threads.first.replies, hasLength(2));

      await controller.setResolved(controller.comments.first, true);
      expect(controller.openCount, 1);
      expect(controller.resolvedThreads, hasLength(1));
      await controller.setResolved(
        controller.resolvedThreads.first.root,
        false,
      );
      expect(controller.openCount, 2);

      await controller.delete(controller.threads.first.root);
      expect(controller.comments.map((c) => c.id), [added.id]);
      controller.dispose();
    });

    test('hears of comments from others and reloads', () async {
      final repository = FakeNotes2Repository();
      final controller = newComments(repository);
      await controller.open();
      expect(controller.comments, isEmpty);
      repository.comments.add(sampleComment('late'));
      repository.changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.comments.map((c) => c.id), ['late']);
      controller.dispose();
    });

    test('says so when the comments cannot be loaded', () async {
      final repository = FakeNotes2Repository()..failComments = true;
      final controller = newComments(repository);
      await controller.open();
      expect(controller.error, isNotNull);
      expect(controller.loading, isFalse);
      repository.failComments = false;
      await controller.refresh();
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('a person who may not comment is told so', () async {
      final repository = FakeNotes2Repository()..canCommentValue = false;
      final controller = newComments(repository);
      await controller.open();
      expect(controller.canComment, isFalse);
      controller.dispose();
    });

    test('the open comments mark their words in a block', () async {
      final repository = FakeNotes2Repository();
      repository.comments
        ..add(
          sampleComment('c1', blockId: 'b1', start: 6, end: 10, quote: 'plan'),
        )
        ..add(
          sampleComment(
            'c2',
            blockId: 'b1',
            start: 0,
            end: 5,
            quote: 'Hello',
            resolvedAt: DateTime(2026, 10, 24, 13),
          ),
        );
      final controller = newComments(repository);
      await controller.open();
      const block = NoteBlock(id: 'b1', pos: 'a', text: 'Hello plan world');
      final anchors = controller.anchorsFor(block);
      expect(anchors.map((a) => (a.start, a.end)), [(6, 10)]);
      controller.dispose();
    });
  });

  group('the panel', () {
    final members = [
      GroupMember(
        profile: Profile(
          id: 'user-2',
          username: 'grace',
          displayName: 'Grace Hopper',
          bio: '',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        role: 'member',
      ),
    ];

    Future<NoteCommentsController> open(
      WidgetTester tester,
      FakeNotes2Repository repository, {
      bool canComment = true,
    }) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = newComments(repository);
      await tester.runAsync(controller.open);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: NoteCommentsPanel(
              controller: controller,
              members: members,
              canComment: canComment,
            ),
          ),
        ),
      );
      await tester.pump();
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('lists open threads with their quote and replies', (
      tester,
    ) async {
      final repository = FakeNotes2Repository();
      repository.comments
        ..add(
          sampleComment(
            'c1',
            body: 'Is this final?',
            blockId: 'b1',
            start: 0,
            end: 4,
            quote: 'Pack',
          ),
        )
        ..add(sampleComment('r1', parentId: 'c1', body: 'Yes', author: 'Bo'))
        ..add(
          sampleComment(
            'c2',
            body: 'Old question',
            resolvedAt: DateTime(2026, 10, 24, 13),
          ),
        );
      await open(tester, repository);
      expect(find.text('Is this final?'), findsOneWidget);
      expect(find.text('Pack'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('Old question'), findsNothing);
      expect(find.text('Open (1)'), findsOneWidget);
      expect(find.text('Resolved (1)'), findsOneWidget);
      await tester.tap(find.text('Resolved (1)'));
      await tester.pump();
      expect(find.text('Old question'), findsOneWidget);
      expect(find.text('Resolved by Ada Lovelace'), findsOneWidget);
      expect(find.text('Is this final?'), findsNothing);
    });

    testWidgets('resolving moves a thread to the resolved tab', (tester) async {
      final repository = FakeNotes2Repository();
      repository.comments.add(sampleComment('c1', body: 'Is this final?'));
      await open(tester, repository);
      await tester.tap(find.text('Resolve'));
      await tester.pump();
      await tester.pump();
      expect(repository.calls, contains('resolve'));
      expect(find.text('Is this final?'), findsNothing);
      expect(find.text('Resolved (1)'), findsOneWidget);
    });

    testWidgets('a reply goes under the thread', (tester) async {
      final repository = FakeNotes2Repository();
      repository.comments.add(sampleComment('c1', body: 'Is this final?'));
      await open(tester, repository);
      await tester.tap(find.text('Reply'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('note-comment-field')).first,
        'Yes!',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-comment-send')).first);
      await tester.pump();
      await tester.pump();
      final reply = repository.comments.last;
      expect(reply.parentId, 'c1');
      expect(reply.body, 'Yes!');
      expect(find.text('Yes!'), findsOneWidget);
    });

    testWidgets('mentions are picked from the note\'s people', (tester) async {
      final repository = FakeNotes2Repository();
      await open(tester, repository);
      final field = find.byKey(const ValueKey('note-comment-field'));
      await tester.enterText(field, 'Hi @gra');
      await tester.pump();
      expect(find.byKey(const ValueKey('note-mention-user-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-mention-user-2')));
      await tester.pump();
      await tester.enterText(field, 'Hi @Grace Hopper can you check?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-comment-send')));
      await tester.pump();
      await tester.pump();
      expect(
        repository.comments.single.body,
        'Hi @Grace Hopper can you check?',
      );
      expect(repository.mentionsSent.single, ['user-2']);
    });

    testWidgets('a mention deleted from the text is not sent', (tester) async {
      final repository = FakeNotes2Repository();
      await open(tester, repository);
      final field = find.byKey(const ValueKey('note-comment-field'));
      await tester.enterText(field, '@gra');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-mention-user-2')));
      await tester.pump();
      await tester.enterText(field, 'never mind');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-comment-send')));
      await tester.pump();
      await tester.pump();
      expect(repository.mentionsSent.single, isEmpty);
    });

    testWidgets('a failed send says so and keeps the words', (tester) async {
      final repository = FakeNotes2Repository()..failWrites = true;
      await open(tester, repository);
      final field = find.byKey(const ValueKey('note-comment-field'));
      await tester.enterText(field, 'Important');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-comment-send')));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Could not send the comment. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Important'), findsOneWidget);
    });

    testWidgets('a reader who cannot comment sees no box', (tester) async {
      final repository = FakeNotes2Repository()..canCommentValue = false;
      repository.comments.add(sampleComment('c1', body: 'Seen'));
      await open(tester, repository, canComment: false);
      expect(find.text('Seen'), findsOneWidget);
      expect(find.byKey(const ValueKey('note-comment-field')), findsNothing);
      expect(find.text('Reply'), findsNothing);
    });

    testWidgets('only what the server allows can be edited or deleted', (
      tester,
    ) async {
      final repository = FakeNotes2Repository();
      repository.comments
        ..add(
          sampleComment('mine', body: 'Mine', canEdit: true, canDelete: true),
        )
        ..add(sampleComment('theirs', body: 'Theirs'));
      await open(tester, repository);
      expect(find.byTooltip('Comment options'), findsOneWidget);
      await tester.tap(find.byTooltip('Comment options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-comment-field')).first,
        'Mine, better',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-comment-send')).first);
      await tester.pump();
      await tester.pump();
      expect(repository.calls, contains('edit'));
      expect(find.text('Mine, better'), findsOneWidget);
      expect(find.text('edited', skipOffstage: false), findsNothing);
    });

    testWidgets('an empty list explains how to start', (tester) async {
      await open(tester, FakeNotes2Repository());
      expect(find.textContaining('Select some words'), findsOneWidget);
    });

    testWidgets('a list that cannot load offers to try again', (tester) async {
      final repository = FakeNotes2Repository()..failComments = true;
      await open(tester, repository);
      expect(find.text('Could not load the comments.'), findsOneWidget);
      repository.failComments = false;
      repository.comments.add(sampleComment('c1', body: 'Back again'));
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Back again'), findsOneWidget);
    });
  });
}
