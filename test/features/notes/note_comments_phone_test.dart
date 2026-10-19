import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_comments_controller.dart';
import 'package:wecord/features/notes/note_comments_panel.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'notes2_fakes.dart';

void main() {
  testWidgets(
    'the comments sheet fits a phone, with a long name and your own comment',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = FakeNotes2Repository();
      repository.comments.add(
        sampleComment(
          'c1',
          author: 'A very long display name that goes on and on and on',
          body: 'Short',
          canEdit: true,
          canDelete: true,
        ),
      );
      final controller = NoteCommentsController(
        repository: repository,
        noteId: 'n',
        newId: () => 'x',
      );
      await tester.runAsync(controller.open);
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNoteComments(
                context,
                controller: controller,
                members: const [],
                canComment: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('note-comment-field')),
        'hello',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('note-comment-send')));
      await tester.pumpAndSettle();
      expect(find.text('hello'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      controller.dispose();
    },
  );
}
