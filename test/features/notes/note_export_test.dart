import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/notes/export/note_file_exporter.dart';
import 'package:wecord/features/notes/export/note_pdf.dart';
import 'package:wecord/features/notes/export/simple_pdf.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_table.dart';

Uint8List fakeJpeg() => Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 0xFF, 0xD9, //
]);

String text(Uint8List bytes) => latin1.decode(bytes);

void main() {
  group('file names', () {
    test('lose what file systems dislike and stay short', () {
      expect(noteExportFileName('Trip plan', 'md'), 'Trip plan.md');
      expect(
        noteExportFileName('a/b\\c:d*e?f"g<h>i|j', 'pdf'),
        'a b c d e f g h i j.pdf',
      );
      expect(noteExportFileName('  ', 'md'), 'note.md');
      expect(noteExportFileName('', 'pdf'), 'note.pdf');
      expect(noteExportFileName('..hidden', 'md'), 'hidden.md');
      expect(noteExportFileName('旅行计划 \u{1F9F3}', 'md'), '旅行计划 \u{1F9F3}.md');
      expect(noteExportFileName('x' * 200, 'md').length, lessThanOrEqualTo(63));
      // Never cuts an emoji in half.
      final long = noteExportFileName('\u{1F9F3}' * 100, 'md');
      expect(long.runes.every((r) => r != 0xFFFD), isTrue);
    });
  });

  group('the PDF file', () {
    test('has a catalog, pages, pictures and a table that points at them', () {
      final bytes = buildImagePdf([
        PdfPageImage(jpeg: fakeJpeg(), pixelWidth: 1190, pixelHeight: 1684),
        PdfPageImage(jpeg: fakeJpeg(), pixelWidth: 1190, pixelHeight: 1684),
      ], title: 'Trip 旅行');
      final raw = text(bytes);
      expect(raw.startsWith('%PDF-1.4'), isTrue);
      expect(raw.trimRight().endsWith('%%EOF'), isTrue);
      expect(RegExp('/Type /Page ').allMatches(raw), hasLength(2));
      expect(raw, contains('/Count 2'));
      expect(raw, contains('/Filter /DCTDecode'));
      expect(raw, contains('/MediaBox [0 0 595 842]'));
      // The title is UTF-16 in hex, so Chinese survives.
      expect(raw, contains('/Title <FEFF'));

      // Every entry of the cross-reference table points at "N 0 obj".
      final xref = raw.lastIndexOf('\nxref\n') + 1;
      final startxref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(raw)!.group(1)!,
      );
      expect(startxref, xref);
      final entries = RegExp(
        r'(\d{10}) 00000 n ',
      ).allMatches(raw.substring(xref)).toList();
      expect(entries, hasLength(9));
      for (final (index, entry) in entries.indexed) {
        final offset = int.parse(entry.group(1)!);
        expect(raw.substring(offset).startsWith('${index + 1} 0 obj'), isTrue);
      }
      expect(raw, contains('/Size 10'));
    });

    test('keeps the pictures byte for byte', () {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, 0x00, 0x0A, 0x0D, 0xFF, 0xD9, //
      ]);
      final bytes = buildImagePdf([
        PdfPageImage(jpeg: jpeg, pixelWidth: 2, pixelHeight: 2),
      ]);
      var found = false;
      for (var i = 0; i + jpeg.length <= bytes.length; i++) {
        var same = true;
        for (var j = 0; j < jpeg.length; j++) {
          if (bytes[i + j] != jpeg[j]) {
            same = false;
            break;
          }
        }
        if (same) {
          found = true;
          break;
        }
      }
      expect(found, isTrue);
    });

    test('needs at least one page', () {
      expect(() => buildImagePdf(const []), throwsArgumentError);
    });
  });

  group('the note as a PDF', () {
    testWidgets('makes a page for a short note and more for a long one', (
      tester,
    ) async {
      final blocks = [
        const NoteBlock(
          id: 'a',
          pos: 'a',
          kind: NoteBlockKind.heading1,
          text: 'Saturday',
        ),
        const NoteBlock(
          id: 'b',
          pos: 'b',
          text: 'Leave at 7 and meet at the north lot.',
          marks: [NoteMark(0, 5, 'b'), NoteMark(6, 8, 'l:https://x.test')],
        ),
        const NoteBlock(
          id: 'c',
          pos: 'c',
          kind: NoteBlockKind.todo,
          text: 'Book the permit',
          props: {'checked': true},
        ),
        const NoteBlock(id: 'd', pos: 'd', kind: NoteBlockKind.divider),
        NoteBlock(
          id: 'e',
          pos: 'e',
          kind: NoteBlockKind.table,
          props: NoteTable.empty(newId: () => 'x${blocksCounter++}').toProps(),
        ),
        const NoteBlock(
          id: 'f',
          pos: 'f',
          kind: NoteBlockKind.image,
          props: {'name': 'map.png', 'path': 'n/m.png'},
        ),
        const NoteBlock(
          id: 'g',
          pos: 'g',
          kind: NoteBlockKind.code,
          text: 'let x = 1;\nlet y = 2;',
        ),
      ];
      final short = await tester.runAsync(
        () => buildNotePdf(title: 'Trip', icon: 'x', blocks: blocks),
      );
      expect(text(short!).startsWith('%PDF-1.4'), isTrue);
      expect(RegExp('/Type /Page ').allMatches(text(short)), hasLength(1));

      final long = await tester.runAsync(
        () => buildNotePdf(
          title: '旅行计划',
          icon: '',
          blocks: [
            for (var i = 0; i < 120; i++)
              NoteBlock(
                id: 'p$i',
                pos: i.toString().padLeft(4, '0'),
                text: 'Paragraph number $i with enough words to take a line.',
              ),
          ],
        ),
      );
      expect(
        RegExp('/Type /Page ').allMatches(text(long!)).length,
        greaterThan(1),
      );
    });

    testWidgets('an empty note still makes a page', (tester) async {
      final bytes = await tester.runAsync(
        () => buildNotePdf(title: '', icon: '', blocks: const []),
      );
      expect(RegExp('/Type /Page ').allMatches(text(bytes!)), hasLength(1));
    });
  });
}

var blocksCounter = 0;
