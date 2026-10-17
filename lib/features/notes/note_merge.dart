import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:wecord/features/notes/note_models.dart';

/// The one contiguous change that turns a text into another: [removed]
/// characters at [start] are replaced by [inserted].
@immutable
class TextEdit {
  const TextEdit(this.start, this.removed, this.inserted);

  final int start;
  final int removed;
  final String inserted;

  int get end => start + removed;
  bool get isEmpty => removed == 0 && inserted.isEmpty;

  @override
  String toString() => 'TextEdit($start, -$removed, +"$inserted")';
}

/// The smallest single edit from [before] to [after] (common prefix and
/// suffix kept). UTF-16 offsets; surrogate pairs are never split.
TextEdit diffText(String before, String after) {
  if (before == after) {
    return TextEdit(before.length, 0, '');
  }
  var prefix = 0;
  final limit = math.min(before.length, after.length);
  while (prefix < limit &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  // Do not stop in the middle of a surrogate pair.
  if (prefix > 0 && _isHighSurrogate(before.codeUnitAt(prefix - 1))) {
    prefix--;
  }
  var suffix = 0;
  while (suffix < limit - prefix &&
      before.codeUnitAt(before.length - 1 - suffix) ==
          after.codeUnitAt(after.length - 1 - suffix)) {
    suffix++;
  }
  if (suffix > 0 &&
      _isLowSurrogate(before.codeUnitAt(before.length - suffix))) {
    suffix--;
  }
  return TextEdit(
    prefix,
    before.length - prefix - suffix,
    after.substring(prefix, after.length - suffix),
  );
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// Where an offset of the old text lands in the new one, for a cursor that
/// should stay with the text around it. Offsets inside a replaced range go
/// to the end of what replaced it.
int transformOffset(int offset, TextEdit edit) {
  if (offset <= edit.start) {
    return offset;
  }
  if (offset >= edit.end) {
    return offset - edit.removed + edit.inserted.length;
  }
  return edit.start + edit.inserted.length;
}

// ------------------------------------------------------------------ marks --

/// The marks of each character of a text of [length]: one set of mark types
/// per UTF-16 unit.
List<Set<String>> marksToCharSets(int length, List<NoteMark> marks) {
  final sets = List<Set<String>>.generate(length, (_) => <String>{});
  for (final mark in marks) {
    final start = mark.start.clamp(0, length);
    final end = mark.end.clamp(0, length);
    for (var i = start; i < end; i++) {
      sets[i].add(mark.type);
    }
  }
  return sets;
}

/// Ranges from per-character sets: neighbours with the same type join.
List<NoteMark> charSetsToMarks(List<Set<String>> sets) {
  final open = <String, int>{};
  final marks = <NoteMark>[];
  for (var i = 0; i <= sets.length; i++) {
    final here = i < sets.length ? sets[i] : const <String>{};
    for (final type in open.keys.toList()) {
      if (!here.contains(type)) {
        marks.add(NoteMark(open.remove(type)!, i, type));
      }
    }
    for (final type in here) {
      open.putIfAbsent(type, () => i);
    }
  }
  marks.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.type.compareTo(b.type);
  });
  return marks;
}

/// [marks] in canonical form for a text of [length]: clipped, sorted and
/// merged. Two block states with the same formatting compare equal.
List<NoteMark> normalizeMarks(List<NoteMark> marks, int length) {
  return charSetsToMarks(marksToCharSets(length, marks));
}

/// The marks of a text after [edit] replaced part of it (its old marks are
/// [marks]). The new characters carry [inserted]'s marks: the set of types
/// they inherit, or none.
List<NoteMark> applyEditToMarks(
  List<NoteMark> marks,
  int oldLength,
  TextEdit edit, {
  Set<String> inherit = const {},
}) {
  final sets = marksToCharSets(oldLength, marks);
  final replacement = List<Set<String>>.generate(
    edit.inserted.length,
    (_) => {...inherit},
  );
  final result = <Set<String>>[
    ...sets.sublist(0, edit.start.clamp(0, sets.length)),
    ...replacement,
    ...sets.sublist(edit.end.clamp(0, sets.length)),
  ];
  return charSetsToMarks(result);
}

/// The mark types a character typed at [offset] picks up: those of the
/// character before it (that continue when typing), and nothing at the
/// start of the text.
Set<String> inheritedMarksAt(String text, List<NoteMark> marks, int offset) {
  if (offset <= 0) {
    return const {};
  }
  return {
    for (final mark in marks)
      if (mark.continuesWhenTyping && mark.start < offset && mark.end >= offset)
        mark.type,
  };
}

// ------------------------------------------------------------------ merge --

/// Merges two people's changes to a block's text and formatting.
///
/// [base] is what both started from, [mine] the local version and [theirs]
/// the one the server has. Changes that do not overlap are both kept:
/// one person's typing in the first sentence survives another's in the
/// last, and bold added by one stays when the other types. Changes to the
/// same stretch keep [theirs] and put what [mine] typed next to it, so
/// nothing typed is ever thrown away.
({String text, List<NoteMark> marks}) mergeText({
  required String base,
  required List<NoteMark> baseMarks,
  required String mine,
  required List<NoteMark> mineMarks,
  required String theirs,
  required List<NoteMark> theirsMarks,
}) {
  final baseSets = marksToCharSets(base.length, baseMarks);
  final mineSets = marksToCharSets(mine.length, mineMarks);
  final theirSets = marksToCharSets(theirs.length, theirsMarks);

  final mineEdit = diffText(base, mine);
  final theirEdit = diffText(base, theirs);

  if (mineEdit.isEmpty && theirEdit.isEmpty) {
    return (
      text: base,
      marks: charSetsToMarks([
        for (var i = 0; i < base.length; i++)
          _mergeSets(baseSets[i], mineSets[i], theirSets[i]),
      ]),
    );
  }

  final overlaps = _overlap(mineEdit, theirEdit);
  if (!overlaps) {
    // The earlier edit goes first; at the same place an insert goes before
    // a replacement (which starts there).
    final mineFirst = mineEdit.start != theirEdit.start
        ? mineEdit.start < theirEdit.start
        : mineEdit.removed == 0;
    final first = mineFirst ? mineEdit : theirEdit;
    final firstIsMine = mineFirst;
    final second = firstIsMine ? theirEdit : mineEdit;
    final text = StringBuffer();
    final sets = <Set<String>>[];

    // Character [i] of the base, seen by each side (null where it was removed).
    Set<String>? inMine(int i) => _mapped(i, mineEdit, mineSets);
    Set<String>? inTheirs(int i) => _mapped(i, theirEdit, theirSets);

    void copyBase(int from, int to) {
      for (var i = from; i < to; i++) {
        text.writeCharCode(base.codeUnitAt(i));
        sets.add(_mergeSets(baseSets[i], inMine(i) ?? {}, inTheirs(i) ?? {}));
      }
    }

    void insert(TextEdit edit, List<Set<String>> source, TextEdit sourceEdit) {
      text.write(edit.inserted);
      for (var i = 0; i < edit.inserted.length; i++) {
        sets.add({...source[sourceEdit.start + i]});
      }
    }

    copyBase(0, first.start);
    insert(first, firstIsMine ? mineSets : theirSets, first);
    copyBase(first.end, second.start);
    insert(second, firstIsMine ? theirSets : mineSets, second);
    copyBase(second.end, base.length);
    return (text: text.toString(), marks: charSetsToMarks(sets));
  }

  // The same stretch changed on both sides: theirs stands, and what mine
  // typed goes next to it.
  var at = mineEdit.start < theirEdit.start
      ? theirEdit.start
      : theirEdit.start + theirEdit.inserted.length;
  at = at.clamp(0, theirs.length);
  if (mineEdit.inserted.isEmpty) {
    return (text: theirs, marks: charSetsToMarks(theirSets));
  }
  final sets = <Set<String>>[
    ...theirSets.sublist(0, at),
    for (var i = 0; i < mineEdit.inserted.length; i++)
      {...mineSets[mineEdit.start + i]},
    ...theirSets.sublist(at),
  ];
  return (
    text: theirs.substring(0, at) + mineEdit.inserted + theirs.substring(at),
    marks: charSetsToMarks(sets),
  );
}

/// The marks of base character [i] in the version produced by [edit], or
/// null when [edit] removed it.
Set<String>? _mapped(int i, TextEdit edit, List<Set<String>> sets) {
  if (i < edit.start) {
    return sets[i];
  }
  if (i >= edit.end) {
    final j = i - edit.removed + edit.inserted.length;
    return j < sets.length ? sets[j] : null;
  }
  return null;
}

/// A three-way merge of one character's marks: what either side removed is
/// gone, what either side added is kept.
Set<String> _mergeSets(Set<String> base, Set<String> mine, Set<String> theirs) {
  return {
    for (final type in {...base, ...mine, ...theirs})
      if (_keeps(type, base, mine, theirs)) type,
  };
}

bool _keeps(
  String type,
  Set<String> base,
  Set<String> mine,
  Set<String> theirs,
) {
  if (base.contains(type)) {
    return mine.contains(type) && theirs.contains(type);
  }
  return mine.contains(type) || theirs.contains(type);
}

/// Whether two edits of the same base touch the same stretch (including two
/// inserts at the same place, whose order would be arbitrary).
bool _overlap(TextEdit a, TextEdit b) {
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  if (a.removed == 0 && b.removed == 0) {
    return a.start == b.start;
  }
  if (a.removed == 0) {
    return a.start > b.start && a.start < b.end;
  }
  if (b.removed == 0) {
    return b.start > a.start && b.start < a.end;
  }
  return a.start < b.end && b.start < a.end;
}

/// Merges two versions of a block that both changed from [base] (null for a
/// block both created). Text and formatting merge as [mergeText]; the kind,
/// position and properties are decided field by field: what [mine] changed
/// wins, otherwise [theirs] stands. The result carries [theirs]' revision so
/// it can be sent as the next change.
NoteBlock mergeBlocks({
  required NoteBlock? base,
  required NoteBlock mine,
  required NoteBlock theirs,
}) {
  final origin =
      base ??
      NoteBlock(id: mine.id, pos: theirs.pos, kind: theirs.kind, rev: 0);
  T pick<T>(T baseValue, T mineValue, T theirValue) =>
      mineValue != baseValue ? mineValue : theirValue;

  final merged = mergeText(
    base: origin.text,
    baseMarks: origin.marks,
    mine: mine.text,
    mineMarks: mine.marks,
    theirs: theirs.text,
    theirsMarks: theirs.marks,
  );
  final props = <String, Object?>{...theirs.props};
  for (final key in {...origin.props.keys, ...mine.props.keys}) {
    if (origin.props[key] != mine.props[key]) {
      if (mine.props.containsKey(key)) {
        props[key] = mine.props[key];
      } else {
        props.remove(key);
      }
    }
  }
  return NoteBlock(
    id: mine.id,
    pos: pick(origin.pos, mine.pos, theirs.pos),
    kind: pick(origin.kind, mine.kind, theirs.kind),
    text: merged.text,
    marks: merged.marks,
    props: props,
    rev: theirs.rev,
    deleted: false,
  );
}
