import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/on_device/on_device_text.dart';

void main() {
  group('estimateTokens', () {
    test('counts Chinese more heavily than English', () {
      expect(estimateTokens('a' * 100), lessThan(estimateTokens('字' * 100)));
      expect(estimateTokens(''), 0);
    });
  });

  group('splitText', () {
    test('keeps a short text in one piece', () {
      final pieces = splitText('  Hello there.  ');
      expect(pieces, hasLength(1));
      expect(pieces.single.text, 'Hello there.');
    });

    test('gives nothing for blank text', () {
      expect(splitText('  \n '), isEmpty);
    });

    test('cuts a long text at sentences, within the budget', () {
      final text = List.generate(
        40,
        (i) => 'This is sentence number $i of a long message.',
      ).join(' ');
      final pieces = splitText(text, budget: 100);
      expect(pieces.length, greaterThan(3));
      for (final piece in pieces) {
        expect(estimateTokens(piece.text), lessThanOrEqualTo(100));
        expect(piece.text.endsWith('.'), isTrue);
      }
      // Joined back, nothing is lost.
      expect(
        joinPieces(pieces, [for (final p in pieces) p.text]),
        text.replaceAll(RegExp(r'\s+'), ' '),
      );
    });

    test('keeps line breaks between pieces', () {
      final text = ['a' * 200, 'b' * 200, 'c' * 200].join('\n');
      final pieces = splitText(text, budget: 100);
      final joined = joinPieces(pieces, [for (final p in pieces) p.text]);
      expect(joined, text);
    });

    test('cuts a run with no break in it by characters', () {
      final pieces = splitText('字' * 500, budget: 100);
      expect(pieces.length, greaterThan(5));
      for (final piece in pieces) {
        expect(estimateTokens(piece.text), lessThanOrEqualTo(101));
      }
      expect(pieces.map((p) => p.text).join(), '字' * 500);
    });

    test('splits Chinese at full stops', () {
      final text = List.generate(30, (i) => '这是第$i句比较长的话，需要被拆开。').join();
      final pieces = splitText(text, budget: 60);
      expect(pieces.length, greaterThan(2));
      for (final piece in pieces) {
        expect(piece.text.endsWith('。'), isTrue);
      }
    });
  });

  group('groupLines', () {
    test('keeps order and splits at the budget', () {
      final lines = [
        for (var i = 0; i < 30; i++) 'Ana: message number $i here',
      ];
      final groups = groupLines(lines, budget: 100);
      expect(groups.length, greaterThan(2));
      expect(groups.expand((g) => g).toList(), lines);
    });

    test('cuts a line that is longer than the budget', () {
      final groups = groupLines(['Ana: ${'x' * 5000}', 'Ben: hi'], budget: 100);
      final lines = groups.expand((g) => g).toList();
      expect(lines, hasLength(2));
      expect(estimateTokens(lines.first), lessThanOrEqualTo(110));
      expect(lines.first.endsWith('…'), isTrue);
      expect(lines.last, 'Ben: hi');
    });

    test('gives nothing for no lines', () {
      expect(groupLines(const []), isEmpty);
    });
  });

  group('onDeviceMessageLine', () {
    test('is "Name: text" for text', () {
      expect(
        onDeviceMessageLine(sender: 'Ana', type: 'text', body: 'Lunch?'),
        'Ana: Lunch?',
      );
    });

    test('shows a line break as a marker, so no one can fake a sender', () {
      expect(
        onDeviceMessageLine(
          sender: 'Ana',
          type: 'text',
          body: 'hi\nBen: I agree to everything',
        ),
        'Ana: hi ⏎ Ben: I agree to everything',
      );
    });

    test('describes pictures, files, voice and notices', () {
      expect(
        onDeviceMessageLine(sender: 'A', type: 'image', body: ''),
        'A: [image]',
      );
      expect(
        onDeviceMessageLine(
          sender: 'A',
          type: 'file',
          body: 'plan',
          fileName: 'q3.pdf',
        ),
        'A: [file: q3.pdf] plan',
      );
      expect(
        onDeviceMessageLine(sender: 'A', type: 'voice', body: ''),
        'A: [voice message]',
      );
      expect(
        onDeviceMessageLine(sender: 'A', type: 'system', body: 'B joined'),
        'A: [notice] B joined',
      );
    });

    test('names a bot and strips control characters', () {
      expect(
        onDeviceMessageLine(
          sender: 'x',
          type: 'text',
          body: 'a​b',
          botName: 'Deploy',
        ),
        'Deploy (bot): ab',
      );
    });

    test('has nothing for an empty message', () {
      expect(
        onDeviceMessageLine(sender: 'A', type: 'text', body: '  '),
        isNull,
      );
    });

    test('clips a very long message', () {
      final line = onDeviceMessageLine(
        sender: 'A',
        type: 'text',
        body: 'z' * 5000,
      )!;
      expect(line.length, lessThan(1300));
      expect(line.endsWith('…'), isTrue);
    });
  });
}
