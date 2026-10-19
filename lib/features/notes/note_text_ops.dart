import 'package:wecord/features/notes/note_merge.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_table.dart';

/// What typing a markdown shortcut at the start of a paragraph turns it
/// into.
typedef BlockShortcut = ({
  NoteBlockKind kind,
  String text,
  Map<String, Object?> props,
});

final _numberedPattern = RegExp(r'^\d{1,3}\. $');

/// The block kind that [text] asks for, when it is exactly a markdown
/// prefix just typed into a paragraph: `# `, `## `, `### `, `- `, `* `,
/// `+ `, `1. `, `[] `, `[ ] `, `[x] `, `> ` and a fence of three backticks.
BlockShortcut? shortcutFor(String text) {
  switch (text) {
    case '# ':
      return (kind: NoteBlockKind.heading1, text: '', props: const {});
    case '## ':
      return (kind: NoteBlockKind.heading2, text: '', props: const {});
    case '### ':
      return (kind: NoteBlockKind.heading3, text: '', props: const {});
    case '- ' || '* ' || '+ ':
      return (kind: NoteBlockKind.bullet, text: '', props: const {});
    case '[] ' || '[ ] ':
      return (kind: NoteBlockKind.todo, text: '', props: const {});
    case '[x] ' || '[X] ':
      return (
        kind: NoteBlockKind.todo,
        text: '',
        props: const {'checked': true},
      );
    case '> ':
      return (kind: NoteBlockKind.quote, text: '', props: const {});
    case '```':
      return (kind: NoteBlockKind.code, text: '', props: const {});
  }
  if (_numberedPattern.hasMatch(text)) {
    return (kind: NoteBlockKind.numbered, text: '', props: const {});
  }
  return null;
}

/// A text cut in two at [offset], each part with the marks that fall in it.
({
  String left,
  List<NoteMark> leftMarks,
  String right,
  List<NoteMark> rightMarks,
})
splitText(String text, List<NoteMark> marks, int offset) {
  final at = offset.clamp(0, text.length);
  final sets = marksToCharSets(text.length, marks);
  return (
    left: text.substring(0, at),
    leftMarks: charSetsToMarks(sets.sublist(0, at)),
    right: text.substring(at),
    rightMarks: charSetsToMarks(sets.sublist(at)),
  );
}

/// [first] followed by [second], with their marks.
({String text, List<NoteMark> marks}) joinText(
  String first,
  List<NoteMark> firstMarks,
  String second,
  List<NoteMark> secondMarks,
) {
  final sets = [
    ...marksToCharSets(first.length, firstMarks),
    ...marksToCharSets(second.length, secondMarks),
  ];
  return (text: first + second, marks: charSetsToMarks(sets));
}

/// A line of pasted text read as a block: markdown prefixes choose the
/// kind.
({NoteBlockKind kind, String text, Map<String, Object?> props}) parseLine(
  String line,
) {
  final trimmed = line.trimRight();
  final heading = RegExp(r'^(#{1,3}) +(.*)$').firstMatch(trimmed);
  if (heading != null) {
    return (
      kind: switch (heading.group(1)!.length) {
        1 => NoteBlockKind.heading1,
        2 => NoteBlockKind.heading2,
        _ => NoteBlockKind.heading3,
      },
      text: heading.group(2)!,
      props: const {},
    );
  }
  final todo = RegExp(r'^[-*+] \[([ xX])\] +(.*)$').firstMatch(trimmed);
  if (todo != null) {
    return (
      kind: NoteBlockKind.todo,
      text: todo.group(2)!,
      props: todo.group(1) == ' ' ? const {} : const {'checked': true},
    );
  }
  final bullet = RegExp(r'^\s*[-*+] +(.*)$').firstMatch(trimmed);
  if (bullet != null) {
    return (
      kind: NoteBlockKind.bullet,
      text: bullet.group(1)!,
      props: const {},
    );
  }
  final numbered = RegExp(r'^\s*\d{1,3}[.)] +(.*)$').firstMatch(trimmed);
  if (numbered != null) {
    return (
      kind: NoteBlockKind.numbered,
      text: numbered.group(1)!,
      props: const {},
    );
  }
  final quote = RegExp(r'^> ?(.*)$').firstMatch(trimmed);
  if (quote != null) {
    return (kind: NoteBlockKind.quote, text: quote.group(1)!, props: const {});
  }
  if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
    return (kind: NoteBlockKind.divider, text: '', props: const {});
  }
  return (kind: NoteBlockKind.paragraph, text: trimmed, props: const {});
}

/// Pasted text as blocks: one per line, code fences kept together as one
/// code block, blank lines dropped.
List<({NoteBlockKind kind, String text, Map<String, Object?> props})>
parsePastedText(String pasted) {
  final lines = pasted
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final blocks =
      <({NoteBlockKind kind, String text, Map<String, Object?> props})>[];
  var inCode = false;
  final code = <String>[];
  String language = '';
  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        blocks.add((
          kind: NoteBlockKind.code,
          text: code.join('\n'),
          props: language.isEmpty ? const {} : {'lang': language},
        ));
        code.clear();
        language = '';
        inCode = false;
      } else {
        inCode = true;
        language = line.trimLeft().substring(3).trim();
      }
      continue;
    }
    if (inCode) {
      code.add(line);
      continue;
    }
    if (line.trim().isEmpty) {
      continue;
    }
    blocks.add(parseLine(line));
  }
  if (inCode) {
    blocks.add((
      kind: NoteBlockKind.code,
      text: code.join('\n'),
      props: language.isEmpty ? const {} : {'lang': language},
    ));
  }
  return blocks;
}

/// The number shown for each numbered block of [blocks] (null for others):
/// runs of numbered blocks count 1, 2, 3 and start again after any other
/// kind of block.
List<int?> listNumbers(List<NoteBlock> blocks) {
  final numbers = <int?>[];
  var count = 0;
  for (final block in blocks) {
    if (block.kind == NoteBlockKind.numbered) {
      count++;
      numbers.add(count);
    } else {
      count = 0;
      numbers.add(null);
    }
  }
  return numbers;
}

/// Markdown for a note, for copying or exporting.
String noteToMarkdown(String title, List<NoteBlock> blocks) {
  final buffer = StringBuffer();
  if (title.trim().isNotEmpty) {
    buffer.writeln('# ${title.trim()}');
    buffer.writeln();
  }
  final numbers = listNumbers(blocks);
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    final text = _inlineMarkdown(block);
    switch (block.kind) {
      case NoteBlockKind.heading1:
        buffer.writeln('# $text');
      case NoteBlockKind.heading2:
        buffer.writeln('## $text');
      case NoteBlockKind.heading3:
        buffer.writeln('### $text');
      case NoteBlockKind.bullet:
        buffer.writeln('- $text');
      case NoteBlockKind.numbered:
        buffer.writeln('${numbers[i]}. $text');
      case NoteBlockKind.todo:
        buffer.writeln('- [${block.checked ? 'x' : ' '}] $text');
      case NoteBlockKind.quote:
        buffer.writeln('> $text');
      case NoteBlockKind.code:
        buffer
          ..writeln('```${block.props['lang'] ?? ''}')
          ..writeln(block.text)
          ..writeln('```');
      case NoteBlockKind.divider:
        buffer.writeln('---');
      case NoteBlockKind.image:
        buffer.writeln('![${block.props['name'] ?? 'picture'}]');
      case NoteBlockKind.table:
        buffer.write(tableToMarkdown(NoteTable.fromProps(block.props)));
      case NoteBlockKind.paragraph:
        buffer.writeln(text);
    }
    if (!(block.kind.isListItem &&
        i + 1 < blocks.length &&
        blocks[i + 1].kind.isListItem)) {
      buffer.writeln();
    }
  }
  return buffer.toString().trimRight();
}

/// A table as a GitHub style Markdown table. Pipes and line breaks in a cell
/// are escaped. A table without a heading row gets an empty one, because
/// Markdown tables always have one.
String tableToMarkdown(NoteTable table) {
  String cell(String text) => text
      .replaceAll('\\', '\\\\')
      .replaceAll('|', '\\|')
      .replaceAll(RegExp(r'\r?\n'), '<br>');
  String line(List<String> cells) => '| ${cells.map(cell).join(' | ')} |';
  final rows = table.textRows;
  final width = table.columns.length;
  final buffer = StringBuffer();
  final head = table.header ? rows.first : List.filled(width, '');
  buffer.writeln(line(head));
  buffer.writeln('| ${List.filled(width, '---').join(' | ')} |');
  for (final row in table.header ? rows.skip(1) : rows) {
    buffer.writeln(line(row));
  }
  return buffer.toString();
}

String _inlineMarkdown(NoteBlock block) {
  if (block.marks.isEmpty) {
    return block.text;
  }
  final opens = <int, List<String>>{};
  final closes = <int, List<String>>{};
  for (final mark in block.marks) {
    final (open, close) = switch (mark.type) {
      NoteMark.bold => ('**', '**'),
      NoteMark.italic => ('_', '_'),
      NoteMark.strike => ('~~', '~~'),
      NoteMark.code => ('`', '`'),
      final type when type.startsWith(NoteMark.linkPrefix) => (
        '[',
        '](${type.substring(NoteMark.linkPrefix.length)})',
      ),
      _ => ('', ''),
    };
    if (open.isEmpty) {
      continue;
    }
    opens.putIfAbsent(mark.start, () => []).add(open);
    closes.putIfAbsent(mark.end, () => []).insert(0, close);
  }
  final buffer = StringBuffer();
  for (var i = 0; i <= block.text.length; i++) {
    for (final close in closes[i] ?? const <String>[]) {
      buffer.write(close);
    }
    for (final open in opens[i] ?? const <String>[]) {
      buffer.write(open);
    }
    if (i < block.text.length) {
      buffer.write(block.text[i]);
    }
  }
  return buffer.toString();
}
