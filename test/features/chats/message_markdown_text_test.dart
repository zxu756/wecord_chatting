import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/shared/models/message.dart';

const _textColor = Color(0xFF123456);

Future<List<Uri>> pumpMarkdown(
  WidgetTester tester,
  String body, {
  List<MessageMention> mentions = const [],
}) async {
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        linkLauncherProvider.overrideWithValue((context, uri) async {
          opened.add(uri);
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageMarkdownText(
              body: body,
              mentions: mentions,
              color: _textColor,
            ),
          ),
        ),
      ),
    ),
  );
  return opened;
}

TextSpan spanWithText(WidgetTester tester, String text) {
  TextSpan? found;
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) {
        found ??= span;
        return false;
      }
      return true;
    });
  }
  expect(found, isNotNull, reason: 'no span with text "$text"');
  return found!;
}

/// The style [text] is painted with, merged down the span tree.
TextStyle effectiveStyle(WidgetTester tester, String text) {
  TextStyle? search(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) {
      return null;
    }
    final style = inherited.merge(span.style);
    if (span.text == text) {
      return style;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = search(child, style);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    final found = search(richText.text, const TextStyle());
    if (found != null) {
      return found;
    }
  }
  fail('no span with text "$text"');
}

void main() {
  testWidgets('plain bodies render as their text', (tester) async {
    await pumpMarkdown(tester, 'just words');

    expect(find.text('just words'), findsOneWidget);
  });

  testWidgets('styles render with matching text styles', (tester) async {
    await pumpMarkdown(tester, '**bold** and *it* and ~~gone~~ and `code`');

    final paragraph = tester.widget<RichText>(find.byType(RichText));
    expect(paragraph.text.toPlainText(), 'bold and it and gone and code');
    expect(effectiveStyle(tester, 'bold').fontWeight, FontWeight.w700);
    expect(effectiveStyle(tester, 'it').fontStyle, FontStyle.italic);
    expect(
      effectiveStyle(tester, 'gone').decoration,
      TextDecoration.lineThrough,
    );
    expect(effectiveStyle(tester, 'code').fontFamily, 'monospace');
    expect(effectiveStyle(tester, ' and ').fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('spoilers stay hidden until tapped', (tester) async {
    await pumpMarkdown(tester, 'the end: ||they win||');

    var spoiler = spanWithText(tester, 'they win');
    expect(spoiler.style?.backgroundColor, _textColor);
    expect(spoiler.style?.color, _textColor);

    await tester.tapOnText(find.textRange.ofSubstring('they win'));
    await tester.pump();

    spoiler = spanWithText(tester, 'they win');
    expect(spoiler.style?.backgroundColor, isNot(_textColor));
  });

  testWidgets('each spoiler reveals on its own', (tester) async {
    await pumpMarkdown(tester, '||first|| and ||second||');

    await tester.tapOnText(find.textRange.ofSubstring('second'));
    await tester.pump();

    expect(spanWithText(tester, 'first').style?.backgroundColor, _textColor);
    expect(
      spanWithText(tester, 'second').style?.backgroundColor,
      isNot(_textColor),
    );
  });

  testWidgets('tapping a link opens it', (tester) async {
    final opened = await pumpMarkdown(
      tester,
      'read https://example.com/docs now',
    );

    await tester.tapOnText(find.textRange.ofSubstring('example.com/docs'));
    await tester.pump();

    expect(opened, [Uri.parse('https://example.com/docs')]);
  });

  testWidgets('links inside hidden spoilers do not open', (tester) async {
    final opened = await pumpMarkdown(tester, '||https://example.com||');

    await tester.tapOnText(find.textRange.ofSubstring('example.com'));
    await tester.pump();
    expect(opened, isEmpty);

    await tester.tapOnText(find.textRange.ofSubstring('example.com'));
    await tester.pump();
    expect(opened, [Uri.parse('https://example.com')]);
  });

  testWidgets('mentions keep their highlight inside bold', (tester) async {
    const body = '**hi @alice**';
    await pumpMarkdown(
      tester,
      body,
      mentions: const [
        MessageMention(
          userId: 'alice-id',
          displayName: 'Alice',
          start: 5,
          end: 11,
        ),
      ],
    );

    final context = tester.element(find.byType(MessageMarkdownText));
    final mention = effectiveStyle(tester, '@alice');
    expect(mention.color, Theme.of(context).colorScheme.primary);
    expect(mention.fontWeight, FontWeight.w700);
    expect(effectiveStyle(tester, 'hi ').fontWeight, FontWeight.w700);
  });

  testWidgets('code blocks and quotes render as blocks', (tester) async {
    await pumpMarkdown(tester, '> quoted **text**\n```\nlet x = *y*;\n```');

    expect(find.byKey(const ValueKey('markdown-quote')), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown-code-block')), findsOneWidget);
    expect(find.text('let x = *y*;'), findsOneWidget);
  });
}
