import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/group_space/album_screen.dart';
import 'package:wecord/features/group_space/folder_screen.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_providers.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';
import 'package:wecord/features/group_space/space_widgets.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

enum SpaceTab { albums, files }

/// The group space of a group chat (roadmap B6): albums for pictures and
/// videos, and folders for files, kept apart from the scroll of the chat.
/// The same two lists are the "Albums" and "Folders" tabs of the chat's media
/// page; this page is for opening the space on its own (from a link or a tab
/// of the group).
class GroupSpaceScreen extends ConsumerStatefulWidget {
  const GroupSpaceScreen({
    required this.conversationId,
    this.initialTab = SpaceTab.albums,
    super.key,
  });

  /// `/chats/:conversationId/space?tab=albums|files`.
  static String pathFor(String conversationId, {SpaceTab? tab}) {
    final base = '/chats/$conversationId/space';
    return tab == null ? base : '$base?tab=${tab.name}';
  }

  static SpaceTab tabFrom(Map<String, String> query) =>
      query['tab'] == 'files' ? SpaceTab.files : SpaceTab.albums;

  final String conversationId;
  final SpaceTab initialTab;

  @override
  ConsumerState<GroupSpaceScreen> createState() => _GroupSpaceScreenState();
}

class _GroupSpaceScreenState extends ConsumerState<GroupSpaceScreen> {
  late var _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final info = ref.watch(groupSpaceInfoProvider(widget.conversationId));
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
                PaperPageHeader(title: tr('Group space')),
                Expanded(
                  child: info.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(color: c.muted),
                    ),
                    error: (error, stack) => SpaceLoadError(
                      error: error,
                      onRetry: () => ref.invalidate(
                        groupSpaceInfoProvider(widget.conversationId),
                      ),
                    ),
                    data: (value) => value.supported
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  12,
                                ),
                                child: WeCordSegmented<SpaceTab>(
                                  expand: true,
                                  selected: _tab,
                                  onChanged: (tab) =>
                                      setState(() => _tab = tab),
                                  segments: [
                                    WeCordSegment(
                                      key: const ValueKey('space-tab-albums'),
                                      value: SpaceTab.albums,
                                      label: tr('Albums'),
                                    ),
                                    WeCordSegment(
                                      key: const ValueKey('space-tab-folders'),
                                      value: SpaceTab.files,
                                      label: tr('Folders'),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _tab == SpaceTab.albums
                                    ? GroupAlbumsTab(
                                        conversationId: widget.conversationId,
                                        info: value,
                                      )
                                    : GroupFoldersTab(
                                        conversationId: widget.conversationId,
                                        info: value,
                                      ),
                              ),
                            ],
                          )
                        : SpaceEmpty(
                            icon: Icons.folder_off_outlined,
                            title: tr('Only group chats have a group space.'),
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

/// The group's albums as a grid (the "Albums" tab).
class GroupAlbumsTab extends ConsumerWidget {
  const GroupAlbumsTab({
    required this.conversationId,
    required this.info,
    super.key,
  });

  final String conversationId;
  final GroupSpaceInfo info;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await askSpaceName(
      context,
      title: tr('New album'),
      label: tr('Album name'),
      confirmLabel: tr('Create'),
      hint: tr('Trip, birthday, notes...'),
    );
    if (name == null || !context.mounted) {
      return;
    }
    SpaceAlbum? created;
    final ok = await runSpaceAction(context, () async {
      created = await ref
          .read(groupSpaceRepositoryProvider)
          .createAlbum(conversationId, name);
    });
    ref.invalidate(groupAlbumsProvider(conversationId));
    if (ok && created != null && context.mounted) {
      unawaited(
        context.push(
          AlbumScreen.pathFor(conversationId, created!.id),
          extra: created!.name,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(groupAlbumsProvider(conversationId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!info.enabled) const SpaceOffNotice(),
        if (info.canAdd)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: WeCordButton(
                key: const ValueKey('space-new-album'),
                label: tr('New album'),
                icon: Icons.add_photo_alternate_outlined,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(_create(context, ref)),
              ),
            ),
          ),
        Expanded(
          child: albums.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => SpaceLoadError(
              error: error,
              onRetry: () =>
                  ref.invalidate(groupAlbumsProvider(conversationId)),
            ),
            data: (list) => list.isEmpty
                ? SpaceEmpty(
                    icon: Icons.photo_album_outlined,
                    title: tr('No albums yet'),
                    message: tr(
                      'Keep the photos and videos worth keeping where the chat cannot bury them.',
                    ),
                    actionLabel: info.canAdd ? tr('New album') : null,
                    onAction: () => unawaited(_create(context, ref)),
                  )
                : _AlbumGrid(conversationId: conversationId, albums: list),
          ),
        ),
      ],
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.conversationId, required this.albums});

  final String conversationId;
  final List<SpaceAlbum> albums;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        const side = 16.0;
        final columns = ((constraints.maxWidth - side * 2) / 170).floor().clamp(
          2,
          5,
        );
        final width =
            (constraints.maxWidth - side * 2 - gap * (columns - 1)) / columns;
        return GridView.builder(
          key: const ValueKey('space-album-grid'),
          padding: const EdgeInsets.fromLTRB(side, 0, side, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: width + 10 + 50 * scale.clamp(1, 2.2),
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) =>
              AlbumTile(conversationId: conversationId, album: albums[index]),
        );
      },
    );
  }
}

/// One album in the grid: its cover, name and how many it holds.
class AlbumTile extends StatelessWidget {
  const AlbumTile({
    required this.conversationId,
    required this.album,
    super.key,
  });

  final String conversationId;
  final SpaceAlbum album;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final cover = album.cover;
    final radius = BorderRadius.circular(WeCordRadii.lg);
    final count = tr('{count} items', {'count': album.itemCount});
    return WeCordPressable(
      key: ValueKey('space-album-${album.id}'),
      onPressed: () => unawaited(
        context.push(
          album.isEvent
              ? AlbumScreen.eventPathFor(conversationId, album.id)
              : AlbumScreen.pathFor(conversationId, album.id),
          extra: album.name,
        ),
      ),
      semanticLabel: album.isEvent
          ? tr('{name}, event pictures, {count}', {
              'name': album.name,
              'count': count,
            })
          : '${album.name}, $count',
      excludeSemantics: true,
      shape: RoundedRectangleBorder(borderRadius: radius),
      pressedScale: 0.97,
      builder: (context, states) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    SpacePicture(
                      file: PreviewFile(
                        bucket: cover.bucket,
                        path: cover.path,
                        name: cover.path.split('/').last,
                        mimeType: 'image/jpeg',
                        size: 0,
                      ),
                    )
                  else
                    ColoredBox(
                      color: c.raised,
                      child: Icon(
                        Icons.photo_album_outlined,
                        size: 36,
                        color: c.faint,
                      ),
                    ),
                  if (states.contains(WidgetState.hovered))
                    ColoredBox(color: c.ink.withValues(alpha: 0.08)),
                  if (album.isEvent)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.panel.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(WeCordRadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_outlined, size: 13, color: c.ink),
                            const SizedBox(width: 3),
                            Text(
                              tr('Event'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
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
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          Text(
            count,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// The group's folders as a list (the "Folders" tab).
class GroupFoldersTab extends ConsumerWidget {
  const GroupFoldersTab({
    required this.conversationId,
    required this.info,
    super.key,
  });

  final String conversationId;
  final GroupSpaceInfo info;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await askSpaceName(
      context,
      title: trIn('group files', 'New folder'),
      label: tr('Folder name'),
      confirmLabel: tr('Create'),
      hint: tr('Handouts, receipts, minutes...'),
    );
    if (name == null || !context.mounted) {
      return;
    }
    SpaceFolder? created;
    final ok = await runSpaceAction(context, () async {
      created = await ref
          .read(groupSpaceRepositoryProvider)
          .createFolder(conversationId, name);
    });
    ref.invalidate(groupFoldersProvider(conversationId));
    if (ok && created != null && context.mounted) {
      unawaited(
        context.push(
          FolderScreen.pathFor(conversationId, created!.id),
          extra: created!.name,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final folders = ref.watch(groupFoldersProvider(conversationId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!info.enabled) const SpaceOffNotice(),
        if (info.canAdd)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: WeCordButton(
                key: const ValueKey('space-new-folder'),
                label: trIn('group files', 'New folder'),
                icon: Icons.create_new_folder_outlined,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () => unawaited(_create(context, ref)),
              ),
            ),
          ),
        Expanded(
          child: folders.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => SpaceLoadError(
              error: error,
              onRetry: () =>
                  ref.invalidate(groupFoldersProvider(conversationId)),
            ),
            data: (value) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [
                SettingsGroup(
                  color: c.panel,
                  children: [
                    SettingsRow(
                      key: const ValueKey('space-top-files'),
                      icon: Icons.folder_open_outlined,
                      title: tr('Group files'),
                      subtitle: tr('Not in a folder'),
                      value: '${value.rootCount}',
                      onTap: () => unawaited(
                        context.push(FolderScreen.topPathFor(conversationId)),
                      ),
                    ),
                    for (final folder in value.folders)
                      SettingsRow(
                        key: ValueKey('space-folder-${folder.id}'),
                        icon: Icons.folder_outlined,
                        title: folder.name,
                        subtitle: folder.creatorName,
                        value: '${folder.fileCount}',
                        onTap: () => unawaited(
                          context.push(
                            FolderScreen.pathFor(conversationId, folder.id),
                            extra: folder.name,
                          ),
                        ),
                      ),
                  ],
                ),
                if (value.folders.isEmpty && value.rootCount == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: SpaceEmpty(
                      inline: true,
                      icon: Icons.folder_copy_outlined,
                      title: tr('No files yet'),
                      message: tr(
                        'Keep handouts and documents here, where new members can find them.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
