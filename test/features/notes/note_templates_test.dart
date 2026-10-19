import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_templates.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'notes2_fakes.dart';

void main() {
  group('the templates that come with the app', () {
    test('are meeting notes, a weekly report and a trip plan', () {
      final templates = builtInNoteTemplates();
      expect(templates.map((t) => t.name), [
        'Meeting notes',
        'Weekly report',
        'Trip plan',
      ]);
      for (final template in templates) {
        expect(template.blocks, isNotEmpty);
        expect(template.icon, isNotEmpty);
      }
    });

    test('hold only blocks the server accepts', () {
      for (final template in builtInNoteTemplates()) {
        expect(template.blocks.length, lessThanOrEqualTo(200));
        for (final block in template.blocks) {
          // create_note_from_blocks refuses pictures (their files belong to
          // another note).
          expect(block.kind, isNot(NoteBlockKind.image));
          expect(block.text.length, lessThanOrEqualTo(20000));
          if (block.kind == NoteBlockKind.table) {
            final table = NoteTable.fromProps(block.props);
            expect(table.columns.length, inInclusiveRange(1, maxTableColumns));
            expect(table.rows.length, inInclusiveRange(1, maxTableRows));
            // Ids are short and the table survives being stored.
            for (final id in [
              ...table.columns,
              ...table.rows.map((r) => r.id),
            ]) {
              expect(id.length, inInclusiveRange(1, 16));
            }
            expect(block.props['cols'], table.columns);
          }
        }
      }
    });

    test('read in Chinese when the app does', () {
      AppStrings.isChinese = true;
      addTearDown(() => AppStrings.isChinese = false);
      expect(builtInNoteTemplates().map((t) => t.name), ['会议纪要', '周报', '旅行计划']);
    });
  });

  group('the new note sheet', () {
    Future<NewNoteChoice?> open(
      WidgetTester tester,
      FakeNotes2Repository repository,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      NewNoteChoice? choice;
      var done = false;
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: repository.overrides,
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      choice = await showNewNoteSheet(context);
                      done = true;
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      addTearDown(() => expect(done || choice == null, isTrue));
      return choice;
    }

    testWidgets('offers a blank page, the app\'s templates and mine', (
      tester,
    ) async {
      final repository = FakeNotes2Repository()
        ..templates = const [
          NoteTemplateSummary(
            id: 't1',
            name: 'Retro',
            icon: '\u{1F501}',
            title: 'Retro',
            blockCount: 7,
          ),
        ];
      await open(tester, repository);
      expect(find.text('Blank note'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Weekly report'), findsOneWidget);
      expect(find.text('Trip plan'), findsOneWidget);
      expect(find.text('My templates'), findsOneWidget);
      expect(find.text('Retro'), findsOneWidget);
      expect(find.text('7 blocks'), findsOneWidget);
    });

    testWidgets('no personal templates, no heading for them', (tester) async {
      await open(tester, FakeNotes2Repository());
      expect(find.text('My templates'), findsNothing);
    });

    testWidgets('choosing blank answers with no template', (tester) async {
      NewNoteChoice? result;
      var closed = false;
      final repository = FakeNotes2Repository();
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: repository.overrides,
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showNewNoteSheet(context);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-note-blank')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNotNull);
      expect(result!.template, isNull);
    });

    testWidgets('choosing a template of the app answers with its blocks', (
      tester,
    ) async {
      NewNoteChoice? result;
      final repository = FakeNotes2Repository();
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: repository.overrides,
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showNewNoteSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-note-template-1')));
      await tester.pumpAndSettle();
      expect(result?.template?.name, 'Weekly report');
      expect(
        result!.template!.blocks.any((b) => b.kind == NoteBlockKind.table),
        isTrue,
      );
    });

    testWidgets('a personal template is fetched when it is chosen', (
      tester,
    ) async {
      NewNoteChoice? result;
      final repository = FakeNotes2Repository()
        ..templates = const [
          NoteTemplateSummary(
            id: 't1',
            name: 'Retro',
            icon: 'x',
            title: 'Retro',
            blockCount: 1,
          ),
        ]
        ..templateContents['t1'] = const NoteTemplate(
          id: 't1',
          name: 'Retro',
          icon: 'x',
          title: 'Retro',
          blocks: [NoteTemplateBlock(kind: NoteBlockKind.bullet, text: 'Good')],
        );
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: repository.overrides,
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showNewNoteSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-note-mine-t1')));
      await tester.pumpAndSettle();
      expect(result?.template?.blocks.single.text, 'Good');
    });

    testWidgets('a personal template can be deleted after asking', (
      tester,
    ) async {
      final repository = FakeNotes2Repository()
        ..templates = const [
          NoteTemplateSummary(
            id: 't1',
            name: 'Retro',
            icon: 'x',
            title: 'Retro',
            blockCount: 1,
          ),
        ];
      await open(tester, repository);
      await tester.tap(find.byTooltip('Delete template'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this template?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(repository.calls, contains('delete-template'));
      expect(find.text('Retro'), findsNothing);
    });
  });
}
