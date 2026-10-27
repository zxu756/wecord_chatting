import 'dart:math' as math;

/// The on-device model has a small context window (about 4,000 tokens for the
/// instructions, the text and the answer together), so long texts go to it in
/// pieces. Nothing here touches the model.

/// The most one request to the model carries, in estimated tokens. The rest
/// of the window is for the instructions and the answer.
const onDeviceInputBudget = 1500;

/// A rough count of the tokens in [text]: about a third of a token for each
/// ASCII character, and over one for each other character (Chinese, Japanese,
/// Korean and emoji cost about a token or more each). An over-estimate is
/// safe; an under-estimate would overflow the window.
int estimateTokens(String text) {
  var ascii = 0;
  var other = 0;
  for (final unit in text.runes) {
    if (unit < 128) {
      ascii++;
    } else {
      other++;
    }
  }
  return (ascii * 0.35).ceil() + (other * 1.4).ceil();
}

/// One piece of a long text: its [text] without trailing whitespace, and
/// the whitespace that followed it in the original.
class TextPiece {
  const TextPiece(this.text, this.gap);

  final String text;
  final String gap;
}

final _segment = RegExp(r'[^\n.!?。！？]*(?:[.!?。！？]+["”’）)」』]*|\n+|$)\s*');

/// [text] cut into pieces of at most [budget] estimated tokens, at line breaks
/// and sentence ends where there are any (and anywhere when a sentence is
/// longer than that). Joining the pieces with their gaps gives [text] back,
/// apart from whitespace at its ends.
List<TextPiece> splitText(String text, {int budget = onDeviceInputBudget}) {
  final source = text.trim();
  if (source.isEmpty) {
    return const [];
  }
  if (estimateTokens(source) <= budget) {
    return [TextPiece(source, '')];
  }
  // Sentences (with the whitespace after them), then packed up to the budget.
  final sentences = <String>[
    for (final match in _segment.allMatches(source))
      if (match.group(0)!.isNotEmpty) match.group(0)!,
  ];
  final pieces = <TextPiece>[];
  var current = StringBuffer();
  var used = 0;

  void flush() {
    final raw = current.toString();
    current = StringBuffer();
    used = 0;
    final trimmed = raw.trimRight();
    if (trimmed.isNotEmpty) {
      pieces.add(TextPiece(trimmed, raw.substring(trimmed.length)));
    }
  }

  for (final sentence in sentences) {
    final cost = estimateTokens(sentence);
    if (cost > budget) {
      flush();
      pieces.addAll(_hardCut(sentence, budget));
      continue;
    }
    if (used + cost > budget) {
      flush();
    }
    current.write(sentence);
    used += cost;
  }
  flush();
  return pieces;
}

/// [sentence] cut by characters, for a run with no break in it.
List<TextPiece> _hardCut(String sentence, int budget) {
  final pieces = <TextPiece>[];
  final runes = sentence.trimRight().runes.toList();
  final gap = sentence.substring(sentence.trimRight().length);
  var start = 0;
  while (start < runes.length) {
    var end = start;
    var used = 0.0;
    while (end < runes.length) {
      final cost = runes[end] < 128 ? 0.35 : 1.4;
      if (used + cost > budget && end > start) {
        break;
      }
      used += cost;
      end++;
    }
    pieces.add(
      TextPiece(
        String.fromCharCodes(runes.sublist(start, end)),
        end == runes.length ? gap : '',
      ),
    );
    start = end;
  }
  return pieces;
}

/// [parts] (the answers for the pieces of one text) joined the way the pieces
/// were cut.
String joinPieces(List<TextPiece> pieces, List<String> parts) {
  final buffer = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    buffer.write(parts[i].trim());
    if (i < parts.length - 1) {
      final gap = pieces[i].gap;
      buffer.write(gap.isEmpty ? ' ' : gap);
    }
  }
  return buffer.toString();
}

/// [lines] (chat lines, oldest first) in groups of at most [budget] estimated
/// tokens, in order. A line that is longer than the budget goes alone, cut.
List<List<String>> groupLines(
  List<String> lines, {
  int budget = onDeviceInputBudget,
}) {
  final groups = <List<String>>[];
  var current = <String>[];
  var used = 0;
  for (var line in lines) {
    var cost = estimateTokens(line) + 1;
    if (cost > budget) {
      line = _clipTo(line, budget);
      cost = estimateTokens(line) + 1;
    }
    if (current.isNotEmpty && used + cost > budget) {
      groups.add(current);
      current = <String>[];
      used = 0;
    }
    current.add(line);
    used += cost;
  }
  if (current.isNotEmpty) {
    groups.add(current);
  }
  return groups;
}

String _clipTo(String line, int budget) {
  final runes = line.runes.toList();
  final keep = math.max(1, (budget / 1.4).floor() - 1);
  if (runes.length <= keep) {
    return line;
  }
  return '${String.fromCharCodes(runes.sublist(0, keep))}…';
}

/// Control and bidirectional formatting characters, which the model's
/// prompts never need.
final _controlChars = RegExp(
  '[\\u0000-\\u0008\\u000b\\u000c\\u000e-\\u001f\\u007f-\\u009f'
  '\\u200b-\\u200f\\u202a-\\u202e\\u2066-\\u2069\\ufeff]',
);

/// [text] on one line with line breaks shown as a marker, so one message
/// cannot start a line that looks like another sender's.
String flattenForPrompt(String text) {
  return text
      .replaceAll(_controlChars, '')
      .replaceAll(RegExp(r'\s*\n+\s*'), ' ⏎ ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

String _clipChars(String text, int max) {
  final runes = text.runes.toList();
  return runes.length <= max
      ? text
      : '${String.fromCharCodes(runes.sublist(0, max))}…';
}

/// What one message adds to the chat log the model reads, mirroring the `ai`
/// function's `messageLine`: its text, or a note for pictures, files and the
/// like; null for a message with nothing to say.
String? onDeviceMessageLine({
  required String sender,
  required String type,
  required String body,
  String? fileName,
  String? botName,
}) {
  final text = flattenForPrompt(body);
  final described = switch (type) {
    'image' => text.isEmpty ? '[image]' : '[image] $text',
    'file' => () {
      final name = fileName == null ? '' : flattenForPrompt(fileName);
      final note = name.isEmpty ? '[file]' : '[file: $name]';
      return text.isEmpty ? note : '$note $text';
    }(),
    'voice' => '[voice message]',
    'poll' => '[poll]',
    'sticker' => '[sticker]',
    'system' => text.isEmpty ? '[notice]' : '[notice] $text',
    _ => text,
  };
  final line = _clipChars(described, 1200);
  if (line.isEmpty) {
    return null;
  }
  final name = botName != null && botName.trim().isNotEmpty
      ? '${flattenForPrompt(botName)} (bot)'
      : flattenForPrompt(sender);
  return '${_clipChars(name.isEmpty ? 'Someone' : name, 60)}: $line';
}
