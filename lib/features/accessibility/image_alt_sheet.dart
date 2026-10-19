import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart' show maxImageAltLength;
import 'package:wecord/shared/ui/ui.dart';

/// The small "ALT" mark on a picture that has a description. In a message it
/// is a button that shows what the sender wrote; in the tray (without
/// [onPressed]) it only shows whether a description was written, and the
/// picture itself is the button.
class ImageAltBadge extends StatelessWidget {
  const ImageAltBadge({
    this.onPressed,
    this.semanticLabel,
    this.described = true,
    this.compact = false,
    super.key,
  });

  /// Whether the picture has a description (the mark is filled) or not (it
  /// invites writing one).
  final bool described;
  final bool compact;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final dark = WeCordPalette.dark;
    Widget mark(Set<WidgetState> states) => Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: described ? c.accent : dark.paper.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!described)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                Icons.add_rounded,
                size: compact ? 10 : 12,
                color: dark.ink,
              ),
            ),
          Text(
            tr('ALT'),
            style: TextStyle(
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: described ? c.onAccent : dark.ink,
            ),
          ),
        ],
      ),
    );
    // A small mark on a picture: it keeps its size when the text grows.
    Widget fixed(Set<WidgetState> states) =>
        MediaQuery.withNoTextScaling(child: mark(states));
    if (onPressed == null) {
      return ExcludeSemantics(child: fixed(const {}));
    }
    return WeCordPressable(
      onPressed: onPressed,
      tooltip: semanticLabel,
      semanticLabel: semanticLabel,
      shape: const StadiumBorder(),
      pressedScale: 0.94,
      builder: (context, states) => fixed(states),
    );
  }
}

/// A picture waiting to be described: [id] tells it apart, [picture] is a
/// small image of it and [current] what was already written.
class AltPicture {
  const AltPicture({required this.id, this.picture, this.current});

  final String id;
  final Uint8List? picture;
  final String? current;
}

/// Asks the sender to describe [pictures]. Resolves to the description of
/// each by id (empty to take one away), or null when they backed out.
Future<Map<String, String>?> showImageAltSheet(
  BuildContext context, {
  required List<AltPicture> pictures,
}) {
  return showWeCordSheet<Map<String, String>>(
    context,
    title: pictures.length == 1
        ? tr('Describe this picture')
        : tr('Describe these pictures'),
    detents: pictures.length > 1 ? const [0.6, 0.92] : null,
    builder: (context, scrollController) =>
        ImageAltSheet(pictures: pictures, scrollController: scrollController),
  );
}

class ImageAltSheet extends StatefulWidget {
  const ImageAltSheet({
    required this.pictures,
    this.scrollController,
    super.key,
  });

  final List<AltPicture> pictures;
  final ScrollController? scrollController;

  static const saveKey = ValueKey('image-alt-save');

  /// The field of the picture [id].
  static ValueKey<String> fieldKey(String id) => ValueKey('image-alt-$id');

  @override
  State<ImageAltSheet> createState() => _ImageAltSheetState();
}

class _ImageAltSheetState extends State<ImageAltSheet> {
  late final _texts = {
    for (final picture in widget.pictures)
      picture.id: TextEditingController(text: picture.current),
  };

  @override
  void dispose() {
    for (final controller in _texts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(
                        'Say what is in the picture for people who cannot see it, such as someone using a screen reader. Mention who or what it shows and any text in it.',
                      ),
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final (index, picture) in widget.pictures.indexed) ...[
                      if (index > 0) const SizedBox(height: 14),
                      _PictureField(
                        picture: picture,
                        controller: _texts[picture.id]!,
                        autofocus: index == 0,
                        number: widget.pictures.length > 1 ? index + 1 : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Stays in reach however many pictures there are.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: WeCordButton(
                key: ImageAltSheet.saveKey,
                label: tr('Save'),
                expand: true,
                onPressed: () => Navigator.of(context).pop({
                  for (final MapEntry(:key, :value) in _texts.entries)
                    key: value.text.trim(),
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One picture with its field.
class _PictureField extends StatelessWidget {
  const _PictureField({
    required this.picture,
    required this.controller,
    required this.autofocus,
    this.number,
  });

  final AltPicture picture;
  final TextEditingController controller;
  final bool autofocus;

  /// Which picture this is, when there are several.
  final int? number;

  @override
  Widget build(BuildContext context) {
    final bytes = picture.picture;
    final label = number == null
        ? trIn('picture-description', 'Description')
        : tr('Description of picture {number}', {'number': number});
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bytes != null) ...[
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
              child: Image.memory(
                bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const SizedBox(width: 72, height: 72),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: WeCordTextField(
            fieldKey: ImageAltSheet.fieldKey(picture.id),
            controller: controller,
            label: label,
            hint: tr('A dog asleep on a red sofa'),
            autofocus: autofocus,
            minLines: 2,
            maxLines: 6,
            maxLength: maxImageAltLength,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),
        ),
      ],
    );
  }
}

/// Shows what the sender wrote about a picture.
Future<void> showImageAltReader(BuildContext context, String description) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Picture description')),
      content: SingleChildScrollView(child: SelectableText(description)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Close')),
        ),
      ],
    ),
  );
}
