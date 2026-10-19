import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_sheet.dart';
import 'package:wecord/features/notes/note_editor_extras.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../notes/notes2_fakes.dart';

Future<void> openSheet(
  WidgetTester tester,
  FakeNoteAssistRepository repository,
  NoteAssistTarget target,
  void Function(NoteAssistApply? apply) onClosed,
) async {
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
            onPressed: () async => onClosed(
              await showNoteAssistSheet(
                context,
                noteId: 'note-plan',
                target: target,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the answer', () {
    test('keeps text blocks and turns anything else into a paragraph', () {
      final todo = NoteAssistBlock.maybeFromJson({
        'kind': 'todo',
        'text': 'Book',
        'checked': true,
      })!.toInsert();
      expect(todo.kind, NoteBlockKind.todo);
      expect(todo.text, 'Book');
      expect(todo.props, {'checked': true});
      expect(
        NoteAssistBlock.maybeFromJson({'kind': 'image', 'text': 'x'})!.kind,
        NoteBlockKind.paragraph,
      );
      expect(
        NoteAssistBlock.maybeFromJson({'kind': 'table', 'text': 'x'})!.kind,
        NoteBlockKind.paragraph,
      );
      expect(
        NoteAssistBlock.maybeFromJson({'kind': 'bullet', 'text': ' '}),
        isNull,
      );
      expect(NoteAssistBlock.maybeFromJson('junk'), isNull);
      expect(
        NoteAssistBlock.maybeFromJson({
          'kind': 'bullet',
          'text': 'a',
        })!.toInsert().props,
        isEmpty,
      );
    });

    test('modes name what the server takes', () {
      expect(NoteAssistMode.values.map((m) => m.code), [
        'continue',
        'summarize',
        'outline',
        'tone',
        'translate',
        'extract_tasks',
      ]);
      expect(NoteAssistTone.values.map((t) => t.code), [
        'polite',
        'formal',
        'casual',
        'concise',
        'fix',
      ]);
      expect(NoteAssistMode.tone.canReplaceSelection, isTrue);
      expect(NoteAssistMode.summarize.canReplaceSelection, isFalse);
    });
  });

  group('the sheet', () {
    testWidgets('lists the six jobs and says what it works on', (tester) async {
      await openSheet(
        tester,
        FakeNoteAssistRepository(),
        const NoteAssistTarget(),
        (_) {},
      );
      for (final mode in NoteAssistMode.values) {
        expect(
          find.byKey(ValueKey('assist-mode-${mode.code}')),
          findsOneWidget,
        );
      }
      expect(find.text('On the whole note'), findsOneWidget);
      expect(
        find.textContaining('nothing changes until you add it'),
        findsOneWidget,
      );
    });

    testWidgets('sends the selection, not the note, and offers to replace it', (
      tester,
    ) async {
      final repository = FakeNoteAssistRepository()
        ..result = const NoteAssistResult(
          blocks: [
            NoteAssistBlock(
              kind: NoteBlockKind.paragraph,
              text: 'Could you send the file?',
            ),
          ],
          text: 'Could you send the file?',
        );
      NoteAssistApply? applied;
      await openSheet(
        tester,
        repository,
        const NoteAssistTarget(
          blockId: 'b1',
          start: 0,
          end: 17,
          selectedText: 'send me the file!',
        ),
        (apply) => applied = apply,
      );
      expect(find.text('On the words you selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assist-mode-tone')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('assist-tone-polite')));
      await tester.pumpAndSettle();
      final request = repository.requests.single;
      expect(request.mode, NoteAssistMode.tone);
      expect(request.tone, NoteAssistTone.polite);
      expect(request.text, 'send me the file!');
      expect(request.noteId, 'note-plan');
      expect(find.text('Could you send the file?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assist-replace')));
      await tester.pumpAndSettle();
      expect(applied?.replace, isTrue);
      expect(applied?.result.text, 'Could you send the file?');
    });

    testWidgets('a summary is added below, never in place of anything', (
      tester,
    ) async {
      final repository = FakeNoteAssistRepository();
      NoteAssistApply? applied;
      await openSheet(
        tester,
        repository,
        const NoteAssistTarget(
          blockId: 'b1',
          start: 0,
          end: 4,
          selectedText: 'Pack',
        ),
        (apply) => applied = apply,
      );
      await tester.tap(find.byKey(const ValueKey('assist-mode-summarize')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-replace')), findsNothing);
      expect(find.text('• First point'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assist-insert')));
      await tester.pumpAndSettle();
      expect(applied?.replace, isFalse);
      expect(applied?.result.blocks, hasLength(2));
    });

    testWidgets('translating asks for a language first', (tester) async {
      final repository = FakeNoteAssistRepository();
      await openSheet(tester, repository, const NoteAssistTarget(), (_) {});
      await tester.tap(find.byKey(const ValueKey('assist-mode-translate')));
      await tester.pumpAndSettle();
      expect(repository.requests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('assist-language-ja')));
      await tester.pumpAndSettle();
      expect(repository.requests.single.target, AiLanguage.japanese);
      expect(repository.requests.single.text, isNull);
    });

    testWidgets('closing without choosing changes nothing', (tester) async {
      var closed = false;
      NoteAssistApply? applied;
      await openSheet(
        tester,
        FakeNoteAssistRepository(),
        const NoteAssistTarget(),
        (apply) {
          closed = true;
          applied = apply;
        },
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(applied, isNull);
    });

    testWidgets('waits for the answer with a status for screen readers', (
      tester,
    ) async {
      final repository = FakeNoteAssistRepository()..hold = Completer<void>();
      await openSheet(tester, repository, const NoteAssistTarget(), (_) {});
      await tester.tap(find.byKey(const ValueKey('assist-mode-outline')));
      await tester.pump();
      expect(find.byKey(const ValueKey('assist-working')), findsOneWidget);
      expect(find.text('Thinking…'), findsOneWidget);
      repository.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-result')), findsOneWidget);
    });

    testWidgets(
      'says why when AI cannot help, and offers a retry only when it may work',
      (tester) async {
        final repository = FakeNoteAssistRepository()
          ..error = const AiBusyException();
        await openSheet(tester, repository, const NoteAssistTarget(), (_) {});
        await tester.tap(find.byKey(const ValueKey('assist-mode-continue')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('assist-error')), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        repository.error = null;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('assist-result')), findsOneWidget);
      },
    );

    testWidgets('a limit or a switch that is off has no retry', (tester) async {
      for (final error in <AiException>[
        const AiLimitReachedException(limit: 50),
        const AiDisabledInCircleException(),
        const AiTurnedOffException(),
      ]) {
        final repository = FakeNoteAssistRepository()..error = error;
        await openSheet(tester, repository, const NoteAssistTarget(), (_) {});
        await tester.tap(find.byKey(const ValueKey('assist-mode-summarize')));
        await tester.pumpAndSettle();
        expect(find.text('Try again'), findsNothing);
        expect(find.text(aiErrorMessage(error)), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('nothing to work on, or no to-dos, is said plainly', (
      tester,
    ) async {
      final repository = FakeNoteAssistRepository()
        ..result = const NoteAssistResult(blocks: [], text: '');
      await openSheet(tester, repository, const NoteAssistTarget(), (_) {});
      await tester.tap(find.byKey(const ValueKey('assist-mode-extract_tasks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assist-empty')), findsOneWidget);
      expect(find.text('No to-dos found.'), findsOneWidget);
    });

    testWidgets('a long note says the AI read only part of it', (tester) async {
      final repository = FakeNoteAssistRepository()
        ..result = const NoteAssistResult(
          blocks: [NoteAssistBlock(kind: NoteBlockKind.bullet, text: 'x')],
          text: 'x',
          truncated: true,
        );
      await openSheet(tester, repository, const NoteAssistTarget(), (_) {});
      await tester.tap(find.byKey(const ValueKey('assist-mode-summarize')));
      await tester.pumpAndSettle();
      expect(
        find.text('The note is long, so the AI read only part of it.'),
        findsOneWidget,
      );
    });
  });
}
