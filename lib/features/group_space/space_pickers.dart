import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_providers.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';
import 'package:wecord/features/group_space/space_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The sentence for what [result] says happened when messages were added.
String addResultText(AddResult result, {required bool toAlbum}) {
  if (result.added == 0) {
    return toAlbum
        ? tr(
            'Nothing was added. View-once, deleted, expiring and forwarded pictures cannot go in an album.',
          )
        : tr(
            'Nothing was added. View-once, deleted, expiring and forwarded files cannot be kept.',
          );
  }
  final base = toAlbum
      ? tr('{count} added to the album.', {'count': result.added})
      : tr('{count} saved to the group files.', {'count': result.added});
  if (result.skipped == 0) {
    return base;
  }
  return '$base ${tr('{count} could not be added.', {'count': result.skipped})}';
}

class _NewChoice {
  const _NewChoice();
}

/// Lets the person choose one of the group's albums for [messageIds] (or make
/// a new one) and adds them. Returns whether anything was added.
Future<bool> addMessagesToAlbumFlow(
  BuildContext context, {
  required String conversationId,
  required List<String> messageIds,
}) async {
  final choice = await showWeCordSheet<Object>(
    context,
    title: tr('Add to album'),
    detents: const [0.55, 0.92],
    builder: (sheetContext, controller) => _AlbumChoiceList(
      conversationId: conversationId,
      controller: controller,
    ),
  );
  if (choice == null || !context.mounted) {
    return false;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final repository = container.read(groupSpaceRepositoryProvider);
  var result = const AddResult();
  final ok = await runSpaceAction(context, () async {
    final String albumId;
    if (choice is SpaceAlbum) {
      albumId = choice.id;
    } else {
      final name = await askSpaceName(
        context,
        title: tr('New album'),
        label: tr('Album name'),
        confirmLabel: tr('Create'),
      );
      if (name == null) {
        throw const SpaceCancelled();
      }
      albumId = (await repository.createAlbum(conversationId, name)).id;
    }
    result = await repository.addMessagesToAlbum(albumId, messageIds);
  });
  if (!context.mounted) {
    return false;
  }
  container.invalidate(groupAlbumsProvider(conversationId));
  if (ok) {
    showSpaceMessage(context, addResultText(result, toAlbum: true));
  }
  return ok && result.added > 0;
}

class _AlbumChoiceList extends ConsumerWidget {
  const _AlbumChoiceList({
    required this.conversationId,
    required this.controller,
  });

  final String conversationId;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final info = ref.watch(groupSpaceInfoProvider(conversationId)).value;
    final albums = ref.watch(groupAlbumsProvider(conversationId));
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      children: [
        SettingsGroup(
          color: c.well,
          children: [
            if (info?.canAdd ?? true)
              SettingsRow(
                key: const ValueKey('space-pick-new-album'),
                icon: Icons.add_photo_alternate_outlined,
                title: tr('New album'),
                showChevron: false,
                onTap: () => Navigator.of(context).pop(const _NewChoice()),
              ),
            ...albums.maybeWhen(
              data: (list) => [
                for (final album in list)
                  if (!album.isEvent)
                    SettingsRow(
                      key: ValueKey('space-pick-album-${album.id}'),
                      icon: Icons.photo_album_outlined,
                      title: album.name,
                      value: tr('{count} items', {'count': album.itemCount}),
                      showChevron: false,
                      onTap: () => Navigator.of(context).pop(album),
                    ),
              ],
              orElse: () => const <Widget>[],
            ),
          ],
        ),
        if (albums.isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (albums.hasError)
          SpaceLoadError(
            error: albums.error!,
            onRetry: () => ref.invalidate(groupAlbumsProvider(conversationId)),
          ),
      ],
    );
  }
}

/// A folder choice: a folder, or the top level (null).
class FolderChoice {
  const FolderChoice(this.folder, {this.isNew = false});

  /// The chosen folder; null for the top level (or for a new folder).
  final SpaceFolder? folder;

  /// The person asked for a new folder.
  final bool isNew;
}

/// Lets the person choose a folder for [messageIds] (the top level, a folder
/// or a new one) and saves them. Returns whether anything was saved.
Future<bool> saveMessagesToFilesFlow(
  BuildContext context, {
  required String conversationId,
  required List<String> messageIds,
}) async {
  final choice = await pickFolder(
    context,
    conversationId: conversationId,
    title: tr('Save to group files'),
  );
  if (choice == null || !context.mounted) {
    return false;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  final repository = container.read(groupSpaceRepositoryProvider);
  var result = const AddResult();
  final ok = await runSpaceAction(context, () async {
    var folderId = choice.folder?.id;
    if (choice.isNew) {
      final name = await askSpaceName(
        context,
        title: trIn('group files', 'New folder'),
        label: tr('Folder name'),
        confirmLabel: tr('Create'),
      );
      if (name == null) {
        throw const SpaceCancelled();
      }
      folderId = (await repository.createFolder(conversationId, name)).id;
    }
    result = await repository.addMessagesToFolder(
      conversationId,
      folderId,
      messageIds,
    );
  });
  if (!context.mounted) {
    return false;
  }
  container.invalidate(groupFoldersProvider(conversationId));
  if (ok) {
    showSpaceMessage(context, addResultText(result, toAlbum: false));
  }
  return ok && result.added > 0;
}

/// Asks which folder: the top level, one of the folders, or (with [allowNew])
/// a new one. [exclude] leaves one folder out (the one a file is in).
Future<FolderChoice?> pickFolder(
  BuildContext context, {
  required String conversationId,
  required String title,
  bool allowNew = true,
  String? exclude,
  bool excludeTop = false,
}) {
  return showWeCordSheet<FolderChoice>(
    context,
    title: title,
    detents: const [0.55, 0.92],
    builder: (sheetContext, controller) => _FolderChoiceList(
      conversationId: conversationId,
      controller: controller,
      allowNew: allowNew,
      exclude: exclude,
      excludeTop: excludeTop,
    ),
  );
}

class _FolderChoiceList extends ConsumerWidget {
  const _FolderChoiceList({
    required this.conversationId,
    required this.controller,
    required this.allowNew,
    required this.exclude,
    required this.excludeTop,
  });

  final String conversationId;
  final ScrollController? controller;
  final bool allowNew;
  final String? exclude;
  final bool excludeTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final info = ref.watch(groupSpaceInfoProvider(conversationId)).value;
    final folders = ref.watch(groupFoldersProvider(conversationId));
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      children: [
        SettingsGroup(
          color: c.well,
          children: [
            if (allowNew && (info?.canAdd ?? true))
              SettingsRow(
                key: const ValueKey('space-pick-new-folder'),
                icon: Icons.create_new_folder_outlined,
                title: trIn('group files', 'New folder'),
                showChevron: false,
                onTap: () => Navigator.of(
                  context,
                ).pop(const FolderChoice(null, isNew: true)),
              ),
            if (!excludeTop)
              SettingsRow(
                key: const ValueKey('space-pick-top'),
                icon: Icons.folder_open_outlined,
                title: tr('Group files'),
                subtitle: tr('Not in a folder'),
                showChevron: false,
                onTap: () =>
                    Navigator.of(context).pop(const FolderChoice(null)),
              ),
            ...folders.maybeWhen(
              data: (value) => [
                for (final folder in value.folders)
                  if (folder.id != exclude)
                    SettingsRow(
                      key: ValueKey('space-pick-folder-${folder.id}'),
                      icon: Icons.folder_outlined,
                      title: folder.name,
                      value: tr('{count} files', {'count': folder.fileCount}),
                      showChevron: false,
                      onTap: () =>
                          Navigator.of(context).pop(FolderChoice(folder)),
                    ),
              ],
              orElse: () => const <Widget>[],
            ),
          ],
        ),
        if (folders.isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (folders.hasError)
          SpaceLoadError(
            error: folders.error!,
            onRetry: () => ref.invalidate(groupFoldersProvider(conversationId)),
          ),
      ],
    );
  }
}

/// Which messages of the chat to take: its pictures and videos (for an
/// album), and with [files] its other files too (for a folder). Returns the
/// ids of the chosen messages, or null when cancelled.
Future<List<String>?> pickChatMedia(
  BuildContext context, {
  required String conversationId,
  required bool files,
}) {
  return showWeCordSheet<List<String>>(
    context,
    title: tr('Choose from this chat'),
    detents: const [0.7, 0.95],
    builder: (sheetContext, controller) => _ChatMediaChoice(
      conversationId: conversationId,
      files: files,
      controller: controller,
    ),
  );
}

class _ChatMediaChoice extends ConsumerStatefulWidget {
  const _ChatMediaChoice({
    required this.conversationId,
    required this.files,
    required this.controller,
  });

  final String conversationId;
  final bool files;
  final ScrollController? controller;

  @override
  ConsumerState<_ChatMediaChoice> createState() => _ChatMediaChoiceState();
}

class _ChatMediaChoiceState extends ConsumerState<_ChatMediaChoice> {
  final _chosen = <String>{};

  bool _isGallery(ConversationMediaItem item) {
    final file = PreviewFile.fromMediaItem(item);
    return file != null && file.kind.isGalleryMedia;
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(chatMediaProvider(widget.conversationId));
    final bottom = MediaQuery.paddingOf(context).bottom;
    return media.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => SpaceLoadError(
        error: error,
        onRetry: () => ref.invalidate(chatMediaProvider(widget.conversationId)),
      ),
      data: (items) {
        final gallery = [
          for (final item in items)
            if (_isGallery(item)) item,
        ];
        final others = widget.files
            ? [
                for (final item in items)
                  if (item.type == MessageType.file && !_isGallery(item)) item,
              ]
            : <ConversationMediaItem>[];
        if (gallery.isEmpty && others.isEmpty) {
          return SpaceEmpty(
            icon: Icons.photo_library_outlined,
            title: widget.files
                ? tr('Nothing to choose from yet')
                : tr('No pictures or videos yet'),
          );
        }
        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                controller: widget.controller,
                slivers: [
                  if (gallery.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 110,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                        itemCount: gallery.length,
                        itemBuilder: (context, index) => _ChoiceTile(
                          item: gallery[index],
                          chosen: _chosen.contains(gallery[index].messageId),
                          onTap: () => _toggle(gallery[index].messageId),
                        ),
                      ),
                    ),
                  if (others.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      sliver: SliverList.separated(
                        itemCount: others.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 6),
                        itemBuilder: (context, index) => _ChoiceRow(
                          item: others[index],
                          chosen: _chosen.contains(others[index].messageId),
                          onTap: () => _toggle(others[index].messageId),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
              child: WeCordButton(
                key: const ValueKey('space-pick-confirm'),
                label: _chosen.isEmpty
                    ? tr('Choose some first')
                    : tr('Add {count}', {'count': _chosen.length}),
                variant: WeCordButtonVariant.primary,
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_chosen.toList()),
              ),
            ),
          ],
        );
      },
    );
  }

  void _toggle(String id) {
    setState(() {
      if (!_chosen.remove(id)) {
        _chosen.add(id);
      }
    });
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.item,
    required this.chosen,
    required this.onTap,
  });

  final ConversationMediaItem item;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final file = PreviewFile.fromMediaItem(item)!;
    final radius = BorderRadius.circular(WeCordRadii.sm);
    return WeCordPressable(
      key: ValueKey('space-choice-${item.messageId}'),
      onPressed: onTap,
      selected: chosen,
      pressedScale: 0.96,
      semanticLabel: file.alt ?? file.name,
      shape: RoundedRectangleBorder(borderRadius: radius),
      builder: (context, states) => ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SpacePicture(file: file, cacheWidth: 240),
            if (chosen) ColoredBox(color: c.accent.withValues(alpha: 0.25)),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen ? c.accent : c.panel.withValues(alpha: 0.85),
                  border: Border.all(
                    color: chosen ? c.accent : c.line,
                    width: 1.5,
                  ),
                ),
                child: chosen
                    ? Icon(Icons.check_rounded, size: 16, color: c.onAccent)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.item,
    required this.chosen,
    required this.onTap,
  });

  final ConversationMediaItem item;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final file = PreviewFile.fromMediaItem(item)!;
    return WeCordPressable(
      key: ValueKey('space-choice-${item.messageId}'),
      onPressed: onTap,
      selected: chosen,
      pressedScale: 0.98,
      semanticLabel: file.name,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: chosen ? c.accentSoft : c.well,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            Icon(previewIconFor(file), color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    previewSubtitle(file),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              chosen ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: chosen ? c.accent : c.faint,
            ),
          ],
        ),
      ),
    );
  }
}
