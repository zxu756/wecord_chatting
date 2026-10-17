import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_text_controller.dart';
import 'package:wecord/features/notes/note_text_ops.dart';

void main() {
  group('markdown shortcuts', () {
    test('a prefix typed into an empty paragraph picks the kind', () {
      expect(shortcutFor('# ')!.kind, NoteBlockKind.heading1);
      expect(shortcutFor('## ')!.kind, NoteBlockKind.heading2);
      expect(shortcutFor('### ')!.kind, NoteBlockKind.heading3);
      expect(shortcutFor('- ')!.kind, NoteBlockKind.bullet);
      expect(shortcutFor('* ')!.kind, NoteBlockKind.bullet);
      expect(shortcutFor('+ ')!.kind, NoteBlockKind.bullet);
      expect(shortcutFor('1. ')!.kind, NoteBlockKind.numbered);
      expect(shortcutFor('12. ')!.kind, NoteBlockKind.numbered);
      expect(shortcutFor('[] ')!.kind, NoteBlockKind.todo);
      expect(shortcutFor('[ ] ')!.kind, NoteBlockKind.todo);
      expect(shortcutFor('[x] ')!.props, {'checked': true});
      expect(shortcutFor('> ')!.kind, NoteBlockKind.quote);
      expect(shortcutFor('```')!.kind, NoteBlockKind.code);
    });

    test('anything else is just text', () {
      expect(shortcutFor('#'), isNull);
      expect(shortcutFor('-'), isNull);
      expect(shortcutFor('- milk'), isNull);
      expect(shortcutFor('#hashtag '), isNull);
      expect(shortcutFor('####### '), isNull);
      expect(shortcutFor('a. '), isNull);
      expect(shortcutFor(''), isNull);
    });
  });

  group('splitText and joinText', () {
    test('marks follow the text on either side of the cut', () {
      final parts = splitText('hello world', const [
        NoteMark(0, 5, 'b'),
        NoteMark(3, 8, 'i'),
      ], 4);
      expect(parts.left, 'hell');
      expect(parts.leftMarks, [
        const NoteMark(0, 4, 'b'),
        const NoteMark(3, 4, 'i'),
      ]);
      expect(parts.right, 'o world');
      expect(parts.rightMarks, [
        const NoteMark(0, 1, 'b'),
        const NoteMark(0, 4, 'i'),
      ]);
    });

    test('joining keeps both sets of marks in place', () {
      final joined = joinText(
        'Hi ',
        const [NoteMark(0, 2, 'b')],
        'there',
        const [NoteMark(0, 5, 'i')],
      );
      expect(joined.text, 'Hi there');
      expect(joined.marks, [
        const NoteMark(0, 2, 'b'),
        const NoteMark(3, 8, 'i'),
      ]);
    });
  });

  group('pasted text', () {
    test('lines become blocks by their markdown', () {
      final blocks = parsePastedText(
        '# Title\n\nplain\n- one\n* two\n1. first\n2) second\n- [ ] todo\n- [x] done\n> quote\n---',
      );
      expect(blocks.map((b) => b.kind), [
        NoteBlockKind.heading1,
        NoteBlockKind.paragraph,
        NoteBlockKind.bullet,
        NoteBlockKind.bullet,
        NoteBlockKind.numbered,
        NoteBlockKind.numbered,
        NoteBlockKind.todo,
        NoteBlockKind.todo,
        NoteBlockKind.quote,
        NoteBlockKind.divider,
      ]);
      expect(blocks[0].text, 'Title');
      expect(blocks[1].text, 'plain');
      expect(blocks[7].props, {'checked': true});
    });

    test('a code fence is one block, with its language', () {
      final blocks = parsePastedText(
        '```dart\nvar a = 1;\n\nvar b = 2;\n```\nafter',
      );
      expect(blocks.first.kind, NoteBlockKind.code);
      expect(blocks.first.text, 'var a = 1;\n\nvar b = 2;');
      expect(blocks.first.props, {'lang': 'dart'});
      expect(blocks.last.text, 'after');
    });
  });

  test('numbered blocks count up and start again after other blocks', () {
    NoteBlock b(NoteBlockKind kind, String id) =>
        NoteBlock(id: id, pos: id, kind: kind);
    expect(
      listNumbers([
        b(NoteBlockKind.numbered, 'a'),
        b(NoteBlockKind.numbered, 'b'),
        b(NoteBlockKind.paragraph, 'c'),
        b(NoteBlockKind.numbered, 'd'),
      ]),
      [1, 2, null, 1],
    );
  });

  test('a note exports as markdown', () {
    final markdown = noteToMarkdown('Plan', const [
      NoteBlock(id: 'a', pos: 'a', kind: NoteBlockKind.heading2, text: 'Food'),
      NoteBlock(
        id: 'b',
        pos: 'b',
        text: 'Pack bold things',
        marks: [NoteMark(5, 9, 'b'), NoteMark(10, 16, 'l:https://a.test')],
      ),
      NoteBlock(id: 'c', pos: 'c', kind: NoteBlockKind.bullet, text: 'rice'),
      NoteBlock(id: 'd', pos: 'd', kind: NoteBlockKind.bullet, text: 'beans'),
      NoteBlock(
        id: 'e',
        pos: 'e',
        kind: NoteBlockKind.todo,
        text: 'shop',
        props: {'checked': true},
      ),
    ]);
    expect(markdown, '''
# Plan

## Food

Pack **bold** [things](https://a.test)

- rice
- beans
- [x] shop''');
  });

  group('NoteTextController', () {
    test('typing inside a bold stretch continues it', () {
      final controller = NoteTextController(
        text: 'bold word',
        marks: const [NoteMark(0, 4, 'b')],
      );
      final changes = <(String, List<NoteMark>)>[];
      controller.onUserChange = (text, marks) => changes.add((text, marks));
      controller.value = const TextEditingValue(
        text: 'boXld word',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(controller.marks, [const NoteMark(0, 5, 'b')]);
      expect(changes.single.$1, 'boXld word');
      controller.dispose();
    });

    test('typing at the end of a link does not extend the link', () {
      final controller = NoteTextController(
        text: 'see docs',
        marks: const [NoteMark(4, 8, 'l:https://a.test')],
      );
      controller.value = const TextEditingValue(
        text: 'see docs!',
        selection: TextSelection.collapsed(offset: 9),
      );
      expect(controller.marks, [const NoteMark(4, 8, 'l:https://a.test')]);
      controller.dispose();
    });

    test('toggling at a caret styles what is typed next', () {
      final controller = NoteTextController(text: 'ab');
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
      );
      controller.toggle(NoteMark.bold);
      expect(controller.isActive(NoteMark.bold), isTrue);
      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(controller.marks, [const NoteMark(2, 3, 'b')]);
      controller.dispose();
    });

    test('remote text keeps the caret with the words around it', () {
      final controller = NoteTextController(text: 'hello world');
      controller.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 8),
      );
      controller.applyRemote('hello brave world', const []);
      expect(controller.text, 'hello brave world');
      expect(controller.selection.baseOffset, 14);
      controller.dispose();
    });

    test('remote changes do not look like typing', () {
      final controller = NoteTextController(text: 'a');
      var typed = 0;
      controller.onUserChange = (_, _) => typed++;
      controller.applyRemote('ab', const [NoteMark(0, 2, 'b')]);
      expect(typed, 0);
      expect(controller.marks, [const NoteMark(0, 2, 'b')]);
      controller.dispose();
    });

    test('a link is set and removed on the selection', () {
      final controller = NoteTextController(text: 'see docs here');
      controller.value = const TextEditingValue(
        text: 'see docs here',
        selection: TextSelection(baseOffset: 4, extentOffset: 8),
      );
      controller.setLink('https://a.test');
      expect(controller.marks, [const NoteMark(4, 8, 'l:https://a.test')]);
      expect(controller.linkAtSelection!.linkUrl, 'https://a.test');
      controller.setLink('');
      expect(controller.marks, isEmpty);
      controller.dispose();
    });

    test('a mention replaces the typed @name and carries the person', () {
      final controller = NoteTextController(text: 'ask @gr');
      controller.insertMention(
        start: 4,
        end: 7,
        userId: 'user-3',
        label: '@Grace',
      );
      expect(controller.text, 'ask @Grace ');
      expect(controller.marks, [const NoteMark(4, 10, 'm:user-3')]);
      expect(controller.selection.baseOffset, 11);
      controller.dispose();
    });
  });
}
