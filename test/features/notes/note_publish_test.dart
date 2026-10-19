import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_publish_sheet.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/features/notes/public/public_note_screen.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'notes2_fakes.dart';

final token = List.filled(48, 'a').join();

Future<void> pumpApp(
  WidgetTester tester,
  Widget home,
  List<Override> overrides, {
  Size size = const Size(800, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: noProviderRetry,
      overrides: overrides,
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('links', () {
    test('only a 48 digit lowercase hex token is a token', () {
      expect(isPublicNoteToken(token), isTrue);
      expect(isPublicNoteToken(token.toUpperCase()), isFalse);
      expect(isPublicNoteToken('${token}0'), isFalse);
      expect(isPublicNoteToken(token.substring(1)), isFalse);
      expect(isPublicNoteToken('${token.substring(1)}g'), isFalse);
    });

    test('the link is on the site and the route is /n/<token>', () {
      expect(publicNotePath(token), '/n/$token');
      expect(
        publicNoteUrl(token, site: 'https://wecord.jokebear.fyi'),
        'https://wecord.jokebear.fyi/n/$token',
      );
    });

    test('a browser address finds the page, nothing else does', () {
      expect(
        publicNoteLocationFor(Uri.parse('https://x.test/n/$token')),
        '/n/$token',
      );
      expect(
        publicNoteLocationFor(Uri.parse('https://x.test/n/$token/')),
        '/n/$token',
      );
      expect(
        publicNoteLocationFor(Uri.parse('https://x.test/n/short')),
        isNull,
      );
      expect(
        publicNoteLocationFor(Uri.parse('https://x.test/c/$token')),
        isNull,
      );
      expect(publicNoteLocationFor(Uri.parse('https://x.test/')), isNull);
      // The app's own routes live after a '#'.
      expect(
        publicNoteLocationFor(Uri.parse('https://x.test/n/$token#/home')),
        isNull,
      );
    });

    test('only web links are followed', () {
      expect(isSafeWebLink('https://example.com/a'), isTrue);
      expect(isSafeWebLink('http://example.com'), isTrue);
      expect(isSafeWebLink('javascript:alert(1)'), isFalse);
      expect(isSafeWebLink('data:text/html,hi'), isFalse);
      expect(isSafeWebLink('mailto:a@b.c'), isFalse);
      expect(isSafeWebLink('//example.com'), isFalse);
      expect(isSafeWebLink(''), isFalse);
    });
  });

  group('the page model', () {
    test('keeps what it can draw and drops the rest', () {
      final note = PublicNote.fromJson({
        'title': 'Trip',
        'icon': 'x',
        'allow_indexing': true,
        'updated_at': '2026-10-24T09:00:00Z',
        'blocks': [
          {
            'id': '',
            'kind': 'paragraph',
            'text': 'Hello',
            'marks': [
              [0, 5, 'b'],
              [0, 5, 'l:javascript:alert(1)'],
              [0, 5, 'l:https://example.com'],
              [0, 5, 'm:someone'],
              [0, 5, 'zz'],
              ['a', 1],
            ],
            'props': <String, Object?>{},
          },
          'junk',
          {
            'kind': 'image',
            'props': {'name': 'p.png', 'url': 'https://f.test/p'},
          },
        ],
      });
      expect(note.allowIndexing, isTrue);
      expect(note.blocks, hasLength(2));
      expect(note.blocks.first.marks.map((m) => m.type), [
        'b',
        'l:https://example.com',
      ]);
      expect(note.blocks.first.id, 'public-0');
      expect(note.blocks.last.kind, NoteBlockKind.image);
    });
  });

  group('the publish sheet', () {
    testWidgets('says what publishing means before it does it', (tester) async {
      final repository = FakeNotes2Repository();
      await pumpApp(
        tester,
        const NotePublishSheet(
          noteId: 'note-plan',
          siteUrl: 'https://site.test',
        ),
        repository.overrides,
      );
      expect(find.byKey(const ValueKey('publish-warning')), findsOneWidget);
      expect(
        find.textContaining('Anyone who has the link can read this note'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('publish-link')), findsNothing);
      expect(repository.calls, isNot(contains('publish')));
      await tester.tap(find.byKey(const ValueKey('publish-button')));
      await tester.pump();
      await tester.pump();
      expect(repository.calls, contains('publish'));
      // Not for search engines unless the author says so.
      expect(repository.publishedIndexing, [false]);
      expect(find.byKey(const ValueKey('publish-link')), findsOneWidget);
      expect(find.text('https://site.test/n/$token'), findsOneWidget);
    });

    testWidgets('the search engine choice is sent with the publication', (
      tester,
    ) async {
      final repository = FakeNotes2Repository();
      await pumpApp(
        tester,
        const NotePublishSheet(noteId: 'note-plan'),
        repository.overrides,
      );
      await tester.tap(find.byType(WeCordSwitch));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('publish-button')));
      await tester.pump();
      await tester.pump();
      expect(repository.publishedIndexing, [true]);
      expect(repository.publication.allowIndexing, isTrue);
    });

    testWidgets('a published note shows its link, which can be copied', (
      tester,
    ) async {
      final repository = FakeNotes2Repository()
        ..publication = NotePublication(
          published: true,
          canPublish: true,
          canWithdraw: true,
          token: token,
          publishedByName: 'Grace Hopper',
        );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpApp(
        tester,
        const NotePublishSheet(noteId: 'note-plan', siteUrl: 'https://s.test'),
        repository.overrides,
      );
      expect(find.text('Published by Grace Hopper'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(copied, 'https://s.test/n/$token');
    });

    testWidgets('stopping asks first, then the link is gone', (tester) async {
      final repository = FakeNotes2Repository()
        ..publication = NotePublication(
          published: true,
          canPublish: true,
          canWithdraw: true,
          token: token,
        );
      await pumpApp(
        tester,
        const NotePublishSheet(noteId: 'note-plan'),
        repository.overrides,
      );
      await tester.tap(find.byKey(const ValueKey('unpublish-button')));
      await tester.pumpAndSettle();
      expect(find.text('Stop sharing this page?'), findsOneWidget);
      // Cancelling changes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls, isNot(contains('unpublish')));
      await tester.tap(find.byKey(const ValueKey('unpublish-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop sharing').last);
      await tester.pumpAndSettle();
      expect(repository.calls, contains('unpublish'));
      expect(find.byKey(const ValueKey('publish-link')), findsNothing);
      expect(find.byKey(const ValueKey('publish-button')), findsOneWidget);
    });

    testWidgets('someone who cannot edit cannot publish', (tester) async {
      final repository = FakeNotes2Repository()
        ..publication = const NotePublication();
      await pumpApp(
        tester,
        const NotePublishSheet(noteId: 'note-plan'),
        repository.overrides,
      );
      expect(
        find.text('Only people who can edit this note can publish it.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('publish-button')), findsNothing);
    });

    testWidgets(
      'someone who cannot edit sees that it is published, not the link',
      (tester) async {
        final repository = FakeNotes2Repository()
          ..publication = const NotePublication(published: true);
        await pumpApp(
          tester,
          const NotePublishSheet(noteId: 'note-plan'),
          repository.overrides,
        );
        expect(find.text('This note is published'), findsOneWidget);
        expect(find.byKey(const ValueKey('publish-link')), findsNothing);
        expect(
          find.text('Only people who can edit this note can see the link.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('unpublish-button')), findsNothing);
      },
    );
  });

  group('the page on the web', () {
    PublicNote note() => PublicNote.fromJson({
      'title': 'Trip plan',
      'icon': '\u{1F5FA}',
      'updated_at': '2026-10-24T09:00:00Z',
      'blocks': [
        {'id': 'b1', 'kind': 'h2', 'text': 'Saturday'},
        {
          'id': 'b2',
          'kind': 'paragraph',
          'text': 'Leave at 7. <script>alert(1)</script>',
          'marks': [
            [0, 5, 'b'],
          ],
        },
        {
          'id': 'b3',
          'kind': 'table',
          'props': {
            'header': true,
            'cols': ['c1', 'c2'],
            'rows': [
              {
                'id': 'r1',
                'c': {'c1': 'Day', 'c2': 'Plan'},
              },
            ],
          },
        },
        {
          'id': 'b4',
          'kind': 'image',
          'props': {'name': 'map.png'},
        },
      ],
    });

    testWidgets('shows the note read only, with its text as plain text', (
      tester,
    ) async {
      final repository = FakePublicNoteRepository()..notes[token] = note();
      await pumpApp(
        tester,
        PublicNoteScreen(token: token),
        repository.overrides,
      );
      expect(repository.loaded, [token]);
      expect(find.textContaining('Trip plan'), findsOneWidget);
      expect(find.text('Saturday'), findsOneWidget);
      // Nothing is parsed as markup: the tag is just words.
      expect(
        find.textContaining('<script>alert(1)</script>', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Plan'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('Anyone with the link can read it'),
        findsOneWidget,
      );
    });

    testWidgets('a dead link looks the same whatever killed it', (
      tester,
    ) async {
      final repository = FakePublicNoteRepository();
      await pumpApp(
        tester,
        PublicNoteScreen(token: token),
        repository.overrides,
      );
      expect(find.byKey(const ValueKey('public-note-gone')), findsOneWidget);
      expect(find.text('This page is not available'), findsOneWidget);
    });

    testWidgets('a connection error offers to try again', (tester) async {
      final repository = FakePublicNoteRepository()
        ..error = StateError('offline');
      await pumpApp(
        tester,
        PublicNoteScreen(token: token),
        repository.overrides,
      );
      expect(find.byKey(const ValueKey('public-note-error')), findsOneWidget);
      repository
        ..error = null
        ..notes[token] = note();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Saturday'), findsOneWidget);
    });

    testWidgets('fits a phone', (tester) async {
      final repository = FakePublicNoteRepository()..notes[token] = note();
      await pumpApp(
        tester,
        PublicNoteScreen(token: token),
        repository.overrides,
        size: const Size(390, 780),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
