import 'dart:async';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/accessibility/image_alt_sheet.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_providers.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';
import 'package:wecord/features/group_space/space_pickers.dart';
import 'package:wecord/features/group_space/space_upload.dart';
import 'package:wecord/features/group_space/space_widgets.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart' show maxImageAltLength;
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How many pictures can be picked from the device at once.
const spaceUploadBatch = 20;

enum _ItemAction { open, cover, describe, remove }

enum _AddAction { upload, fromChat }

enum _AlbumAction { rename, delete }

/// One album of the group space: its pictures and videos in a grid, newest
/// first. The album of an event (the pictures people added from the event) is
/// shown the same way, read-only apart from taking a picture away.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({
    required this.conversationId,
    this.albumId,
    this.eventId,
    this.title,
    super.key,
  }) : assert(
         (albumId == null) != (eventId == null),
         'An album screen shows an album or an event, not both',
       );

  /// `/chats/:conversationId/space/albums/:albumId`.
  static String pathFor(String conversationId, String albumId) =>
      '/chats/$conversationId/space/albums/$albumId';

  /// `/chats/:conversationId/space/events/:eventId`.
  static String eventPathFor(String conversationId, String eventId) =>
      '/chats/$conversationId/space/events/$eventId';

  final String conversationId;
  final String? albumId;
  final String? eventId;

  /// The name, known when opened from the list.
  final String? title;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  ({int done, int total})? _uploading;

  bool get _isEvent => widget.eventId != null;

  AsyncValue<List<SpaceMedia>> _items() => _isEvent
      ? ref.watch(
          eventAlbumProvider((
            conversationId: widget.conversationId,
            eventId: widget.eventId!,
          )),
        )
      : ref.watch(albumItemsProvider(widget.albumId!));

  void _refresh() {
    ref.invalidate(groupAlbumsProvider(widget.conversationId));
    if (_isEvent) {
      ref.invalidate(
        eventAlbumProvider((
          conversationId: widget.conversationId,
          eventId: widget.eventId!,
        )),
      );
    } else {
      ref.invalidate(albumItemsProvider(widget.albumId!));
    }
  }

  SpaceAlbum? _album(List<SpaceAlbum>? albums) {
    final id = widget.albumId ?? widget.eventId;
    for (final album in albums ?? const <SpaceAlbum>[]) {
      if (album.id == id) {
        return album;
      }
    }
    return null;
  }

  Future<void> _add(GroupSpaceInfo info) async {
    final action = await showCircleActionMenu<_AddAction>(
      context,
      items: [
        CircleMenuItem(
          value: _AddAction.upload,
          icon: Icons.upload_outlined,
          label: tr('Upload photos and videos'),
        ),
        CircleMenuItem(
          value: _AddAction.fromChat,
          icon: Icons.chat_bubble_outline_rounded,
          label: tr('Choose from this chat'),
        ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _AddAction.upload:
        await _upload();
      case _AddAction.fromChat:
        await _fromChat();
    }
  }

  Future<void> _fromChat() async {
    final ids = await pickChatMedia(
      context,
      conversationId: widget.conversationId,
      files: false,
    );
    if (ids == null || ids.isEmpty || !mounted) {
      return;
    }
    AddResult result = const AddResult();
    final ok = await runSpaceAction(context, () async {
      result = await ref
          .read(groupSpaceRepositoryProvider)
          .addMessagesToAlbum(widget.albumId!, ids);
    });
    _refresh();
    if (ok && mounted) {
      showSpaceMessage(context, addResultText(result, toAlbum: true));
    }
  }

  Future<void> _upload() async {
    final List<XFile> files;
    try {
      files = await ref
          .read(chatMediaPickerProvider)
          .pickPhotosAndVideos(limit: spaceUploadBatch);
    } on Object catch (error) {
      if (mounted) {
        showSpaceMessage(context, errorText(error));
      }
      return;
    }
    if (files.isEmpty || !mounted) {
      return;
    }
    final repository = ref.read(groupSpaceRepositoryProvider);
    var done = 0;
    var failed = 0;
    Object? lastError;
    setState(() => _uploading = (done: 0, total: files.length));
    for (final file in files) {
      try {
        final upload = await prepareSpaceUpload(file, mediaOnly: true);
        await repository.uploadToAlbum(
          widget.conversationId,
          widget.albumId!,
          upload,
        );
        done += 1;
      } on Object catch (error) {
        failed += 1;
        lastError = error;
        if (error is NotAlbumMediaException) {
          lastError = StateError(
            tr('"{name}" is not a picture or a video.', {'name': error.name}),
          );
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _uploading = (done: done + failed, total: files.length));
    }
    if (!mounted) {
      return;
    }
    setState(() => _uploading = null);
    _refresh();
    if (failed == 0) {
      showSpaceMessage(
        context,
        tr('{count} added to the album.', {'count': done}),
      );
    } else {
      final why = lastError == null ? '' : ' ${errorText(lastError)}';
      showSpaceMessage(
        context,
        '${tr('{done} added, {failed} could not be added.', {'done': done, 'failed': failed})}$why',
      );
    }
  }

  Future<void> _rename(SpaceAlbum album) async {
    final name = await askSpaceName(
      context,
      title: tr('Rename album'),
      label: tr('Album name'),
      confirmLabel: tr('Save'),
      initial: album.name,
    );
    if (name == null || name == album.name || !mounted) {
      return;
    }
    await runSpaceAction(
      context,
      () => ref.read(groupSpaceRepositoryProvider).renameAlbum(album.id, name),
    );
    _refresh();
  }

  Future<void> _delete(SpaceAlbum album) async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete the album "{name}"?', {'name': album.name}),
      message: tr(
        'The pictures in it that were sent in the chat stay in the chat. Files uploaded to the album are deleted.',
      ),
      confirmLabel: tr('Delete album'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    final ok = await runSpaceAction(
      context,
      () => ref.read(groupSpaceRepositoryProvider).deleteAlbum(album.id),
    );
    ref.invalidate(groupAlbumsProvider(widget.conversationId));
    if (ok && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _albumMenu(SpaceAlbum album) async {
    final action = await showCircleActionMenu<_AlbumAction>(
      context,
      items: [
        CircleMenuItem(
          value: _AlbumAction.rename,
          icon: Icons.edit_outlined,
          label: tr('Rename album'),
        ),
        CircleMenuItem(
          value: _AlbumAction.delete,
          icon: Icons.delete_outline_rounded,
          label: tr('Delete album'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _AlbumAction.rename:
        await _rename(album);
      case _AlbumAction.delete:
        await _delete(album);
    }
  }

  void _open(SpaceMedia item, List<SpaceMedia> all) {
    final gallery = [for (final media in all) media.toPreviewFile()];
    unawaited(
      openFilePreview(context, file: item.toPreviewFile(), gallery: gallery),
    );
  }

  Future<void> _itemMenu(
    SpaceMedia item,
    List<SpaceMedia> all,
    SpaceAlbum? album,
  ) async {
    final canCover = !_isEvent && !item.isVideo && (album?.canManage ?? false);
    final canDescribe = !_isEvent && !item.isVideo && item.canDelete;
    final action = await showCircleActionMenu<_ItemAction>(
      context,
      items: [
        CircleMenuItem(
          value: _ItemAction.open,
          icon: Icons.open_in_full_rounded,
          label: tr('Open'),
        ),
        if (canCover)
          CircleMenuItem(
            value: _ItemAction.cover,
            icon: Icons.photo_size_select_actual_outlined,
            label: tr('Make album cover'),
          ),
        if (canDescribe)
          CircleMenuItem(
            value: _ItemAction.describe,
            icon: Icons.short_text_rounded,
            label: item.alt == null
                ? tr('Describe this picture')
                : tr('Edit description'),
          ),
        if (item.canDelete)
          CircleMenuItem(
            value: _ItemAction.remove,
            icon: Icons.delete_outline_rounded,
            label: _isEvent ? tr('Delete picture') : tr('Remove from album'),
            destructive: true,
          ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _ItemAction.open:
        _open(item, all);
      case _ItemAction.cover:
        await runSpaceAction(
          context,
          () => ref
              .read(groupSpaceRepositoryProvider)
              .setAlbumCover(widget.albumId!, item.id),
        );
        _refresh();
      case _ItemAction.describe:
        final described = await showImageAltSheet(
          context,
          pictures: [AltPicture(id: item.id, current: item.alt)],
        );
        if (described == null || !mounted) {
          return;
        }
        final text = (described[item.id] ?? '').trim();
        await runSpaceAction(
          context,
          () => ref
              .read(groupSpaceRepositoryProvider)
              .setItemAlt(
                item.id,
                text.isEmpty
                    ? null
                    : text.substring(
                        0,
                        text.length > maxImageAltLength
                            ? maxImageAltLength
                            : text.length,
                      ),
              ),
        );
        _refresh();
      case _ItemAction.remove:
        final confirmed = await confirmCircleAction(
          context,
          title: _isEvent
              ? tr('Delete this picture?')
              : tr('Remove from the album?'),
          message: _isEvent
              ? tr('It is taken off the event too.')
              : item.fromChat
              ? tr('The picture stays in the chat.')
              : tr('The file is deleted.'),
          confirmLabel: _isEvent ? tr('Delete') : tr('Remove'),
        );
        if (!confirmed || !mounted) {
          return;
        }
        await runSpaceAction(context, () {
          final repository = ref.read(groupSpaceRepositoryProvider);
          return _isEvent
              ? repository.deleteEventPhoto(item)
              : repository.removeAlbumItem(item.id);
        });
        _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final info =
        ref.watch(groupSpaceInfoProvider(widget.conversationId)).value ??
        const GroupSpaceInfo();
    final albums = ref.watch(groupAlbumsProvider(widget.conversationId));
    final album = _album(albums.value);
    final items = _items();
    final title = album?.name ?? widget.title ?? tr('Album');
    final add = !_isEvent && info.canAdd && _uploading == null;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: title,
                  actions: [
                    if (add)
                      WeCordIconButton(
                        key: const ValueKey('album-add'),
                        icon: Icons.add_photo_alternate_outlined,
                        tooltip: tr('Add pictures and videos'),
                        variant: WeCordButtonVariant.onPaper,
                        onPressed: () => unawaited(_add(info)),
                      ),
                    if (!_isEvent && album != null && album.canManage)
                      WeCordIconButton(
                        key: const ValueKey('album-menu'),
                        icon: Icons.more_horiz_rounded,
                        tooltip: tr('Album options'),
                        variant: WeCordButtonVariant.onPaper,
                        onPressed: () => unawaited(_albumMenu(album)),
                      ),
                  ],
                ),
                if (_isEvent)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SpaceNotice(
                      text: tr(
                        'These are the pictures people added from the event. Add yours from the event.',
                      ),
                      icon: Icons.event_outlined,
                    ),
                  )
                else if (!info.enabled)
                  const SpaceOffNotice(),
                if (!_isEvent &&
                    context.touchTargetSize > 0 &&
                    (items.value?.any((item) => item.canDelete) ?? false))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Text(
                      tr('Touch and hold a picture for more.'),
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ),
                if (_uploading case final progress?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          key: const ValueKey('album-upload-progress'),
                          value: progress.total == 0
                              ? null
                              : progress.done / progress.total,
                          color: c.accent,
                          backgroundColor: c.track,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr('Uploading {done} of {total}', {
                            'done': progress.done,
                            'total': progress.total,
                          }),
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: items.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) =>
                        SpaceLoadError(error: error, onRetry: _refresh),
                    data: (list) => list.isEmpty
                        ? SpaceEmpty(
                            icon: Icons.photo_outlined,
                            title: tr('Nothing in this album yet'),
                            message: _isEvent
                                ? null
                                : tr(
                                    'Upload pictures, or long-press a picture in the chat and choose Add to album.',
                                  ),
                            actionLabel: add ? tr('Add pictures') : null,
                            onAction: () => unawaited(_add(info)),
                          )
                        : _ItemGrid(
                            items: list,
                            onOpen: (item) => _open(item, list),
                            onMore: (item) =>
                                unawaited(_itemMenu(item, list, album)),
                            canMore: (item) =>
                                item.canDelete ||
                                (album?.canManage ?? false) && !item.isVideo,
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

class _ItemGrid extends StatelessWidget {
  const _ItemGrid({
    required this.items,
    required this.onOpen,
    required this.onMore,
    required this.canMore,
  });

  final List<SpaceMedia> items;
  final ValueChanged<SpaceMedia> onOpen;
  final ValueChanged<SpaceMedia> onMore;
  final bool Function(SpaceMedia item) canMore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 120).floor().clamp(3, 6);
        return GridView.builder(
          key: const ValueKey('album-grid'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _ItemTile(
              item: item,
              onOpen: () => onOpen(item),
              onMore: canMore(item) ? () => onMore(item) : null,
            );
          },
        );
      },
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onOpen, this.onMore});

  final SpaceMedia item;
  final VoidCallback onOpen;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final radius = BorderRadius.circular(WeCordRadii.sm);
    final file = item.toPreviewFile();
    final alt = item.alt;
    return Stack(
      fit: StackFit.expand,
      children: [
        WeCordPressable(
          key: ValueKey('album-item-${item.id}'),
          onPressed: onOpen,
          onLongPress: onMore,
          pressedScale: 0.96,
          semanticLabel:
              alt ??
              (item.isVideo ? '${item.name}, ${tr('video')}' : item.name),
          excludeSemantics: true,
          shape: RoundedRectangleBorder(borderRadius: radius),
          builder: (context, states) => ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SpacePicture(file: file),
                if (states.contains(WidgetState.hovered))
                  ColoredBox(color: c.ink.withValues(alpha: 0.08)),
                if (alt != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: ImageAltBadge(
                      key: ValueKey('album-alt-${item.id}'),
                      compact: true,
                      onPressed: () =>
                          unawaited(showImageAltReader(context, alt)),
                      semanticLabel: tr('Picture description'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // A mouse gets a button; a finger touches and holds (a button this
        // small would be too small to hit).
        if (onMore != null && context.touchTargetSize == 0)
          Positioned(
            top: 2,
            right: 2,
            child: Semantics(
              button: true,
              label: tr('More'),
              child: GestureDetector(
                key: ValueKey('album-item-more-${item.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: onMore,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: WeCordPalette.dark.paper.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 16,
                      color: WeCordPalette.dark.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
