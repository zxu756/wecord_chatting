import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/browser/in_app_browser_screen.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

typedef LinkLauncher = Future<void> Function(BuildContext context, Uri uri);

/// Opens links tapped in messages: web pages in the in-app browser where
/// there is one, everything else with the system; tests override it.
final linkLauncherProvider = Provider<LinkLauncher>((ref) {
  return (context, uri) async {
    if (inAppBrowserSupported && isWebPageUri(uri)) {
      await openInAppBrowser(context, uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  };
});

const _monospaceFamily = 'monospace';
const _monospaceFallback = ['Menlo', 'Consolas', 'Courier New'];

/// Renders a message body's markdown, keeping @mention highlighting.
/// Custom emoji show as images to members of their circle, `:name:` to
/// everyone else.
class MessageMarkdownText extends ConsumerStatefulWidget {
  const MessageMarkdownText({
    required this.body,
    required this.color,
    this.mentions = const <MessageMention>[],
    this.enlargeEmojiOnly = false,
    super.key,
  });

  final String body;
  final List<MessageMention> mentions;
  final Color color;

  /// Shows a message of nothing but emoji (at most [maxJumboEmoji]) large.
  final bool enlargeEmojiOnly;

  @override
  ConsumerState<MessageMarkdownText> createState() =>
      _MessageMarkdownTextState();
}

class _MessageMarkdownTextState extends ConsumerState<MessageMarkdownText> {
  late List<MarkdownBlock> _blocks;
  final _revealedSpoilers = <int>{};
  final _recognizers = <GestureRecognizer>[];
  var _spoilerIndex = 0;
  var _jumbo = false;
  var _usableEmojis = const <String, CircleEmoji>{};

  @override
  void initState() {
    super.initState();
    _blocks = _parse();
  }

  @override
  void didUpdateWidget(covariant MessageMarkdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body ||
        !_sameMentions(oldWidget.mentions, widget.mentions)) {
      _blocks = _parse();
      _revealedSpoilers.clear();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  List<MarkdownBlock> _parse() {
    return parseMessageMarkdown(widget.body, mentions: widget.mentions);
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    _spoilerIndex = 0;
    _usableEmojis = ref.watch(usableEmojisByIdProvider);
    _jumbo = widget.enlargeEmojiOnly && isEmojiOnlyMarkdown(_blocks);
    final baseStyle = TextStyle(
      color: widget.color,
      fontSize: _jumbo ? _jumboFontSize : null,
    );
    if (_blocks.isEmpty) {
      return Text(widget.body, style: baseStyle);
    }
    final children = <Widget>[];
    for (final block in _blocks) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 4));
      }
      children.add(_buildBlock(context, block, baseStyle));
    }
    if (children.length == 1) {
      return children.single;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildBlock(
    BuildContext context,
    MarkdownBlock block,
    TextStyle baseStyle,
  ) {
    switch (block) {
      case MarkdownParagraph(:final children):
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: _spans(context, children, const _SpanState()),
          ),
        );
      case MarkdownQuote(:final children):
        return Container(
          key: const ValueKey('markdown-quote'),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: widget.color.withValues(alpha: 0.5),
                width: 3,
              ),
            ),
          ),
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: _spans(context, children, const _SpanState()),
            ),
          ),
        );
      case MarkdownCodeBlock(:final code):
        return Container(
          key: const ValueKey('markdown-code-block'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            code,
            style: baseStyle.copyWith(
              fontFamily: _monospaceFamily,
              fontFamilyFallback: _monospaceFallback,
            ),
          ),
        );
    }
  }

  List<InlineSpan> _spans(
    BuildContext context,
    List<MarkdownInline> nodes,
    _SpanState state,
  ) {
    return [for (final node in nodes) _span(context, node, state)];
  }

  InlineSpan _span(
    BuildContext context,
    MarkdownInline node,
    _SpanState state,
  ) {
    final palette = context.tokens.colors;
    // On an outgoing (ink) bubble links keep the bubble's text color.
    final onInk = widget.color == palette.onInk;
    switch (node) {
      case MarkdownText(:final text):
        return TextSpan(text: text);
      case MarkdownCustomEmoji(:final name, :final id):
        final emoji = _usableEmojis[id];
        if (emoji == null) {
          return TextSpan(text: ':$name:');
        }
        final size = _jumbo ? customEmojiJumboSize : customEmojiInlineSize;
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          // No tooltip: long presses open the message's actions.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: CustomEmojiImage(
              key: ValueKey('custom-emoji-$id'),
              storagePath: emoji.storagePath,
              size: size,
              semanticLabel: ':${emoji.name}:',
              fallback: Text(':$name:'),
            ),
          ),
        );
      case MarkdownMention(:final text, :final mention):
        // Role mentions take the role's colour; @here and roles get a
        // tinted background since they reach many people.
        final roleColor = mention.color;
        final color = mention.isRole && roleColor != null
            ? Color(0xFF000000 | roleColor)
            : palette.accentText;
        return TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            backgroundColor: mention.isRole
                ? color.withValues(alpha: 0.14)
                : palette.accentSoft,
          ),
        );
      case MarkdownInlineCode(:final code):
        return TextSpan(
          text: code,
          style: TextStyle(
            fontFamily: _monospaceFamily,
            fontFamilyFallback: _monospaceFallback,
            backgroundColor: widget.color.withValues(alpha: 0.12),
          ),
        );
      case MarkdownLink(:final url):
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(url);
        _recognizers.add(recognizer);
        return TextSpan(
          text: url,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          style: TextStyle(
            color: onInk ? widget.color : palette.accentText,
            decoration: state.decorationWith(TextDecoration.underline),
            decorationColor: onInk
                ? widget.color.withValues(alpha: 0.6)
                : palette.accentText.withValues(alpha: 0.5),
          ),
        );
      case MarkdownStyled(style: MarkdownStyle.spoiler, :final children):
        final index = _spoilerIndex++;
        if (_revealedSpoilers.contains(index)) {
          return TextSpan(
            style: TextStyle(
              backgroundColor: widget.color.withValues(alpha: 0.12),
            ),
            children: _spans(context, children, state),
          );
        }
        // Hidden spoilers are one flat span so every character takes the tap.
        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            setState(() {
              _revealedSpoilers.add(index);
            });
          };
        _recognizers.add(recognizer);
        return TextSpan(
          text: plainTextOfInlines(children),
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          style: TextStyle(
            color: widget.color,
            backgroundColor: widget.color,
            decoration: TextDecoration.none,
          ),
        );
      case MarkdownStyled(:final style, :final children):
        final next = state.withStyle(style);
        return TextSpan(
          style: TextStyle(
            fontWeight: next.bold ? FontWeight.w700 : null,
            fontStyle: next.italic ? FontStyle.italic : null,
            decoration: next.decoration,
          ),
          children: _spans(context, children, next),
        );
    }
  }

  void _openLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    ref.read(linkLauncherProvider)(context, uri).catchError((Object _) {});
  }
}

/// A message of nothing but emoji shows them this large, up to this many.
const maxJumboEmoji = 27;
const _jumboFontSize = 40.0;

// Emoji, flag letters and the keycap mark. The analyzer does not know
// Extended_Pictographic, which the Dart and JavaScript engines support.
final _emojiGlyph = RegExp(
  // ignore: valid_regexps
  r'[\p{Extended_Pictographic}\u{1F1E6}-\u{1F1FF}\u{20E3}]',
  unicode: true,
);
final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether [blocks] are one paragraph of only custom and unicode emoji (and
/// spaces), 1 to [maxJumboEmoji] of them.
bool isEmojiOnlyMarkdown(List<MarkdownBlock> blocks) {
  if (blocks.length != 1) {
    return false;
  }
  final block = blocks.single;
  if (block is! MarkdownParagraph) {
    return false;
  }
  var count = 0;
  for (final node in block.children) {
    switch (node) {
      case MarkdownCustomEmoji():
        count++;
      case MarkdownText(:final text):
        for (final glyph in text.characters) {
          if (glyph.trim().isEmpty) {
            continue;
          }
          // Keycaps (1️⃣) are digits with U+20E3.
          final isEmoji =
              _emojiGlyph.hasMatch(glyph) &&
              (!_letterOrDigit.hasMatch(glyph) || glyph.contains('\u20E3'));
          if (!isEmoji) {
            return false;
          }
          count++;
        }
      default:
        return false;
    }
    if (count > maxJumboEmoji) {
      return false;
    }
  }
  return count > 0;
}

bool _sameMentions(List<MessageMention> left, List<MessageMention> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index].start != right[index].start ||
        left[index].end != right[index].end) {
      return false;
    }
  }
  return true;
}

/// Inherited emphasis, so nested decorations combine instead of replacing
/// each other.
class _SpanState {
  const _SpanState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;

  _SpanState withStyle(MarkdownStyle style) {
    return _SpanState(
      bold: bold || style == MarkdownStyle.bold,
      italic: italic || style == MarkdownStyle.italic,
      underline: underline || style == MarkdownStyle.underline,
      strikethrough: strikethrough || style == MarkdownStyle.strikethrough,
    );
  }

  TextDecoration? get decoration {
    final decorations = [
      if (underline) TextDecoration.underline,
      if (strikethrough) TextDecoration.lineThrough,
    ];
    return decorations.isEmpty ? null : TextDecoration.combine(decorations);
  }

  TextDecoration decorationWith(TextDecoration extra) {
    return TextDecoration.combine([?decoration, extra]);
  }
}
