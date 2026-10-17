import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_text_controller.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/shared/api/signed_url_refresh.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A temporary URL for a picture of a note.
final noteImageUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) {
  return ref.watch(notesRepositoryProvider).imageUrl(path);
});

/// The text style of a block of [kind].
TextStyle noteTextStyle(BuildContext context, NoteBlock block) {
  final c = context.tokens.colors;
  return switch (block.kind) {
    NoteBlockKind.heading1 => TextStyle(
      fontSize: 28,
      height: 1.25,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      color: c.ink,
    ),
    NoteBlockKind.heading2 => TextStyle(
      fontSize: 22,
      height: 1.3,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
      color: c.ink,
    ),
    NoteBlockKind.heading3 => TextStyle(
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: c.ink,
    ),
    NoteBlockKind.quote => TextStyle(
      fontSize: 16,
      height: 1.55,
      fontStyle: FontStyle.italic,
      color: c.muted,
    ),
    NoteBlockKind.code => TextStyle(
      fontFamily: 'JetBrains Mono',
      fontSize: 13.5,
      height: 1.6,
      color: c.ink,
    ),
    NoteBlockKind.todo when block.checked => TextStyle(
      fontSize: 16,
      height: 1.55,
      color: c.muted,
      decoration: TextDecoration.lineThrough,
      decorationColor: c.muted,
    ),
    _ => TextStyle(fontSize: 16, height: 1.55, color: c.ink),
  };
}

String _hintFor(NoteBlock block) {
  return switch (block.kind) {
    NoteBlockKind.heading1 => tr('Heading 1'),
    NoteBlockKind.heading2 => tr('Heading 2'),
    NoteBlockKind.heading3 => tr('Heading 3'),
    NoteBlockKind.quote => tr('Quote'),
    NoteBlockKind.code => tr('Code'),
    NoteBlockKind.bullet || NoteBlockKind.numbered => tr('List item'),
    NoteBlockKind.todo => tr('To-do'),
    _ => tr("Write something, or type '/' for blocks"),
  };
}

/// One block of a note, drawn for its kind: the gutter (bullet, number,
/// check box, quote bar), the text field, the carets of the other people
/// in it, and for pictures and dividers their own looks.
class NoteBlockRow extends ConsumerWidget {
  const NoteBlockRow({
    required this.block,
    required this.rowKey,
    required this.text,
    required this.focusNode,
    required this.readOnly,
    required this.peers,
    required this.onKeyEvent,
    required this.onOpenLink,
    this.number,
    this.onToggleChecked,
    this.onMenu,
    this.onTapBlock,
    this.onLastBlockTap,
    super.key,
  });

  final NoteBlock block;
  final GlobalKey rowKey;
  final NoteTextController text;
  final FocusNode focusNode;
  final int? number;
  final bool readOnly;
  final List<NotePeer> peers;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback? onToggleChecked;
  final void Function(Rect anchor)? onMenu;
  final void Function(String url) onOpenLink;
  final VoidCallback? onTapBlock;

  /// Set on the last block: tapping the space under it.
  final VoidCallback? onLastBlockTap;

  Color _peerColor(NotePeer peer) => WeCordAvatarColors.forSeed(peer.userId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final style = noteTextStyle(context, block);
    final touch = usesTouchInput(context);
    final topGap = switch (block.kind) {
      NoteBlockKind.heading1 => 14.0,
      NoteBlockKind.heading2 => 10.0,
      NoteBlockKind.heading3 => 6.0,
      _ => 2.0,
    };

    Widget body;
    switch (block.kind) {
      case NoteBlockKind.divider:
        body = _NonTextBlock(
          focusNode: focusNode,
          onKeyEvent: onKeyEvent,
          onTap: onTapBlock,
          semanticLabel: tr('Divider'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: c.line),
          ),
        );
      case NoteBlockKind.image:
        body = _NonTextBlock(
          focusNode: focusNode,
          onKeyEvent: onKeyEvent,
          onTap: onTapBlock,
          semanticLabel: '${block.props['name'] ?? tr('Picture')}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: NoteImageView(
              path: block.props['path'] as String?,
              name: block.props['name'] as String? ?? '',
            ),
          ),
        );
      default:
        body = _TextBlock(
          block: block,
          style: style,
          text: text,
          focusNode: focusNode,
          readOnly: readOnly,
          number: number,
          peers: peers,
          peerColor: _peerColor,
          onKeyEvent: onKeyEvent,
          onToggleChecked: onToggleChecked,
          onOpenLink: onOpenLink,
        );
    }

    final focused = peers.isNotEmpty;
    final handle = (!touch && onMenu != null)
        ? _RowHandle(
            onMenu: () {
              final box = rowKey.currentContext?.findRenderObject();
              if (box is RenderBox && box.hasSize) {
                final origin = box.localToGlobal(Offset.zero);
                onMenu!(origin & box.size);
              }
            },
          )
        : const SizedBox(width: 0);

    return Column(
      children: [
        Padding(
          key: rowKey,
          padding: EdgeInsets.only(top: topGap, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!touch) handle,
              Expanded(child: body),
              if (focused) const SizedBox(width: 4),
            ],
          ),
        ),
        if (onLastBlockTap != null)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onTap: onLastBlockTap,
            child: const SizedBox(height: 120, width: double.infinity),
          ),
      ],
    );
  }
}

/// The ⋮⋮ handle in the margin on desktop: opens the block menu.
class _RowHandle extends StatelessWidget {
  const _RowHandle({required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SizedBox(
      width: 28,
      child: WeCordPressable(
        onPressed: onMenu,
        tooltip: tr('Block options'),
        semanticLabel: tr('Block options'),
        shape: const CircleBorder(),
        pressedScale: 1,
        minTapSize: Size.zero,
        builder: (context, states) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            Icons.drag_indicator_rounded,
            size: 18,
            color: states.contains(WidgetState.hovered) ? c.ink : c.faint,
          ),
        ),
      ),
    );
  }
}

class _NonTextBlock extends StatelessWidget {
  const _NonTextBlock({
    required this.focusNode,
    required this.onKeyEvent,
    required this.child,
    required this.semanticLabel,
    this.onTap,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final Widget child;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(event),
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) => Semantics(
          label: semanticLabel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(WeCordRadii.sm),
                border: Border.all(
                  color: focusNode.hasFocus ? c.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.block,
    required this.style,
    required this.text,
    required this.focusNode,
    required this.readOnly,
    required this.peers,
    required this.peerColor,
    required this.onKeyEvent,
    required this.onOpenLink,
    this.number,
    this.onToggleChecked,
  });

  final NoteBlock block;
  final TextStyle style;
  final NoteTextController text;
  final FocusNode focusNode;
  final bool readOnly;
  final int? number;
  final List<NotePeer> peers;
  final Color Function(NotePeer) peerColor;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback? onToggleChecked;
  final void Function(String url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final isCode = block.kind == NoteBlockKind.code;

    Widget field = ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final field = TextField(
          controller: text,
          focusNode: focusNode,
          readOnly: readOnly,
          maxLines: null,
          minLines: 1,
          style: style,
          cursorColor: c.accent,
          cursorWidth: 2,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: isCode
              ? TextCapitalization.none
              : TextCapitalization.sentences,
          smartDashesType: isCode ? SmartDashesType.disabled : null,
          smartQuotesType: isCode ? SmartQuotesType.disabled : null,
          autocorrect: !isCode,
          enableSuggestions: !isCode,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          // A line of text is a touch target: at least 48 (44 on iOS) tall,
          // the text centred in it.
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            constraints: BoxConstraints(minHeight: context.touchTargetSize),
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: focusNode.hasFocus && !readOnly ? _hintFor(block) : null,
            hintStyle: style.copyWith(
              color: c.subtle,
              decoration: TextDecoration.none,
              fontStyle: FontStyle.normal,
            ),
          ),
          onTap: () => _tapped(),
        );
        return field;
      },
    );

    field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => onKeyEvent(event),
      child: field,
    );

    // Other people's carets over the text.
    if (peers.isNotEmpty) {
      final textField = field;
      field = LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            textField,
            for (final peer in peers)
              _PeerMarker(
                peer: peer,
                color: peerColor(peer),
                text: text.text,
                style: style,
                width: constraints.maxWidth,
              ),
          ],
        ),
      );
    }

    final gutter = _gutter(context);
    final content = isCode
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: field,
          )
        : block.kind == NoteBlockKind.quote
        ? Container(
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: c.accent, width: 3)),
            ),
            child: field,
          )
        : field;

    if (gutter == null) {
      return content;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        gutter,
        Expanded(child: content),
      ],
    );
  }

  void _tapped() {
    final selection = text.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return;
    }
    final link = text.linkAtSelection;
    if (link == null) {
      return;
    }
    final modifier =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (readOnly || modifier) {
      onOpenLink(link.linkUrl);
    }
  }

  Widget? _gutter(BuildContext context) {
    final c = context.tokens.colors;
    final lineHeight = math.max(16 * 1.55, context.touchTargetSize);
    switch (block.kind) {
      case NoteBlockKind.bullet:
        return SizedBox(
          width: 24,
          height: lineHeight,
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            ),
          ),
        );
      case NoteBlockKind.numbered:
        return SizedBox(
          width: 28,
          height: lineHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${number ?? 1}.',
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
        );
      case NoteBlockKind.todo:
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: NoteCheckBox(
            checked: block.checked,
            onChanged: onToggleChecked,
            label: block.text.isEmpty ? tr('To-do') : block.text,
          ),
        );
      default:
        return null;
    }
  }
}

/// The round check box of a to-do block (and of tasks): 22 wide, with a
/// 44 tap area.
class NoteCheckBox extends StatelessWidget {
  const NoteCheckBox({
    required this.checked,
    required this.onChanged,
    required this.label,
    this.size = 22,
    super.key,
  });

  final bool checked;
  final VoidCallback? onChanged;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      onPressed: onChanged,
      toggled: checked,
      semanticLabel: label,
      shape: const CircleBorder(),
      mergeSemantics: false,
      builder: (context, states) => AnimatedContainer(
        duration: WeCordMotion.quick,
        curve: WeCordMotion.standard,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? c.success : Colors.transparent,
          border: Border.all(
            color: checked
                ? c.success
                : states.contains(WidgetState.hovered)
                ? c.accent
                : c.faint,
            width: 2,
          ),
        ),
        child: checked
            ? Icon(Icons.check_rounded, size: size - 6, color: Colors.white)
            : null,
      ),
    );
  }
}

/// Another person's caret in a text: a bar in their color with their name
/// on a flag above it.
class _PeerMarker extends StatelessWidget {
  const _PeerMarker({
    required this.peer,
    required this.color,
    required this.text,
    required this.style,
    required this.width,
  });

  final NotePeer peer;
  final Color color;
  final String text;
  final TextStyle style;
  final double width;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: math.max(width, 1));
    final offset = (peer.offset ?? 0).clamp(0, text.length);
    final position = painter.getOffsetForCaret(
      TextPosition(offset: offset),
      Rect.zero,
    );
    final height = painter.preferredLineHeight;
    painter.dispose();
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        child: Semantics(
          label: tr('{name} is here', {'name': peer.name}),
          child: SizedBox(
            width: 2,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: ColoredBox(color: color)),
                Positioned(
                  left: 0,
                  bottom: height,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    child: Text(
                      peer.name,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A picture of a note, loaded with a temporary URL; tap to see it large.
class NoteImageView extends ConsumerWidget {
  const NoteImageView({required this.path, required this.name, super.key});

  final String? path;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final path = this.path;
    Widget placeholder(IconData icon) => Container(
      height: 140,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Icon(icon, color: c.faint, size: 28),
    );
    if (path == null) {
      return placeholder(Icons.broken_image_outlined);
    }
    final url = ref.watch(noteImageUrlProvider(path));
    return url.when(
      loading: () => placeholder(Icons.image_outlined),
      error: (_, _) => placeholder(Icons.broken_image_outlined),
      data: (url) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: Semantics(
                        label: name,
                        image: true,
                        child: Image.network(url, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  right: 8,
                  child: WeCordIconButton(
                    icon: Icons.close_rounded,
                    tooltip: tr('Close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(WeCordRadii.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Semantics(
              label: name.isEmpty ? tr('Picture') : name,
              image: true,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorBuilder: (context, error, stackTrace) {
                  refreshSignedUrlSoon(
                    'note-image-$path',
                    () => ref.invalidate(noteImageUrlProvider(path)),
                  );
                  return placeholder(Icons.broken_image_outlined);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The formatting bar under the note: text styles, lists, pictures,
/// mentions and the block menu. On phones it floats as glass above the
/// keyboard; on desktop it is a flat bar with a hairline.
class NoteFormatBar extends StatelessWidget {
  const NoteFormatBar({
    required this.kind,
    required this.isActive,
    required this.onToggleMark,
    required this.onLink,
    required this.onKind,
    required this.onImage,
    required this.onMention,
    required this.onMore,
    super.key,
  });

  final NoteBlockKind? kind;
  final bool Function(String type) isActive;
  final void Function(String type) onToggleMark;
  final VoidCallback onLink;
  final void Function(NoteBlockKind kind) onKind;
  final VoidCallback onImage;
  final VoidCallback onMention;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final touch = usesTouchInput(context);
    final shortcut = defaultTargetPlatformIsApple(context) ? '⌘' : 'Ctrl+';

    Widget mark(String type, IconData icon, String tooltip, [String? keys]) {
      return WeCordIconButton(
        icon: icon,
        tooltip: keys == null ? tooltip : '$tooltip ($shortcut$keys)',
        size: 36,
        iconSize: 19,
        variant: WeCordButtonVariant.ghost,
        selected: isActive(type),
        onPressed: () => onToggleMark(type),
      );
    }

    Widget block(NoteBlockKind target, IconData icon, String tooltip) {
      return WeCordIconButton(
        icon: icon,
        tooltip: tooltip,
        size: 36,
        iconSize: 19,
        variant: WeCordButtonVariant.ghost,
        selected: kind == target,
        onPressed: () => onKind(target),
      );
    }

    final divider = Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: c.line,
    );

    final buttons = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          mark(NoteMark.bold, Icons.format_bold_rounded, tr('Bold'), 'B'),
          mark(NoteMark.italic, Icons.format_italic_rounded, tr('Italic'), 'I'),
          mark(
            NoteMark.strike,
            Icons.format_strikethrough_rounded,
            tr('Strikethrough'),
          ),
          mark(NoteMark.code, Icons.code_rounded, tr('Inline code'), 'E'),
          WeCordIconButton(
            icon: Icons.link_rounded,
            tooltip: '${tr('Link')} (${shortcut}K)',
            size: 36,
            iconSize: 19,
            variant: WeCordButtonVariant.ghost,
            onPressed: onLink,
          ),
          divider,
          block(NoteBlockKind.heading1, Icons.title_rounded, tr('Heading')),
          block(
            NoteBlockKind.bullet,
            Icons.format_list_bulleted_rounded,
            tr('Bulleted list'),
          ),
          block(
            NoteBlockKind.numbered,
            Icons.format_list_numbered_rounded,
            tr('Numbered list'),
          ),
          block(NoteBlockKind.todo, Icons.check_box_outlined, tr('To-do list')),
          block(NoteBlockKind.quote, Icons.format_quote_rounded, tr('Quote')),
          block(
            NoteBlockKind.code,
            Icons.data_object_rounded,
            tr('Code block'),
          ),
          divider,
          WeCordIconButton(
            icon: Icons.image_outlined,
            tooltip: tr('Add picture'),
            size: 36,
            iconSize: 19,
            variant: WeCordButtonVariant.ghost,
            onPressed: onImage,
          ),
          WeCordIconButton(
            icon: Icons.alternate_email_rounded,
            tooltip: tr('Mention someone'),
            size: 36,
            iconSize: 19,
            variant: WeCordButtonVariant.ghost,
            onPressed: onMention,
          ),
          WeCordIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: tr('Block options'),
            size: 36,
            iconSize: 19,
            variant: WeCordButtonVariant.ghost,
            onPressed: onMore,
          ),
        ],
      ),
    );

    if (touch) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          10,
          0,
          10,
          MediaQuery.viewInsetsOf(context).bottom > 0
              ? 6
              : math.max(MediaQuery.paddingOf(context).bottom, 10),
        ),
        child: WeCordGlass(
          key: const ValueKey('note-format-bar'),
          borderRadius: BorderRadius.circular(WeCordRadii.pill),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(height: 48, child: buttons),
        ),
      );
    }
    return Container(
      key: const ValueKey('note-format-bar'),
      height: 48,
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      alignment: Alignment.centerLeft,
      child: buttons,
    );
  }
}

/// ⌘ on Apple platforms, Ctrl elsewhere.
bool defaultTargetPlatformIsApple(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
}

/// The people matching an @ being typed, as a floating list.
class NoteMentionTray extends StatelessWidget {
  const NoteMentionTray({
    required this.candidates,
    required this.onPick,
    super.key,
  });

  final List<({String userId, String label})> candidates;
  final void Function(({String userId, String label}) candidate) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordGlass(
      key: const ValueKey('note-mention-tray'),
      elevation: GlassElevation.menu,
      borderRadius: BorderRadius.circular(WeCordRadii.lg),
      padding: const EdgeInsets.all(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Semantics(
          label: tr('People to mention'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final candidate in candidates)
                WeCordPressable(
                  key: ValueKey('note-mention-${candidate.userId}'),
                  onPressed: () => onPick(candidate),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.sm),
                  ),
                  pressedScale: 0.99,
                  builder: (context, states) => Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: states.contains(WidgetState.hovered)
                          ? c.raised
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(WeCordRadii.sm),
                    ),
                    child: Row(
                      children: [
                        PersonAvatar(
                          name: candidate.label.substring(1),
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            candidate.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a link's address; returns it (empty to remove the link) or
/// null when cancelled.
Future<String?> showNoteLinkDialog(
  BuildContext context, {
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Link')),
      content: SizedBox(
        width: 420,
        child: WeCordTextField(
          controller: controller,
          label: tr('Address'),
          hint: 'https://',
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) =>
              Navigator.of(context).pop(_normalizedUrl(value)),
        ),
      ),
      actions: [
        if (initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(tr('Remove link')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_normalizedUrl(controller.text)),
          child: Text(tr('Save')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

String _normalizedUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)
      ? trimmed
      : 'https://$trimmed';
}

/// Exposed for tests: the URL a link dialog answer is turned into.
String normalizedLinkUrl(String value) => _normalizedUrl(value);
