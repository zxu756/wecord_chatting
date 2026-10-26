import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:wecord/features/hashtags/hashtag_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A text whose topics (#话题) are links. [onTag] gets the clean tag, without
/// the hash. With no [onTag] the text is plain.
class HashtagText extends StatefulWidget {
  const HashtagText(
    this.text, {
    required this.style,
    this.onTag,
    this.maxLines,
    this.overflow,
    this.selectable = false,
    this.textKey,
    super.key,
  });

  final String text;
  final TextStyle style;
  final ValueChanged<String>? onTag;
  final int? maxLines;
  final TextOverflow? overflow;

  /// The text can be selected and copied (a Moment's text).
  final bool selectable;

  /// Key of the [Text] or [SelectableText] inside, for tests.
  final Key? textKey;

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
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
    final ValueChanged<String>? onTag = widget.onTag;
    final spans = onTag == null
        ? const <HashtagSpan>[]
        : hashtagSpans(widget.text);
    if (spans.isEmpty) {
      return widget.selectable
          ? SelectableText(
              widget.text,
              key: widget.textKey,
              style: widget.style,
              maxLines: widget.maxLines,
            )
          : Text(
              widget.text,
              key: widget.textKey,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            );
    }
    final c = context.tokens.colors;
    final children = <InlineSpan>[];
    var position = 0;
    for (final span in spans) {
      if (span.start > position) {
        children.add(
          TextSpan(text: widget.text.substring(position, span.start)),
        );
      }
      final recognizer = TapGestureRecognizer()..onTap = () => onTag!(span.tag);
      _recognizers.add(recognizer);
      children.add(
        TextSpan(
          text: widget.text.substring(span.start, span.end),
          recognizer: recognizer,
          semanticsLabel: tr('Topic {tag}', {'tag': span.tag}),
          style: TextStyle(color: c.accentText, fontWeight: FontWeight.w700),
        ),
      );
      position = span.end;
    }
    if (position < widget.text.length) {
      children.add(TextSpan(text: widget.text.substring(position)));
    }
    if (widget.selectable) {
      // The selectable text is a text-field node with a node per piece; a
      // screen reader gets the whole text as one label and each topic as an
      // action instead.
      return Semantics(
        label: widget.text,
        customSemanticsActions: {
          for (final span in spans)
            CustomSemanticsAction(
              label: tr('Topic {tag}', {'tag': span.tag}),
            ): () =>
                onTag!(span.tag),
        },
        child: ExcludeSemantics(
          child: SelectableText.rich(
            TextSpan(children: children),
            key: widget.textKey,
            style: widget.style,
            maxLines: widget.maxLines,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: children),
      key: widget.textKey,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

/// The topics of a post as a row of pills; a tap on one gets its tag.
class HashtagPills extends StatelessWidget {
  const HashtagPills({
    required this.tags,
    this.onTag,
    this.onPaper = false,
    this.selected,
    super.key,
  });

  final List<String> tags;
  final ValueChanged<String>? onTag;
  final bool onPaper;

  /// The tag shown as chosen, when the pills are a filter.
  final String? selected;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          WeCordChip(
            label: '#$tag',
            height: 28,
            onPaper: onPaper,
            selected: tag == selected,
            semanticLabel: tr('Topic {tag}', {'tag': tag}),
            onPressed: onTag == null ? null : () => onTag!(tag),
          ),
      ],
    );
  }
}

/// Picks the topics of a post: the chosen ones as pills that go away when
/// pressed, and a field to add another (a hash in front is fine).
class HashtagEditor extends StatefulWidget {
  const HashtagEditor({
    required this.tags,
    required this.onChanged,
    this.enabled = true,
    this.onPaper = true,
    this.suggestions = const [],
    super.key,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final bool onPaper;

  /// Topics offered under the field (the ones already used nearby).
  final List<String> suggestions;

  @override
  State<HashtagEditor> createState() => _HashtagEditorState();
}

class _HashtagEditorState extends State<HashtagEditor> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _errorText = null);
      return;
    }
    final tag = cleanHashtag(text);
    if (tag == null) {
      setState(
        () => _errorText = tr(
          'A topic is 1 to 30 letters, digits or characters, without spaces.',
        ),
      );
      return;
    }
    if (widget.tags.contains(tag)) {
      _controller.clear();
      setState(() => _errorText = null);
      return;
    }
    if (widget.tags.length >= maxHashtags) {
      setState(
        () => _errorText = tr('A post can have {count} topics at most.', {
          'count': maxHashtags,
        }),
      );
      return;
    }
    _controller.clear();
    setState(() => _errorText = null);
    widget.onChanged([...widget.tags, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final offered = [
      for (final tag in widget.suggestions)
        if (!widget.tags.contains(tag)) tag,
    ].take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WeCordTextField(
          controller: _controller,
          enabled: widget.enabled,
          onPaper: widget.onPaper,
          label: tr('Topics'),
          hint: tr('Add a topic'),
          prefixIcon: Icons.tag_rounded,
          errorText: _errorText,
          textInputAction: TextInputAction.done,
          onSubmitted: _add,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: WeCordIconButton(
              tooltip: tr('Add topic'),
              icon: Icons.add_rounded,
              variant: WeCordButtonVariant.ghost,
              size: 36,
              onPressed: widget.enabled ? () => _add(_controller.text) : null,
            ),
          ),
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                WeCordChip(
                  label: '#$tag',
                  height: 30,
                  selected: true,
                  semanticLabel: tr('Remove topic {tag}', {'tag': tag}),
                  trailing: Icon(Icons.close_rounded, size: 14, color: c.onInk),
                  onPressed: widget.enabled
                      ? () => widget.onChanged([
                          for (final other in widget.tags)
                            if (other != tag) other,
                        ])
                      : null,
                ),
            ],
          ),
        ],
        if (offered.isNotEmpty && widget.enabled) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in offered)
                WeCordChip(
                  label: '#$tag',
                  height: 28,
                  onPaper: widget.onPaper,
                  semanticLabel: tr('Add topic {tag}', {'tag': tag}),
                  onPressed: () => _add(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
