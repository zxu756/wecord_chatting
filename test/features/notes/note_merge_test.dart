import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/note_merge.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/shared/models/fractional_key.dart';

NoteMark mark(int start, int end, String type) => NoteMark(start, end, type);

({String text, List<NoteMark> marks}) merge(
  String base,
  String mine,
  String theirs, {
  List<NoteMark> baseMarks = const [],
  List<NoteMark> mineMarks = const [],
  List<NoteMark> theirsMarks = const [],
}) => mergeText(
  base: base,
  baseMarks: baseMarks,
  mine: mine,
  mineMarks: mineMarks,
  theirs: theirs,
  theirsMarks: theirsMarks,
);

void main() {
  group('fractional keys', () {
    test('the first key and keys at either end', () {
      expect(keyBetween(null, null), firstFractionalKey);
      final before = keyBetween(null, 'V');
      final after = keyBetween('V', null);
      expect(before.compareTo('V'), lessThan(0));
      expect(after.compareTo('V'), greaterThan(0));
    });

    test('keys always fit between any two neighbours', () {
      var low = keyBetween(null, null);
      var high = keyBetween(low, null);
      // Keep inserting at the same spot: the keys grow but stay ordered.
      for (var i = 0; i < 100; i++) {
        final middle = keyBetween(low, high);
        expect(middle.compareTo(low), greaterThan(0), reason: '$low $middle');
        expect(middle.compareTo(high), lessThan(0), reason: '$middle $high');
        expect(isFractionalKey(middle), isTrue);
        high = middle;
      }
      for (var i = 0; i < 100; i++) {
        final middle = keyBetween(low, high);
        expect(middle.compareTo(low), greaterThan(0));
        expect(middle.compareTo(high), lessThan(0));
        low = middle;
      }
    });

    test('appending and prepending many times stays ordered', () {
      final keys = <String>[keyBetween(null, null)];
      for (var i = 0; i < 100; i++) {
        keys.add(keyBetween(keys.last, null));
      }
      for (var i = 0; i < 100; i++) {
        keys.insert(0, keyBetween(null, keys.first));
      }
      final sorted = [...keys]..sort();
      expect(keys, sorted);
      expect(keys.toSet().length, keys.length);
    });

    test('several keys at once', () {
      final keys = keysBetween('A', 'B', 9);
      expect(keys.length, 9);
      expect([...keys]..sort(), keys);
      expect(keys.first.compareTo('A'), greaterThan(0));
      expect(keys.last.compareTo('B'), lessThan(0));
      expect(keysBetween(null, null, 0), isEmpty);
    });

    test('keys the wrong way round are refused', () {
      expect(() => keyBetween('b', 'a'), throwsArgumentError);
      expect(() => keyBetween('a', 'a'), throwsArgumentError);
      expect(() => keyBetween('a0', null), throwsArgumentError);
    });
  });

  group('diffText and transformOffset', () {
    test('finds the one changed stretch', () {
      final edit = diffText('hello world', 'hello brave world');
      expect(edit.start, 6);
      expect(edit.removed, 0);
      expect(edit.inserted, 'brave ');
      expect(diffText('abc', 'abc').isEmpty, isTrue);
      final replaced = diffText('abcdef', 'abXYef');
      expect(
        (replaced.start, replaced.removed, replaced.inserted),
        (2, 2, 'XY'),
      );
    });

    test('never splits an emoji', () {
      final edit = diffText('a\u{1F600}b', 'a\u{1F601}b');
      expect(edit.start, 1);
      expect(edit.removed, 2);
      expect(edit.inserted, '\u{1F601}');
    });

    test('cursors follow the text around them', () {
      final edit = diffText('hello world', 'hello brave world');
      expect(transformOffset(3, edit), 3);
      expect(transformOffset(6, edit), 6);
      expect(transformOffset(8, edit), 14);
      final removal = diffText('hello brave world', 'hello world');
      expect(transformOffset(9, removal), 6);
      expect(transformOffset(17, removal), 11);
    });
  });

  group('marks', () {
    test('become per character sets and back', () {
      final marks = [mark(0, 3, 'b'), mark(2, 5, 'i')];
      final sets = marksToCharSets(6, marks);
      expect(sets[2], {'b', 'i'});
      expect(sets[5], isEmpty);
      expect(charSetsToMarks(sets), [mark(0, 3, 'b'), mark(2, 5, 'i')]);
    });

    test('normalizing merges touching marks and clips to the text', () {
      expect(
        normalizeMarks([mark(0, 2, 'b'), mark(2, 4, 'b'), mark(3, 99, 'i')], 5),
        [mark(0, 4, 'b'), mark(3, 5, 'i')],
      );
      expect(normalizeMarks([mark(4, 2, 'b')], 5), isEmpty);
    });

    test('typing inside bold continues it; links and mentions do not', () {
      final marks = [mark(0, 5, 'b'), mark(2, 4, 'l:https://a.test')];
      expect(inheritedMarksAt('hello', marks, 3), {'b'});
      expect(inheritedMarksAt('hello', marks, 0), isEmpty);
      final edit = diffText('hello', 'heXllo');
      final next = applyEditToMarks(
        marks,
        5,
        edit,
        inherit: inheritedMarksAt('hello', marks, 2),
      );
      expect(next.where((m) => m.type == 'b').single, mark(0, 6, 'b'));
      // The link moved right by one and stayed 2 long.
      expect(next.where((m) => m.isLink).single.start, 3);
    });
  });

  group('mergeText', () {
    test('edits in different places are both kept', () {
      final merged = merge(
        'The quick fox jumps',
        'The quick brown fox jumps',
        'The quick fox jumps over',
      );
      expect(merged.text, 'The quick brown fox jumps over');
    });

    test('an edit on one side only is taken as is', () {
      expect(merge('abc', 'abc', 'abXc').text, 'abXc');
      expect(merge('abc', 'aXbc', 'abc').text, 'aXbc');
    });

    test('inserts at the same place keep both, theirs first', () {
      final merged = merge('ab', 'aXb', 'aYb');
      expect(merged.text, 'aYXb');
    });

    test('changes to the same stretch keep theirs and what mine typed', () {
      final merged = merge('one two three', 'one TWO three', 'one 2 three');
      expect(merged.text.contains('2'), isTrue);
      expect(merged.text.contains('TWO'), isTrue);
    });

    test('a removal and an edit elsewhere both apply', () {
      final merged = merge('abcdef', 'cdef', 'abcdeXf');
      expect(merged.text, 'cdeXf');
    });

    test('formatting added on one side survives typing on the other', () {
      final merged = merge(
        'hello world',
        'hello world',
        'hello world!',
        mineMarks: [mark(0, 5, 'b')],
      );
      expect(merged.text, 'hello world!');
      expect(merged.marks, [mark(0, 5, 'b')]);
    });

    test('formatting removed on one side is removed in the result', () {
      final merged = merge(
        'hello world',
        'hello world',
        'hello world',
        baseMarks: [mark(0, 11, 'b')],
        mineMarks: [mark(6, 11, 'b')],
        theirsMarks: [mark(0, 11, 'b')],
      );
      expect(merged.marks, [mark(6, 11, 'b')]);
    });

    test('marks move with the text around an insert', () {
      final merged = merge(
        'bold word',
        'bold word',
        'very bold word',
        baseMarks: [mark(0, 4, 'b')],
        mineMarks: [mark(0, 4, 'b'), mark(5, 9, 'i')],
        theirsMarks: [mark(5, 9, 'b')],
      );
      expect(merged.text, 'very bold word');
      expect(merged.marks, [mark(5, 9, 'b'), mark(10, 14, 'i')]);
    });

    test('inserted text brings its own marks', () {
      final merged = merge('ab', 'aXXb', 'ab', mineMarks: [mark(1, 3, 'c')]);
      expect(merged.text, 'aXXb');
      expect(merged.marks, [mark(1, 3, 'c')]);
    });
  });

  group('mergeBlocks', () {
    const base = NoteBlock(
      id: 'b1',
      pos: 'V',
      kind: NoteBlockKind.paragraph,
      text: 'hello',
      rev: 1,
    );

    test('what mine changed wins field by field, the rest is theirs', () {
      final merged = mergeBlocks(
        base: base,
        mine: base.copyWith(kind: NoteBlockKind.bullet),
        theirs: base.copyWith(text: 'hello!', pos: 'W', rev: 2),
      );
      expect(merged.kind, NoteBlockKind.bullet);
      expect(merged.text, 'hello!');
      expect(merged.pos, 'W');
      expect(merged.rev, 2);
    });

    test('a checked box on one side and text on the other both stay', () {
      final merged = mergeBlocks(
        base: base.copyWith(kind: NoteBlockKind.todo),
        mine: base.copyWith(kind: NoteBlockKind.todo, props: {'checked': true}),
        theirs: base.copyWith(
          kind: NoteBlockKind.todo,
          text: 'hello there',
          rev: 3,
        ),
      );
      expect(merged.checked, isTrue);
      expect(merged.text, 'hello there');
    });

    test('a block both sides created merges as inserts', () {
      final merged = mergeBlocks(
        base: null,
        mine: const NoteBlock(id: 'b1', pos: 'V', text: 'mine'),
        theirs: const NoteBlock(id: 'b1', pos: 'V', text: 'theirs', rev: 1),
      );
      expect(merged.text, contains('mine'));
      expect(merged.text, contains('theirs'));
    });
  });
}
