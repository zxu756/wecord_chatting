import 'dart:async';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/group_space/group_space_models.dart';
import 'package:wecord/features/group_space/group_space_providers.dart';
import 'package:wecord/features/group_space/group_space_repository.dart';
import 'package:wecord/features/group_space/space_pickers.dart';
import 'package:wecord/features/group_space/space_upload.dart';
import 'package:wecord/features/group_space/space_widgets.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How many files can be picked from the device at once.
const spaceFileBatch = 20;

enum _AddAction { upload, fromChat }

enum _FolderAction { rename, delete }

enum _FileAction { open, rename, move, remove }

/// A folder of the group's files, or (without a folder) the files that sit
/// outside any folder.
class FolderScreen extends ConsumerStatefulWidget {
  const FolderScreen({
    required this.conversationId,
    this.folderId,
    this.title,
    super.key,
  });

  /// `/chats/:conversationId/space/folders/:folderId`.
  static String pathFor(String conversationId, String folderId) =>
      '/chats/$conversationId/space/folders/$folderId';

  /// `/chats/:conversationId/space/files`: the files outside any folder.
  static String topPathFor(String conversationId) =>
      '/chats/$conversationId/space/files';

  final String conversationId;

  /// Null: the files outside any folder.
  final String? folderId;
  final String? title;

  @override
  ConsumerState<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends ConsumerState<FolderScreen> {
  ({int done, int total})? _uploading;

  FolderRef get _ref =>
      (conversationId: widget.conversationId, folderId: widget.folderId);

  void _refresh() {
    ref.invalidate(groupFoldersProvider(widget.conversationId));
    ref.invalidate(folderFilesProvider(_ref));
  }

  SpaceFolder? _folder(SpaceFolders? folders) {
    for (final folder in folders?.folders ?? const <SpaceFolder>[]) {
      if (folder.id == widget.folderId) {
        return folder;
      }
    }
    return null;
  }

  Future<void> _add() async {
    final action = await showCircleActionMenu<_AddAction>(
      context,
      items: [
        CircleMenuItem(
          value: _AddAction.upload,
          icon: Icons.upload_file_outlined,
          label: tr('Upload files'),
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
      files: true,
    );
    if (ids == null || ids.isEmpty || !mounted) {
      return;
    }
    var result = const AddResult();
    final ok = await runSpaceAction(context, () async {
      result = await ref
          .read(groupSpaceRepositoryProvider)
          .addMessagesToFolder(widget.conversationId, widget.folderId, ids);
    });
    _refresh();
    if (ok && mounted) {
      showSpaceMessage(context, addResultText(result, toAlbum: false));
    }
  }

  Future<void> _upload() async {
    final List<XFile> files;
    try {
      files = await ref.read(chatMediaPickerProvider).pickFiles();
    } on Object catch (error) {
      if (mounted) {
        showSpaceMessage(context, errorText(error));
      }
      return;
    }
    if (files.isEmpty || !mounted) {
      return;
    }
    final picked = files.take(spaceFileBatch).toList();
    final repository = ref.read(groupSpaceRepositoryProvider);
    var done = 0;
    var failed = 0;
    Object? lastError;
    setState(() => _uploading = (done: 0, total: picked.length));
    for (final file in picked) {
      try {
        final upload = await prepareSpaceUpload(file, asIs: true);
        await repository.uploadToFolder(
          widget.conversationId,
          widget.folderId,
          upload,
        );
        done += 1;
      } on Object catch (error) {
        failed += 1;
        lastError = error;
      }
      if (!mounted) {
        return;
      }
      setState(() => _uploading = (done: done + failed, total: picked.length));
    }
    if (!mounted) {
      return;
    }
    setState(() => _uploading = null);
    _refresh();
    if (failed == 0) {
      showSpaceMessage(
        context,
        tr('{count} saved to the group files.', {'count': done}),
      );
    } else {
      final why = lastError == null ? '' : ' ${errorText(lastError)}';
      showSpaceMessage(
        context,
        '${tr('{done} added, {failed} could not be added.', {'done': done, 'failed': failed})}$why',
      );
    }
  }

  Future<void> _renameFolder(SpaceFolder folder) async {
    final name = await askSpaceName(
      context,
      title: tr('Rename folder'),
      label: tr('Folder name'),
      confirmLabel: tr('Save'),
      initial: folder.name,
    );
    if (name == null || name == folder.name || !mounted) {
      return;
    }
    await runSpaceAction(
      context,
      () =>
          ref.read(groupSpaceRepositoryProvider).renameFolder(folder.id, name),
    );
    _refresh();
  }

  Future<void> _deleteFolder(SpaceFolder folder) async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Delete the folder "{name}"?', {'name': folder.name}),
      message: folder.fileCount == 0
          ? null
          : tr(
              'Its {count} files are taken out of the group files. Files that were sent in the chat stay in the chat.',
              {'count': folder.fileCount},
            ),
      confirmLabel: trIn('group files', 'Delete folder'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    final ok = await runSpaceAction(
      context,
      () => ref.read(groupSpaceRepositoryProvider).deleteFolder(folder.id),
    );
    _refresh();
    if (ok && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _folderMenu(SpaceFolder folder) async {
    final action = await showCircleActionMenu<_FolderAction>(
      context,
      items: [
        CircleMenuItem(
          value: _FolderAction.rename,
          icon: Icons.edit_outlined,
          label: tr('Rename folder'),
        ),
        CircleMenuItem(
          value: _FolderAction.delete,
          icon: Icons.delete_outline_rounded,
          label: trIn('group files', 'Delete folder'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case _FolderAction.rename:
        await _renameFolder(folder);
      case _FolderAction.delete:
        await _deleteFolder(folder);
    }
  }

  void _open(SpaceFile file, List<SpaceFile> all) {
    final preview = file.toPreviewFile();
    unawaited(
      openFilePreview(
        context,
        file: preview,
        gallery: [
          for (final other in all)
            if (other.toPreviewFile().kind.isGalleryMedia)
              other.toPreviewFile(),
        ],
      ),
    );
  }

  Future<void> _fileMenu(SpaceFile file, List<SpaceFile> all) async {
    final action = await showCircleActionMenu<_FileAction>(
      context,
      items: [
        CircleMenuItem(
          value: _FileAction.open,
          icon: Icons.open_in_full_rounded,
          label: tr('Open'),
        ),
        if (file.canDelete) ...[
          CircleMenuItem(
            value: _FileAction.rename,
            icon: Icons.edit_outlined,
            label: tr('Rename'),
          ),
          CircleMenuItem(
            value: _FileAction.move,
            icon: Icons.drive_file_move_outline,
            label: tr('Move to...'),
          ),
          CircleMenuItem(
            value: _FileAction.remove,
            icon: Icons.delete_outline_rounded,
            label: tr('Remove from group files'),
            destructive: true,
          ),
        ],
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    final repository = ref.read(groupSpaceRepositoryProvider);
    switch (action) {
      case _FileAction.open:
        _open(file, all);
      case _FileAction.rename:
        final name = await askSpaceName(
          context,
          title: tr('Rename file'),
          label: tr('File name'),
          confirmLabel: tr('Save'),
          initial: file.name,
        );
        if (name == null || name == file.name || !mounted) {
          return;
        }
        await runSpaceAction(
          context,
          () => repository.renameFile(file.id, name),
        );
        _refresh();
      case _FileAction.move:
        final target = await pickFolder(
          context,
          conversationId: widget.conversationId,
          title: tr('Move to...'),
          allowNew: false,
          exclude: widget.folderId,
          excludeTop: widget.folderId == null,
        );
        if (target == null || !mounted) {
          return;
        }
        await runSpaceAction(
          context,
          () => repository.moveFile(file.id, target.folder?.id),
        );
        _refresh();
      case _FileAction.remove:
        final confirmed = await confirmCircleAction(
          context,
          title: tr('Remove "{name}"?', {'name': file.name}),
          message: file.fromChat
              ? tr('The file stays in the chat.')
              : tr('The file is deleted.'),
          confirmLabel: tr('Remove'),
        );
        if (!confirmed || !mounted) {
          return;
        }
        await runSpaceAction(context, () => repository.removeFile(file.id));
        _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final info =
        ref.watch(groupSpaceInfoProvider(widget.conversationId)).value ??
        const GroupSpaceInfo();
    final folders = ref.watch(groupFoldersProvider(widget.conversationId));
    final folder = _folder(folders.value);
    final files = ref.watch(folderFilesProvider(_ref));
    final title = widget.folderId == null
        ? tr('Group files')
        : folder?.name ?? widget.title ?? tr('Folder');
    final add = info.canAdd && _uploading == null;
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
                        key: const ValueKey('folder-add'),
                        icon: Icons.upload_file_outlined,
                        tooltip: tr('Add files'),
                        variant: WeCordButtonVariant.onPaper,
                        onPressed: () => unawaited(_add()),
                      ),
                    if (folder != null && folder.canManage)
                      WeCordIconButton(
                        key: const ValueKey('folder-menu'),
                        icon: Icons.more_horiz_rounded,
                        tooltip: tr('Folder options'),
                        variant: WeCordButtonVariant.onPaper,
                        onPressed: () => unawaited(_folderMenu(folder)),
                      ),
                  ],
                ),
                if (!info.enabled) const SpaceOffNotice(),
                if (_uploading case final progress?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          key: const ValueKey('folder-upload-progress'),
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
                  child: files.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) =>
                        SpaceLoadError(error: error, onRetry: _refresh),
                    data: (list) => list.isEmpty
                        ? SpaceEmpty(
                            icon: Icons.folder_open_outlined,
                            title: tr('No files here yet'),
                            message: tr(
                              'Upload a file, or long-press a file in the chat and choose Save to group files.',
                            ),
                            actionLabel: add ? tr('Add files') : null,
                            onAction: () => unawaited(_add()),
                          )
                        : ListView.separated(
                            key: const ValueKey('folder-file-list'),
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                            itemCount: list.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => _FileRow(
                              file: list[index],
                              onOpen: () => _open(list[index], list),
                              onMore: () =>
                                  unawaited(_fileMenu(list[index], list)),
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

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.onOpen,
    required this.onMore,
  });

  final SpaceFile file;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final preview = file.toPreviewFile();
    final tone = previewToneFor(preview, c);
    return WeCordPressable(
      key: ValueKey('folder-file-${file.id}'),
      onPressed: onOpen,
      onLongPress: onMore,
      pressedScale: 0.98,
      semanticLabel: '${file.name}, ${previewSubtitle(preview)}',
      excludeSemantics: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      builder: (context, states) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(WeCordRadii.xl),
          boxShadow: context.tokens.shadows.hairline,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tone.fill,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Icon(previewIconFor(preview), color: tone.foreground),
            ),
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
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewSubtitle(preview),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ],
              ),
            ),
            WeCordIconButton(
              key: ValueKey('folder-file-more-${file.id}'),
              icon: Icons.more_horiz_rounded,
              tooltip: tr('More'),
              variant: WeCordButtonVariant.ghost,
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}
