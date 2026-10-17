import 'package:wecord/features/chats/time_tokens/time_token.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// A small Discord-flavoured markdown dialect for chat messages.
///
/// Supported: `**bold**`, `*italic*` / `_italic_`, `__underline__`,
/// `~~strike~~`, `` `inline code` ``, fenced ```` ``` ```` code blocks,
/// `> quote` lines, `||spoiler||`, bare http(s) links, `\` escapes and
/// custom emoji tokens `<:name:uuid>` and time tokens `<t:unix:style>`.
/// Anything that does not close stays literal text. There is no HTML.

enum MarkdownStyle { bold, italic, underline, strikethrough, spoiler }

sealed class MarkdownInline {
  const MarkdownInline();
}

final class MarkdownText extends MarkdownInline {
  const MarkdownText(this.text);

  final String text;
}

final class MarkdownStyled extends MarkdownInline {
  const MarkdownStyled(this.style, this.children);

  final MarkdownStyle style;
  final List<MarkdownInline> children;
}

final class MarkdownInlineCode extends MarkdownInline {
  const MarkdownInlineCode(this.code);

  final String code;
}

final class MarkdownLink extends MarkdownInline {
  const MarkdownLink(this.url);

  final String url;
}

/// A circle's custom emoji, written `<:name:uuid>`.
final class MarkdownCustomEmoji extends MarkdownInline {
  const MarkdownCustomEmoji(this.name, this.id);

  final String name;
  final String id;
}

/// A moment written `<t:unix>` or `<t:unix:style>`, shown in each reader's
/// own time zone.
final class MarkdownTimeToken extends MarkdownInline {
  const MarkdownTimeToken(this.token);

  final TimeToken token;
}

final class MarkdownMention extends MarkdownInline {
  const MarkdownMention(this.text, this.mention);

  final String text;
  final MessageMention mention;
}

sealed class MarkdownBlock {
  const MarkdownBlock();
}

final class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.children);

  final List<MarkdownInline> children;
}

/// Consecutive `> ` lines; lines are separated by `\n` text nodes.
final class MarkdownQuote extends MarkdownBlock {
  const MarkdownQuote(this.children);

  final List<MarkdownInline> children;
}

final class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock(this.code, {this.language});

  final String code;
  final String? language;
}

/// Parses [body] into blocks. [mentions] are offsets into [body]; a mention
/// renders atomically wherever it is not inside code.
List<MarkdownBlock> parseMessageMarkdown(
  String body, {
  List<MessageMention> mentions = const <MessageMention>[],
}) {
  return _MarkdownParser(body, mentions).parse();
}

/// [body] without markdown markers, for one-line previews and notifications.
/// Spoiler contents are hidden.
String plainTextFromMarkdown(String body) {
  final buffer = StringBuffer();
  final blocks = parseMessageMarkdown(body);
  for (var index = 0; index < blocks.length; index++) {
    if (index > 0) {
      buffer.write('\n');
    }
    switch (blocks[index]) {
      case MarkdownParagraph(:final children):
      case MarkdownQuote(:final children):
        _writePlain(buffer, children);
      case MarkdownCodeBlock(:final code):
        buffer.write(code);
    }
  }
  return buffer.toString();
}

/// The first http(s) link outside code, or null.
String? firstLinkInMarkdown(
  String body, {
  List<MessageMention> mentions = const <MessageMention>[],
}) {
  String? search(List<MarkdownInline> nodes) {
    for (final node in nodes) {
      switch (node) {
        case MarkdownLink(:final url):
          return url;
        case MarkdownStyled(:final children):
          final url = search(children);
          if (url != null) {
            return url;
          }
        case MarkdownText() ||
            MarkdownInlineCode() ||
            MarkdownMention() ||
            MarkdownTimeToken() ||
            MarkdownCustomEmoji():
          break;
      }
    }
    return null;
  }

  for (final block in parseMessageMarkdown(body, mentions: mentions)) {
    final url = switch (block) {
      MarkdownParagraph(:final children) => search(children),
      MarkdownQuote(:final children) => search(children),
      MarkdownCodeBlock() => null,
    };
    if (url != null) {
      return url;
    }
  }
  return null;
}

String get spoilerPlaceholder => tr('[spoiler]');

/// The text [nodes] display, with spoiler contents included.
String plainTextOfInlines(List<MarkdownInline> nodes) {
  final buffer = StringBuffer();
  _writePlain(buffer, nodes, hideSpoilers: false);
  return buffer.toString();
}

void _writePlain(
  StringBuffer buffer,
  List<MarkdownInline> nodes, {
  bool hideSpoilers = true,
}) {
  for (final node in nodes) {
    switch (node) {
      case MarkdownText(:final text):
        buffer.write(text);
      case MarkdownInlineCode(:final code):
        buffer.write(code);
      case MarkdownLink(:final url):
        buffer.write(url);
      case MarkdownMention(:final text):
        buffer.write(text);
      case MarkdownCustomEmoji(:final name):
        buffer.write(':$name:');
      case MarkdownTimeToken(:final token):
        buffer.write(formatTimeToken(token, now: DateTime.now()));
      case MarkdownStyled(style: MarkdownStyle.spoiler) when hideSpoilers:
        buffer.write(spoilerPlaceholder);
      case MarkdownStyled(:final children):
        _writePlain(buffer, children, hideSpoilers: hideSpoilers);
    }
  }
}

const _fence = '```';

/// Nested styles deeper than this stay literal.
const _maxDepth = 16;

const _escapable = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';

final _urlPattern = RegExp(r'https?://[^\s<]+', caseSensitive: false);
final _customEmojiPattern = RegExp(
  r'<:([a-z0-9_]{2,32}):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})>',
);
final _languagePattern = RegExp(r'^[A-Za-z0-9_+.#-]+$');

class _MarkdownParser {
  _MarkdownParser(this.source, List<MessageMention> mentions)
    : _mentionsByStart = {
        for (final mention in mentions)
          if (mention.start >= 0 &&
              mention.end > mention.start &&
              mention.end <= source.length)
            mention.start: mention,
      };

  final String source;
  final Map<int, MessageMention> _mentionsByStart;

  List<MarkdownBlock> parse() {
    final blocks = <MarkdownBlock>[];
    var segmentStart = 0;
    var index = 0;
    while (index < source.length) {
      if (_isEscape(index)) {
        index += 2;
        continue;
      }
      if (source.startsWith(_fence, index)) {
        final close = source.indexOf(_fence, index + _fence.length);
        if (close != -1) {
          var textEnd = index;
          if (textEnd > segmentStart && source[textEnd - 1] == '\n') {
            textEnd--;
          }
          _addTextBlocks(blocks, segmentStart, textEnd);
          blocks.add(_codeBlock(index + _fence.length, close));
          index = close + _fence.length;
          if (index < source.length && source[index] == '\n') {
            index++;
          }
          segmentStart = index;
          continue;
        }
      }
      index++;
    }
    _addTextBlocks(blocks, segmentStart, source.length);
    return blocks;
  }

  MarkdownCodeBlock _codeBlock(int start, int end) {
    var content = source.substring(start, end);
    String? language;
    final newline = content.indexOf('\n');
    if (newline != -1) {
      final firstLine = content.substring(0, newline).trim();
      if (firstLine.isEmpty) {
        content = content.substring(newline + 1);
      } else if (_languagePattern.hasMatch(firstLine) &&
          content.substring(newline + 1).trim().isNotEmpty) {
        language = firstLine;
        content = content.substring(newline + 1);
      }
    }
    if (content.endsWith('\n')) {
      content = content.substring(0, content.length - 1);
    }
    return MarkdownCodeBlock(content, language: language);
  }

  void _addTextBlocks(List<MarkdownBlock> blocks, int start, int end) {
    if (start >= end) {
      return;
    }
    var lineStart = start;
    var paragraphStart = -1;
    var quoteLines = <(int, int)>[];

    void flushParagraph(int paragraphEnd) {
      if (paragraphStart == -1) {
        return;
      }
      final children = _parseInline(paragraphStart, paragraphEnd, 0);
      if (children.isNotEmpty) {
        blocks.add(MarkdownParagraph(children));
      }
      paragraphStart = -1;
    }

    void flushQuote() {
      if (quoteLines.isEmpty) {
        return;
      }
      final children = <MarkdownInline>[];
      for (var line = 0; line < quoteLines.length; line++) {
        if (line > 0) {
          children.add(const MarkdownText('\n'));
        }
        final (lineFrom, lineTo) = quoteLines[line];
        children.addAll(_parseInline(lineFrom, lineTo, 0));
      }
      blocks.add(MarkdownQuote(_mergeText(children)));
      quoteLines = <(int, int)>[];
    }

    while (lineStart <= end) {
      var lineEnd = source.indexOf('\n', lineStart);
      if (lineEnd == -1 || lineEnd > end) {
        lineEnd = end;
      }
      final quoteContentStart = _quoteContentStart(lineStart, lineEnd);
      if (quoteContentStart != null) {
        // The newline before a quote belongs to neither block.
        flushParagraph(lineStart > start ? lineStart - 1 : lineStart);
        quoteLines.add((quoteContentStart, lineEnd));
      } else {
        flushQuote();
        if (paragraphStart == -1) {
          paragraphStart = lineStart;
        }
      }
      if (lineEnd >= end) {
        break;
      }
      lineStart = lineEnd + 1;
    }
    flushQuote();
    flushParagraph(end);
  }

  int? _quoteContentStart(int lineStart, int lineEnd) {
    if (lineStart >= lineEnd || source[lineStart] != '>') {
      return null;
    }
    if (lineStart + 1 == lineEnd) {
      return lineEnd;
    }
    if (source[lineStart + 1] == ' ') {
      return lineStart + 2;
    }
    return null;
  }

  bool _isEscape(int index) {
    return source[index] == r'\' &&
        index + 1 < source.length &&
        _escapable.contains(source[index + 1]);
  }

  List<MarkdownInline> _parseInline(int start, int end, int depth) {
    final nodes = <MarkdownInline>[];
    final text = StringBuffer();

    void flushText() {
      if (text.isNotEmpty) {
        nodes.add(MarkdownText(text.toString()));
        text.clear();
      }
    }

    var index = start;
    while (index < end) {
      final char = source[index];

      if (char == r'\' && index + 1 < end && _isEscape(index)) {
        text.write(source[index + 1]);
        index += 2;
        continue;
      }

      final mention = _mentionAt(index, end);
      if (mention != null) {
        flushText();
        nodes.add(
          MarkdownMention(source.substring(index, mention.end), mention),
        );
        index = mention.end;
        continue;
      }

      if (char == '<') {
        final emoji = _customEmojiAt(index, end);
        if (emoji != null) {
          flushText();
          nodes.add(MarkdownCustomEmoji(emoji.group(1)!, emoji.group(2)!));
          index = emoji.end;
          continue;
        }
        final time = timeTokenAt(source, index);
        if (time != null && time.end <= end) {
          flushText();
          nodes.add(MarkdownTimeToken(time.token));
          index = time.end;
          continue;
        }
      }

      if (char == '`') {
        final code = _codeSpanAt(index, end);
        if (code != null) {
          flushText();
          nodes.add(MarkdownInlineCode(code.$1));
          index = code.$2;
        } else {
          final run = _runLength(index, end);
          text.write(source.substring(index, index + run));
          index += run;
        }
        continue;
      }

      final urlEnd = _urlAt(index, end);
      if (urlEnd != null) {
        flushText();
        nodes.add(MarkdownLink(source.substring(index, urlEnd)));
        index = urlEnd;
        continue;
      }

      if (depth < _maxDepth && _isDelimiterChar(char)) {
        final styled = _styledAt(index, end, depth);
        if (styled != null) {
          if (styled.literalPrefix > 0) {
            text.write(source.substring(index, index + styled.literalPrefix));
          }
          flushText();
          nodes.add(styled.node);
          index = styled.end;
          continue;
        }
        final run = _runLength(index, end);
        text.write(source.substring(index, index + run));
        index += run;
        continue;
      }

      text.write(char);
      index++;
    }
    flushText();
    return nodes;
  }

  MessageMention? _mentionAt(int index, int end) {
    final mention = _mentionsByStart[index];
    if (mention == null || mention.end > end) {
      return null;
    }
    return mention;
  }

  /// A custom emoji token starting at [index] and ending by [end].
  Match? _customEmojiAt(int index, int end) {
    if (source[index] != '<') {
      return null;
    }
    final match = _customEmojiPattern.matchAsPrefix(source, index);
    if (match == null || match.end > end) {
      return null;
    }
    return match;
  }

  bool _isDelimiterChar(String char) {
    return char == '*' || char == '_' || char == '~' || char == '|';
  }

  int _runLength(int index, int end) {
    final char = source[index];
    var cursor = index;
    while (cursor < end && source[cursor] == char) {
      cursor++;
    }
    return cursor - index;
  }

  /// An inline code span opening at [index]: (content, index after closer).
  (String, int)? _codeSpanAt(int index, int end) {
    final run = _runLength(index, end);
    var cursor = index + run;
    while (cursor < end) {
      if (source[cursor] != '`') {
        cursor++;
        continue;
      }
      final closeRun = _runLength(cursor, end);
      if (closeRun == run) {
        var content = source.substring(index + run, cursor);
        if (content.length > 2 &&
            content.startsWith(' ') &&
            content.endsWith(' ') &&
            content.trim().isNotEmpty) {
          content = content.substring(1, content.length - 1);
        }
        if (content.isEmpty) {
          return null;
        }
        return (content, cursor + closeRun);
      }
      cursor += closeRun;
    }
    return null;
  }

  /// End of a bare http(s) link starting at [index], or null.
  int? _urlAt(int index, int end) {
    final char = source[index];
    if (char != 'h' && char != 'H') {
      return null;
    }
    if (index > 0 && _isWordChar(source[index - 1])) {
      return null;
    }
    final match = _urlPattern.matchAsPrefix(source, index);
    if (match == null) {
      return null;
    }
    var urlEnd = match.end < end ? match.end : end;
    while (urlEnd > index) {
      final last = source[urlEnd - 1];
      if (r'''.,:;!?'"*_~|>]'''.contains(last)) {
        urlEnd--;
        continue;
      }
      if (last == ')') {
        final candidate = source.substring(index, urlEnd);
        final opens = '('.allMatches(candidate).length;
        final closes = ')'.allMatches(candidate).length;
        if (closes > opens) {
          urlEnd--;
          continue;
        }
      }
      break;
    }
    final uri = Uri.tryParse(source.substring(index, urlEnd));
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return urlEnd;
  }

  _StyledMatch? _styledAt(int index, int end, int depth) {
    final char = source[index];
    final run = _runLength(index, end);
    switch (char) {
      case '*':
        if (run >= 2) {
          final bold = _tryStyle(index, end, depth, '**', MarkdownStyle.bold);
          if (bold != null) {
            return bold;
          }
        }
        // Fall back to italic from the last star of the run.
        final opener = index + run - 1;
        final italic = _tryStyle(opener, end, depth, '*', MarkdownStyle.italic);
        return italic?.withLiteralPrefix(opener - index);
      case '_':
        if (run >= 2) {
          final underline = _tryStyle(
            index,
            end,
            depth,
            '__',
            MarkdownStyle.underline,
          );
          if (underline != null) {
            return underline;
          }
        }
        final opener = index + run - 1;
        final italic = _tryStyle(opener, end, depth, '_', MarkdownStyle.italic);
        return italic?.withLiteralPrefix(opener - index);
      case '~':
        if (run < 2) {
          return null;
        }
        return _tryStyle(index, end, depth, '~~', MarkdownStyle.strikethrough);
      case '|':
        if (run < 2) {
          return null;
        }
        return _tryStyle(index, end, depth, '||', MarkdownStyle.spoiler);
    }
    return null;
  }

  _StyledMatch? _tryStyle(
    int opener,
    int end,
    int depth,
    String delimiter,
    MarkdownStyle style,
  ) {
    final contentStart = opener + delimiter.length;
    if (contentStart >= end) {
      return null;
    }
    if (!_validOpener(opener, contentStart, delimiter)) {
      return null;
    }
    final closer = _findCloser(contentStart, end, delimiter);
    if (closer == null) {
      return null;
    }
    final children = _parseInline(contentStart, closer, depth + 1);
    return _StyledMatch(
      MarkdownStyled(style, children),
      closer + delimiter.length,
    );
  }

  bool _validOpener(int opener, int contentStart, String delimiter) {
    if (delimiter == '*') {
      return !_isWhitespace(source[contentStart]);
    }
    if (delimiter == '_') {
      return (opener == 0 || !_isWordChar(source[opener - 1])) &&
          !_isWhitespace(source[contentStart]);
    }
    return true;
  }

  /// The closing delimiter after [start], skipping escapes, code spans,
  /// mentions, custom emoji and links, which are opaque to emphasis.
  int? _findCloser(int start, int end, String delimiter) {
    final char = delimiter[0];
    final length = delimiter.length;
    var cursor = start;
    while (cursor < end) {
      if (_isEscape(cursor)) {
        cursor += 2;
        continue;
      }
      final mention = _mentionAt(cursor, end);
      if (mention != null) {
        cursor = mention.end;
        continue;
      }
      final emoji = _customEmojiAt(cursor, end);
      if (emoji != null) {
        cursor = emoji.end;
        continue;
      }
      final time = timeTokenAt(source, cursor);
      if (time != null && time.end <= end) {
        cursor = time.end;
        continue;
      }
      final current = source[cursor];
      if (current == '`') {
        final code = _codeSpanAt(cursor, end);
        cursor = code?.$2 ?? cursor + _runLength(cursor, end);
        continue;
      }
      final urlEnd = _urlAt(cursor, end);
      if (urlEnd != null) {
        cursor = urlEnd;
        continue;
      }
      if (current != char) {
        cursor++;
        continue;
      }
      final run = _runLength(cursor, end);
      // A run longer than the delimiter closes with its last characters, so
      // `***both***` closes bold around an italic.
      final closer = run == length
          ? cursor
          : run >= 3
          ? cursor + run - length
          : null;
      if (closer != null &&
          closer > start &&
          _validCloser(closer, end, delimiter)) {
        return closer;
      }
      cursor += run;
    }
    return null;
  }

  bool _validCloser(int closer, int end, String delimiter) {
    if (delimiter == '*') {
      return !_isWhitespace(source[closer - 1]);
    }
    if (delimiter == '_') {
      final after = closer + 1;
      return !_isWhitespace(source[closer - 1]) &&
          (after >= source.length || !_isWordChar(source[after]));
    }
    return true;
  }
}

class _StyledMatch {
  const _StyledMatch(this.node, this.end, {this.literalPrefix = 0});

  final MarkdownStyled node;
  final int end;

  /// Delimiter characters before the opener that stay literal.
  final int literalPrefix;

  _StyledMatch withLiteralPrefix(int prefix) {
    return _StyledMatch(node, end, literalPrefix: prefix);
  }
}

List<MarkdownInline> _mergeText(List<MarkdownInline> nodes) {
  final merged = <MarkdownInline>[];
  for (final node in nodes) {
    final previous = merged.isEmpty ? null : merged.last;
    if (node is MarkdownText && previous is MarkdownText) {
      merged[merged.length - 1] = MarkdownText(previous.text + node.text);
    } else {
      merged.add(node);
    }
  }
  return merged;
}

bool _isWhitespace(String char) => char.trim().isEmpty;

bool _isWordChar(String char) {
  final unit = char.codeUnitAt(0);
  return (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5a) ||
      (unit >= 0x61 && unit <= 0x7a) ||
      unit == 0x5f;
}
