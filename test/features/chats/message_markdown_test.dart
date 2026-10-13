import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/shared/models/message.dart';

String describeInlines(List<MarkdownInline> nodes) {
  return nodes.map(describeInline).join();
}

String describeInline(MarkdownInline node) {
  return switch (node) {
    MarkdownText(:final text) => text,
    MarkdownInlineCode(:final code) => 'code($code)',
    MarkdownLink(:final url) => 'link($url)',
    MarkdownMention(:final text) => 'mention($text)',
    MarkdownCustomEmoji(:final name, :final id) => 'emoji($name,$id)',
    MarkdownStyled(:final style, :final children) =>
      '${_styleName(style)}(${describeInlines(children)})',
  };
}

String _styleName(MarkdownStyle style) {
  return switch (style) {
    MarkdownStyle.bold => 'b',
    MarkdownStyle.italic => 'i',
    MarkdownStyle.underline => 'u',
    MarkdownStyle.strikethrough => 's',
    MarkdownStyle.spoiler => 'spoiler',
  };
}

String describe(String body, {List<MessageMention> mentions = const []}) {
  return parseMessageMarkdown(body, mentions: mentions)
      .map((block) {
        return switch (block) {
          MarkdownParagraph(:final children) => describeInlines(children),
          MarkdownQuote(:final children) =>
            'quote[${describeInlines(children)}]',
          MarkdownCodeBlock(:final code, :final language) =>
            'codeblock${language == null ? '' : '<$language>'}[$code]',
        };
      })
      .join(' | ');
}

MessageMention mentionOf(String body, String token) {
  final start = body.indexOf(token);
  return MessageMention(
    userId: 'user-$token',
    displayName: token,
    start: start,
    end: start + token.length,
  );
}

void main() {
  group('parseMessageMarkdown inline styles', () {
    test('plain text stays one text node', () {
      expect(describe('hello world'), 'hello world');
      expect(describe(''), '');
    });

    test('parses each basic style', () {
      expect(describe('a **bold** b'), 'a b(bold) b');
      expect(describe('a *it* b'), 'a i(it) b');
      expect(describe('a _it_ b'), 'a i(it) b');
      expect(describe('a __under__ b'), 'a u(under) b');
      expect(describe('a ~~gone~~ b'), 'a s(gone) b');
      expect(describe('a ||secret|| b'), 'a spoiler(secret) b');
    });

    test('nests styles', () {
      expect(describe('**bold *and italic***'), 'b(bold i(and italic))');
      expect(describe('***both***'), 'b(i(both))');
      expect(describe('*a **b** c*'), 'i(a b(b) c)');
      expect(describe('__~~u and s~~__'), 'u(s(u and s))');
      expect(describe('||**hidden bold**||'), 'spoiler(b(hidden bold))');
    });

    test('unclosed markers stay literal', () {
      expect(describe('**not bold'), '**not bold');
      expect(describe('*not italic'), '*not italic');
      expect(describe('~~nope'), '~~nope');
      expect(describe('||nope'), '||nope');
      expect(describe('`nope'), '`nope');
      expect(describe('**a*'), '*i(a)');
      expect(
        describe('a single ~ tilde and | pipe'),
        'a single ~ tilde and | pipe',
      );
    });

    test('empty markers stay literal', () {
      expect(describe('****'), '****');
      expect(describe('||||'), '||||');
      expect(describe('``'), '``');
    });

    test('star italic needs non-space next to the markers', () {
      expect(describe('2 * 3 * 4'), '2 * 3 * 4');
      expect(describe('*a *'), '*a *');
    });

    test('underscore italic needs word boundaries', () {
      expect(describe('snake_case_word'), 'snake_case_word');
      expect(describe('call my_func_ now'), 'call my_func_ now');
      expect(describe('(_wrapped_)'), '(i(wrapped))');
    });
  });

  group('parseMessageMarkdown code', () {
    test('inline code does not format inside', () {
      expect(describe('run `**not bold**` now'), 'run code(**not bold**) now');
      expect(describe('`a_b_c`'), 'code(a_b_c)');
      expect(describe('``has ` tick``'), 'code(has ` tick)');
    });

    test('inline code hides its delimiters from an outer style', () {
      expect(describe('**bold `code**` end**'), 'b(bold code(code**) end)');
    });

    test('fenced code blocks keep their contents literal', () {
      expect(
        describe('before\n```\n**x** _y_\n```\nafter'),
        'before | codeblock[**x** _y_] | after',
      );
    });

    test('fenced code block language label is read and dropped', () {
      expect(describe('```dart\nprint(1);\n```'), 'codeblock<dart>[print(1);]');
      expect(describe('```inline code```'), 'codeblock[inline code]');
    });

    test('an unclosed fence stays literal', () {
      expect(describe('```not code'), '```not code');
    });

    test('mentions and links inside code stay code', () {
      const body = 'see `@alice https://a.example`';
      expect(
        describe(body, mentions: [mentionOf(body, '@alice')]),
        'see code(@alice https://a.example)',
      );
    });
  });

  group('parseMessageMarkdown quotes', () {
    test('groups consecutive quote lines', () {
      expect(describe('> one\n> **two**\nafter'), 'quote[one\nb(two)] | after');
    });

    test('text before a quote becomes its own paragraph', () {
      expect(describe('intro\n> quoted'), 'intro | quote[quoted]');
    });

    test('a marker without a space is not a quote', () {
      expect(describe('>not quote'), '>not quote');
      expect(describe('a > b'), 'a > b');
    });
  });

  group('parseMessageMarkdown escapes', () {
    test('backslash escapes markers', () {
      expect(describe(r'\*not italic\*'), '*not italic*');
      expect(describe(r'\*\*not bold\*\*'), '**not bold**');
      expect(describe(r'\||not spoiler||'), '||not spoiler||');
      expect(describe(r'\`not code`'), '`not code`');
      expect(describe(r'\> not quote'), '> not quote');
    });

    test('escaped markers do not close styles', () {
      expect(describe(r'**a\**b**'), 'b(a**b)');
    });

    test('backslash before ordinary text stays', () {
      expect(describe(r'C:\Users\me'), r'C:\Users\me');
      expect(describe(r'\\'), r'\');
    });

    test('escaped fence is not a code block', () {
      expect(describe(r'\```x```'), '```x```');
    });

    test('backslashes inside code are literal', () {
      expect(describe(r'`a\*b`'), r'code(a\*b)');
    });
  });

  group('parseMessageMarkdown links', () {
    test('autolinks http and https urls', () {
      expect(
        describe('go https://example.com/a?b=1 now'),
        'go link(https://example.com/a?b=1) now',
      );
      expect(describe('http://x.example'), 'link(http://x.example)');
    });

    test('trailing punctuation is not part of the link', () {
      expect(
        describe('see https://example.com.'),
        'see link(https://example.com).',
      );
      expect(
        describe('(https://example.com/wiki/A_(b))'),
        '(link(https://example.com/wiki/A_(b)))',
      );
    });

    test('links keep underscores and stars literal', () {
      expect(
        describe('https://example.com/_a_*b*'),
        'link(https://example.com/_a_*b)*',
      );
      expect(
        describe('**https://example.com**'),
        'b(link(https://example.com))',
      );
    });

    test('other schemes and embedded http are not links', () {
      expect(describe('ftp://example.com'), 'ftp://example.com');
      expect(describe('xhttps://example.com'), 'xhttps://example.com');
      expect(describe('https://'), 'https://');
    });

    test('firstLinkInMarkdown skips code', () {
      expect(
        firstLinkInMarkdown('`https://code.example` and https://real.example'),
        'https://real.example',
      );
      expect(firstLinkInMarkdown('```\nhttps://code.example\n```'), isNull);
      expect(firstLinkInMarkdown('no links'), isNull);
      expect(
        firstLinkInMarkdown('**bold https://bold.example**'),
        'https://bold.example',
      );
    });
  });

  group('parseMessageMarkdown mentions', () {
    test('mentions are atomic and keep their offsets', () {
      const body = 'hi @bob_smith_ there';
      expect(
        describe(body, mentions: [mentionOf(body, '@bob_smith_')]),
        'hi mention(@bob_smith_) there',
      );
    });

    test('mentions inside bold', () {
      const body = '**hey @alice**';
      expect(
        describe(body, mentions: [mentionOf(body, '@alice')]),
        'b(hey mention(@alice))',
      );
    });

    test('out of range mentions are ignored', () {
      const body = 'hi';
      expect(
        describe(
          body,
          mentions: const [
            MessageMention(userId: 'u', displayName: 'u', start: 1, end: 9),
          ],
        ),
        'hi',
      );
    });
  });

  group('plainTextFromMarkdown', () {
    test('strips markers and hides spoilers', () {
      expect(
        plainTextFromMarkdown('**bold** _it_ ~~s~~ `code` ||secret||'),
        'bold it s code $spoilerPlaceholder',
      );
    });

    test('keeps literal text, quotes and code blocks', () {
      expect(plainTextFromMarkdown('> quoted\n```\ncode\n```'), 'quoted\ncode');
      expect(plainTextFromMarkdown('2 * 3 * 4'), '2 * 3 * 4');
      expect(plainTextFromMarkdown(r'\*literal\*'), '*literal*');
    });
  });
}
