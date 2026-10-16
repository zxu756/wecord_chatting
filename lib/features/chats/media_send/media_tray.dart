import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The tray above the composer that holds the photos, videos and files
/// chosen for the next message: thumbnails with remove buttons, an
/// optional caption, the "Original quality" switch for photos, and the
/// send button. Nothing is shown while it is empty.
class MediaTray extends ConsumerStatefulWidget {
  const MediaTray({
    required this.conversationId,
    required this.onSend,
    required this.onAddMore,
    this.desktop = false,
    this.sendEnabled = true,
    this.allowViewOnce = false,
    super.key,
  });

  final String conversationId;

  /// Prepares and queues what is in the tray.
  final Future<void> Function() onSend;

  /// Opens the chooser for more files, anchored to the widget of [context].
  final void Function(BuildContext context) onAddMore;
  final bool desktop;

  /// False while something else keeps the reader from sending (slowmode).
  final bool sendEnabled;

  /// Offers "View once" for photos and videos (direct chats and groups).
  final bool allowViewOnce;

  @override
  ConsumerState<MediaTray> createState() => _MediaTrayState();
}

class _MediaTrayState extends ConsumerState<MediaTray> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  MediaTrayController get _controller =>
      ref.read(mediaTrayProvider(widget.conversationId).notifier);

  /// "3 photos", "1 video", "2 files", "4 items".
  static String titleFor(List<DraftAttachment> items, int loading) {
    final count = items.length + loading;
    final kinds = {for (final item in items) item.kind};
    if (loading == 0 && kinds.length == 1) {
      switch (kinds.single) {
        case DraftKind.image:
          return count == 1
              ? tr('1 photo')
              : tr('{count} photos', {'count': count});
        case DraftKind.video:
          return count == 1
              ? tr('1 video')
              : tr('{count} videos', {'count': count});
        case DraftKind.file:
          return count == 1
              ? tr('1 file')
              : tr('{count} files', {'count': count});
      }
    }
    return count == 1 ? tr('1 item') : tr('{count} items', {'count': count});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mediaTrayProvider(widget.conversationId));
    ref.listen(mediaTrayProvider(widget.conversationId), (previous, next) {
      if (next.isEmpty && _caption.text.isNotEmpty) {
        _caption.clear();
      } else if (next.caption != _caption.text && _caption.text.isEmpty) {
        // A caption put back by "Edit and resend".
        _caption.text = next.caption;
      }
    });
    if (state.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final desktop = widget.desktop;
    final thumb = desktop ? 84.0 : 72.0;

    final subtitle = state.isPreparing
        ? tr('Preparing {done} of {total}…', {
            'done': state.preparing!.$1,
            'total': state.preparing!.$2,
          })
        : state.hasImages
        ? (state.original
              ? tr('Full size · location removed')
              : tr('Resized to {size} px · location removed', {
                  'size': maxPhotoEdge,
                }))
        : null;

    return WeCordGlass(
      key: const ValueKey('media-tray'),
      borderRadius: BorderRadius.circular(WeCordRadii.xl),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleFor(state.items, state.loading),
                      key: const ValueKey('media-tray-title'),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        key: const ValueKey('media-tray-subtitle'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: c.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (state.hasImages) ...[
                Text(
                  tr('Original quality'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
                const SizedBox(width: 8),
                WeCordSwitch(
                  key: const ValueKey('media-tray-original'),
                  compact: true,
                  semanticLabel: tr('Original quality'),
                  value: state.original,
                  onChanged: state.isPreparing ? null : _controller.setOriginal,
                ),
              ],
              const SizedBox(width: 4),
              WeCordIconButton(
                key: const ValueKey('media-tray-close'),
                tooltip: tr('Remove all'),
                icon: Icons.close_rounded,
                size: 32,
                iconSize: 18,
                variant: WeCordButtonVariant.ghost,
                onPressed: state.isPreparing ? null : _controller.clear,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: thumb + 6,
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(top: 6),
              children: [
                for (final item in state.items)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _TrayThumb(
                      item: item,
                      size: thumb,
                      onRemove: state.isPreparing
                          ? null
                          : () => _controller.remove(item.id),
                    ),
                  ),
                for (var i = 0; i < state.loading; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: thumb,
                      height: thumb,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.raised,
                        borderRadius: BorderRadius.circular(WeCordRadii.sm),
                      ),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.faint,
                        ),
                      ),
                    ),
                  ),
                if (state.room > 0 && !state.isPreparing)
                  Builder(
                    builder: (tileContext) => _AddTile(
                      size: thumb,
                      onPressed: () => widget.onAddMore(tileContext),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.allowViewOnce && state.canViewOnce) ...[
            const SizedBox(height: 8),
            _ViewOnceRow(
              value: state.viewOnce,
              onChanged: state.isPreparing ? null : _controller.setViewOnce,
            ),
          ],
          if (state.tooBig.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Notice(
              key: const ValueKey('media-tray-too-big'),
              text: tr(
                'Files can be up to 50 MB. Remove the ones marked to send.',
              ),
              danger: true,
            ),
          ],
          if (state.leftOut > 0) ...[
            const SizedBox(height: 8),
            _Notice(
              key: const ValueKey('media-tray-left-out'),
              text: tr(
                'You can send up to {max} at a time. {count} left out.',
                {'max': maxTrayItems, 'count': state.leftOut},
              ),
              onDismiss: _controller.dismissNotice,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(WeCordRadii.lg),
                    border: Border.all(color: c.lineSoft),
                  ),
                  child: TextField(
                    key: const ValueKey('media-tray-caption'),
                    controller: _caption,
                    enabled: !state.isPreparing && !state.sendsViewOnce,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onChanged: _controller.setCaption,
                    onSubmitted: (_) {
                      if (state.canSend && widget.sendEnabled) {
                        widget.onSend();
                      }
                    },
                    style: TextStyle(
                      fontSize: desktop ? 14.5 : 15.5,
                      color: c.ink,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintText: state.sendsViewOnce
                          ? tr('No caption on view-once media')
                          : tr('Add a caption…'),
                      hintStyle: TextStyle(color: c.subtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              WeCordButton(
                key: const ValueKey('media-tray-send'),
                label: state.items.length > 1
                    ? tr('Send {count}', {'count': state.items.length})
                    : tr('Send'),
                icon: Icons.arrow_upward_rounded,
                variant: WeCordButtonVariant.accent,
                loading: state.isPreparing,
                onPressed: state.canSend && widget.sendEnabled
                    ? widget.onSend
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One file in the tray: its picture (or a tile for files), a remove
/// button in the corner and a mark when it is too big.
class _TrayThumb extends StatelessWidget {
  const _TrayThumb({
    required this.item,
    required this.size,
    required this.onRemove,
  });

  final DraftAttachment item;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final dark = WeCordPalette.dark;
    final radius = BorderRadius.circular(WeCordRadii.sm);
    final thumbnail = item.thumbnail;

    Widget face;
    if (item.kind == DraftKind.file || thumbnail == null) {
      final file = PreviewFile(
        bucket: '',
        path: item.name,
        name: item.name,
        mimeType: item.mimeType,
        size: item.size,
      );
      face = Container(
        color: c.raised,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FileTypeTile(file: file, size: size >= 80 ? 38 : 34),
            const SizedBox(height: 4),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ],
        ),
      );
    } else {
      face = Image.memory(
        thumbnail,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ColoredBox(color: c.raised),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  face,
                  if (item.kind == DraftKind.video)
                    Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: dark.paper.withValues(alpha: 0.62),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: dark.ink,
                        ),
                      ),
                    ),
                  if (item.kind == DraftKind.video || item.overLimit)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.overLimit
                              ? c.danger
                              : dark.paper.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(WeCordRadii.pill),
                        ),
                        child: Text(
                          item.overLimit
                              ? tr('Too big')
                              : formatFileSize(item.size),
                          key: ValueKey('media-tray-badge-${item.id}'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                            color: item.overLimit ? c.onDanger : dark.ink,
                          ),
                        ),
                      ),
                    ),
                  if (item.overLimit)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(color: c.danger, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: WeCordPressable(
              key: ValueKey('media-tray-remove-${item.id}'),
              onPressed: onRemove,
              tooltip: tr('Remove'),
              semanticLabel: tr('Remove {name}', {'name': item.name}),
              shape: const CircleBorder(),
              pressedScale: 0.9,
              builder: (context, states) => SizedBox.square(
                dimension: 30,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c.ink,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.panel, width: 1.5),
                    ),
                    child: Icon(Icons.close_rounded, size: 13, color: c.onInk),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onPressed});

  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      key: const ValueKey('media-tray-add'),
      onPressed: onPressed,
      tooltip: tr('Add more'),
      semanticLabel: tr('Add more'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.sm),
      ),
      builder: (context, states) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered)
              ? c.raisedStrong
              : c.raised,
          borderRadius: BorderRadius.circular(WeCordRadii.sm),
        ),
        child: Icon(Icons.add_rounded, size: 26, color: c.muted),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    this.danger = false,
    this.onDismiss,
    super.key,
  });

  final String text;
  final bool danger;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: danger ? c.dangerSoft : c.accentSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: danger ? c.dangerText : c.accentText,
              ),
            ),
          ),
          if (onDismiss != null)
            WeCordPressable(
              onPressed: onDismiss,
              tooltip: tr('Dismiss'),
              semanticLabel: tr('Dismiss'),
              shape: const CircleBorder(),
              builder: (context, states) => SizedBox.square(
                dimension: 28,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: danger ? c.dangerText : c.accentText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "View once" switch under the tray's thumbnails, with what it means
/// (and does not) while it is on.
class _ViewOnceRow extends StatelessWidget {
  const _ViewOnceRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.timelapse_rounded,
            size: 18,
            color: value ? c.accentText : c.muted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('View once'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              Text(
                value
                    ? tr(
                        'Each person can open it one time. Screenshots and screen recordings can\'t be blocked.',
                      )
                    : tr('Let people open each photo or video one time.'),
                key: const ValueKey('media-tray-view-once-note'),
                style: TextStyle(fontSize: 11.5, height: 1.3, color: c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        WeCordSwitch(
          key: const ValueKey('media-tray-view-once'),
          compact: true,
          semanticLabel: tr('View once'),
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
